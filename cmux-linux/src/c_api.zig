/// GTK4 and libadwaita C bindings via @cImport.
/// Ghostty C API bindings.

const std = @import("std");

pub const gtk = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("adwaita.h");
    @cInclude("glib-unix.h");
});

pub const ghostty = @cImport({
    @cInclude("ghostty.h");
});

// Re-export commonly used types
pub const GtkWidget = gtk.GtkWidget;
pub const GtkApplication = gtk.GtkApplication;
pub const GApplication = gtk.GApplication;
pub const AdwApplicationWindow = gtk.AdwApplicationWindow;
pub const AdwHeaderBar = gtk.AdwHeaderBar;
pub const GtkGLArea = gtk.GtkGLArea;

// Ghostty types
pub const ghostty_app_t = ghostty.ghostty_app_t;
pub const ghostty_surface_t = ghostty.ghostty_surface_t;
pub const ghostty_config_t = ghostty.ghostty_config_t;
