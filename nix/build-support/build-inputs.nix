# Runtime library inputs for cmux Linux GTK4 build.
# Wayland-only — no X11 paths (per architecture decision).
{
  pkgs,
  lib,
  stdenv,
}:
[
  pkgs.libGL
]
++ lib.optionals stdenv.hostPlatform.isLinux [
  # Core libraries
  pkgs.bzip2
  pkgs.expat
  pkgs.fontconfig
  pkgs.freetype
  pkgs.harfbuzz
  pkgs.libpng
  pkgs.libxml2
  pkgs.oniguruma
  pkgs.simdutf
  pkgs.zlib

  # Rendering
  pkgs.glslang
  pkgs.spirv-cross

  # Input
  pkgs.libxkbcommon

  # GTK4 / libadwaita stack
  pkgs.glib
  pkgs.gobject-introspection
  pkgs.gsettings-desktop-schemas
  pkgs.gst_all_1.gst-plugins-base
  pkgs.gst_all_1.gst-plugins-good
  pkgs.gst_all_1.gstreamer
  pkgs.gtk4
  pkgs.libadwaita

  # Wayland
  pkgs.gtk4-layer-shell
  pkgs.wayland

  # cmux-specific: browser panel + secrets
  pkgs.webkitgtk_6_0
  pkgs.libsecret
]
