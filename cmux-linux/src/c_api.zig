/// GTK4, libadwaita, WebKitGTK, and Ghostty C API bindings via @cImport.

const std = @import("std");
const build_options = @import("build_options");

/// Whether WebKitGTK is available (false on RHEL/Rocky builds with -Dno-webkit).
pub const has_webkit = build_options.enable_webkit;

pub const gtk = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("adwaita.h");
    @cInclude("glib-unix.h");
});

/// WebKitGTK bindings — only imported when built with WebKitGTK support.
/// On RHEL/Rocky where WebKitGTK is unavailable, this is an empty struct
/// and browser panel code paths are compile-time disabled.
pub const webkit = if (has_webkit) @cImport({
    @cInclude("webkit/webkit.h");
}) else struct {};

pub const ghostty = @cImport({
    @cInclude("ghostty.h");
});

// Re-export commonly used GTK types
pub const GtkWidget = gtk.GtkWidget;
pub const GtkApplication = gtk.GtkApplication;
pub const GApplication = gtk.GApplication;
pub const AdwApplicationWindow = gtk.AdwApplicationWindow;
pub const AdwHeaderBar = gtk.AdwHeaderBar;
pub const GtkGLArea = gtk.GtkGLArea;

// WebKitGTK types (opaque stubs when WebKitGTK is unavailable)
pub const WebKitWebView = if (has_webkit) webkit.WebKitWebView else anyopaque;
pub const WebKitSettings = if (has_webkit) webkit.WebKitSettings else anyopaque;
pub const WebKitUserContentManager = if (has_webkit) webkit.WebKitUserContentManager else anyopaque;

// Ghostty types
pub const ghostty_app_t = ghostty.ghostty_app_t;
pub const ghostty_surface_t = ghostty.ghostty_surface_t;
pub const ghostty_config_t = ghostty.ghostty_config_t;
