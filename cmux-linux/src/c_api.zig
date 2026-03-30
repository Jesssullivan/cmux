/// GTK4, libadwaita, WebKitGTK, and Ghostty C API bindings via @cImport.

const std = @import("std");

pub const gtk = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("adwaita.h");
    @cInclude("glib-unix.h");
});

pub const webkit = @cImport({
    @cInclude("webkit/webkit.h");
});

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

// WebKitGTK types
pub const WebKitWebView = webkit.WebKitWebView;
pub const WebKitSettings = webkit.WebKitSettings;
pub const WebKitUserContentManager = webkit.WebKitUserContentManager;

// Ghostty types
pub const ghostty_app_t = ghostty.ghostty_app_t;
pub const ghostty_surface_t = ghostty.ghostty_surface_t;
pub const ghostty_config_t = ghostty.ghostty_config_t;
