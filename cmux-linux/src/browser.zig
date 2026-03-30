/// Browser panel: embeds a WebKitGTK 6.0 WebView in the split tree.
///
/// Handles navigation, title/URL tracking, and signal connections.
/// Parallel to surface.zig (terminal panels) in the panel architecture.

const std = @import("std");
const c = @import("c_api.zig");
const WebAuthnBridge = @import("webauthn_bridge.zig").WebAuthnBridge;

const log = std.log.scoped(.browser);

/// State for a single browser panel.
pub const BrowserView = struct {
    /// The WebKitWebView instance.
    web_view: *c.WebKitWebView,
    /// The WebKitSettings for this view.
    settings: *c.WebKitSettings,
    /// Current URL (updated on navigation).
    current_url: ?[*:0]const u8 = null,
    /// Current page title (updated on load).
    current_title: ?[*:0]const u8 = null,
    /// Whether a page is currently loading.
    is_loading: bool = false,
    /// WebAuthn bridge (FIDO2/YubiKey support).
    webauthn_bridge: ?*WebAuthnBridge = null,

    /// Create a new browser view and optionally navigate to a URL.
    pub fn create(initial_url: ?[]const u8) !*c.GtkWidget {
        // Create settings with sane defaults
        const settings: *c.WebKitSettings = @ptrCast(c.webkit.webkit_settings_new() orelse
            return error.SettingsCreationFailed);

        // Enable developer extras (F12 inspector)
        c.webkit.webkit_settings_set_enable_developer_extras(settings, 1);
        // Enable JavaScript
        c.webkit.webkit_settings_set_enable_javascript(settings, 1);
        // Allow autoplay (for media-heavy sites)
        c.webkit.webkit_settings_set_media_playback_requires_user_gesture(settings, 0);

        // Create the web view
        const web_view: *c.WebKitWebView = @ptrCast(c.webkit.webkit_web_view_new() orelse
            return error.WebViewCreationFailed);

        // Apply settings
        c.webkit.webkit_web_view_set_settings(web_view, settings);

        // Make the widget expand to fill available space
        const widget: *c.GtkWidget = @ptrCast(@alignCast(web_view));
        c.gtk.gtk_widget_set_hexpand(widget, 1);
        c.gtk.gtk_widget_set_vexpand(widget, 1);
        c.gtk.gtk_widget_set_focusable(widget, 1);
        c.gtk.gtk_widget_set_can_focus(widget, 1);

        // Allocate browser state and store as widget data
        const alloc = std.heap.c_allocator;
        const view = try alloc.create(BrowserView);
        view.* = .{
            .web_view = web_view,
            .settings = settings,
        };
        c.gtk.g_object_set_data(@ptrCast(@alignCast(web_view)), "cmux-browser", view);

        // Connect signals
        _ = c.gtk.g_signal_connect_data(
            @ptrCast(@alignCast(web_view)),
            "load-changed",
            @ptrCast(&onLoadChanged),
            view,
            null,
            0,
        );

        _ = c.gtk.g_signal_connect_data(
            @ptrCast(@alignCast(web_view)),
            "notify::title",
            @ptrCast(&onTitleChanged),
            view,
            null,
            0,
        );

        _ = c.gtk.g_signal_connect_data(
            @ptrCast(@alignCast(web_view)),
            "notify::uri",
            @ptrCast(&onUriChanged),
            view,
            null,
            0,
        );

        // Install WebAuthn bridge for FIDO2/YubiKey support
        const webauthn = alloc.create(WebAuthnBridge) catch null;
        if (webauthn) |wa| {
            wa.install(web_view) catch |err| {
                log.warn("WebAuthn bridge install failed: {}", .{err});
            };
            view.webauthn_bridge = wa;
        }

        // Navigate to initial URL if provided
        if (initial_url) |url| {
            // Need null-terminated string for C API
            const url_z = alloc.dupeZ(u8, url) catch null;
            if (url_z) |z| {
                c.webkit.webkit_web_view_load_uri(web_view, z.ptr);
                alloc.free(z);
            }
        }

        log.info("Browser panel created", .{});
        return widget;
    }

    /// Navigate to a URL.
    pub fn navigate(self: *BrowserView, url: [*:0]const u8) void {
        c.webkit.webkit_web_view_load_uri(self.web_view, url);
    }

    /// Go back in navigation history.
    pub fn goBack(self: *BrowserView) void {
        c.webkit.webkit_web_view_go_back(self.web_view);
    }

    /// Go forward in navigation history.
    pub fn goForward(self: *BrowserView) void {
        c.webkit.webkit_web_view_go_forward(self.web_view);
    }

    /// Reload the current page.
    pub fn reload(self: *BrowserView) void {
        c.webkit.webkit_web_view_reload(self.web_view);
    }

    /// Get the current URI (may be null).
    pub fn getUri(self: *const BrowserView) ?[*:0]const u8 {
        return c.webkit.webkit_web_view_get_uri(self.web_view);
    }

    /// Get the current page title (may be null).
    pub fn getTitle(self: *const BrowserView) ?[*:0]const u8 {
        return c.webkit.webkit_web_view_get_title(self.web_view);
    }

    /// Check if the view can go back.
    pub fn canGoBack(self: *const BrowserView) bool {
        return c.webkit.webkit_web_view_can_go_back(self.web_view) != 0;
    }

    /// Check if the view can go forward.
    pub fn canGoForward(self: *const BrowserView) bool {
        return c.webkit.webkit_web_view_can_go_forward(self.web_view) != 0;
    }

    // ── Signal Handlers ─────────────────────────────────────────────────

    fn onLoadChanged(_: *c.WebKitWebView, load_event: c_uint, view: *BrowserView) callconv(.c) void {
        // WebKitLoadEvent: 0=STARTED, 1=REDIRECTED, 2=COMMITTED, 3=FINISHED
        view.is_loading = (load_event != 3);
    }

    fn onTitleChanged(_: *c.WebKitWebView, _: ?*anyopaque, view: *BrowserView) callconv(.c) void {
        view.current_title = c.webkit.webkit_web_view_get_title(view.web_view);
    }

    fn onUriChanged(_: *c.WebKitWebView, _: ?*anyopaque, view: *BrowserView) callconv(.c) void {
        view.current_url = c.webkit.webkit_web_view_get_uri(view.web_view);
    }
};

/// Get the BrowserView from a GtkWidget (if it's a browser panel).
pub fn fromWidget(widget: *c.GtkWidget) ?*BrowserView {
    const data = c.gtk.g_object_get_data(@ptrCast(@alignCast(widget)), "cmux-browser");
    if (data) |d| return @ptrCast(@alignCast(d));
    return null;
}
