/// WebAuthn bridge coordinator for WebKitGTK 6.0.
///
/// Injects the JavaScript bridge into browser panels and handles
/// navigator.credentials.create/get requests by routing them through
/// libctap2 for hardware security key (YubiKey) authentication.
///
/// Parallel to macOS WebAuthnCoordinator.swift but using GTK signals
/// instead of WKScriptMessageHandlerWithReply.

const std = @import("std");
const c = @import("c_api.zig");
const bridge_js = @import("webauthn_bridge_js.zig");

const log = std.log.scoped(.webauthn);

pub const WebAuthnBridge = struct {
    web_view: *c.WebKitWebView,

    /// Install the WebAuthn bridge on a browser panel's web view.
    /// Injects the JavaScript and registers the message handler signal.
    pub fn install(self: *WebAuthnBridge, web_view: *c.WebKitWebView) !void {
        self.web_view = web_view;

        // Get or create the user content manager
        const ucm = c.webkit.webkit_web_view_get_user_content_manager(web_view) orelse
            return error.NoUserContentManager;

        // Create and inject the JavaScript bridge at document start, main frame only
        const script = c.webkit.webkit_user_script_new(
            bridge_js.BRIDGE_SOURCE,
            c.webkit.WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
            0, // all frames = 0, will be filtered by JS guard
            null, // allow list
            null, // block list
        ) orelse return error.ScriptCreationFailed;

        c.webkit.webkit_user_content_manager_add_script(ucm, script);

        // Register the message handler channel
        _ = c.webkit.webkit_user_content_manager_register_script_message_handler(
            ucm,
            bridge_js.MESSAGE_HANDLER_NAME,
            null, // world name (default)
        );

        // Connect the signal for receiving messages from JavaScript
        _ = c.gtk.g_signal_connect_data(
            @ptrCast(@alignCast(ucm)),
            "script-message-received::" ++ bridge_js.MESSAGE_HANDLER_NAME,
            @ptrCast(&onScriptMessage),
            self,
            null,
            0,
        );

        log.info("WebAuthn bridge installed", .{});
    }

    /// Signal handler: receives JSON messages from the JavaScript bridge.
    /// Message format: { "type": "create"|"get", "options": {...}, "origin": "..." }
    fn onScriptMessage(
        _: ?*anyopaque, // user content manager
        js_result: ?*anyopaque, // WebKitJavascriptResult
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        const self: *WebAuthnBridge = @ptrCast(@alignCast(user_data));
        _ = self;
        _ = js_result;

        // TODO: Extract JSON from JSCValue
        // TODO: Parse type, options, origin
        // TODO: Dispatch to CTAP2 handler on background thread
        // TODO: Reply to JavaScript with credential response

        log.info("WebAuthn message received (handler stub)", .{});
    }
};
