# cmux development shell.
# Provides all dependencies for building cmux on Linux (GTK4/libadwaita)
# and macOS (Xcode handles most deps natively).
{
  mkShell,
  lib,
  stdenv,
  # Build tools
  pkg-config,
  zig,
  python3,
  nodejs,
  # Linting / formatting
  alejandra,
  shellcheck,
  # Linux GTK4 stack
  gtk4,
  libadwaita,
  webkitgtk_6_0,
  glib,
  gobject-introspection,
  wayland,
  wayland-scanner,
  wayland-protocols,
  gtk4-layer-shell,
  # Linux media
  gst_all_1,
  # Linux rendering + OpenGL
  libGL,
  bzip2,
  expat,
  fontconfig,
  freetype,
  harfbuzz,
  libpng,
  libxml2,
  oniguruma,
  simdutf,
  zlib,
  glslang,
  spirv-cross,
  libxkbcommon,
  # cmux-specific
  libsecret,
  libnotify,
  # Testing / VMs
  xorg,
  qemu,
  # Icons
  adwaita-icon-theme,
  hicolor-icon-theme,
  glycin-loaders,
  librsvg,
  # misc
  jq,
  pkgs,
}: let
  ld_library_path = import ./build-support/ld-library-path.nix {
    inherit pkgs lib stdenv;
  };
  gi_typelib_path = import ./build-support/gi-typelib-path.nix {
    inherit pkgs lib stdenv;
  };
in
  mkShell {
    name = "cmux";
    packages =
      [
        # Core build tools
        zig
        pkg-config
        python3
        nodejs
        jq

        # Linting
        alejandra
        shellcheck

        # GTK4 (needed on all platforms for dist tarballs)
        gtk4
        libadwaita
      ]
      ++ lib.optionals stdenv.hostPlatform.isLinux [
        # VM testing + headless display
        qemu
        xorg.xorgserver

        # Rendering deps (OpenGL via libGL/Mesa)
        libGL
        bzip2
        expat
        fontconfig
        freetype
        harfbuzz
        libpng
        libxml2
        oniguruma
        simdutf
        zlib
        glslang
        spirv-cross
        libxkbcommon

        # GTK4 / Wayland
        glib
        gobject-introspection
        wayland
        wayland-scanner
        wayland-protocols
        gtk4-layer-shell
        gst_all_1.gstreamer
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good

        # cmux-specific
        webkitgtk_6_0
        libsecret
        libnotify

        # Icons in dev shell
        glycin-loaders
        librsvg
      ];

    LD_LIBRARY_PATH = ld_library_path;
    GI_TYPELIB_PATH = gi_typelib_path;

    shellHook =
      ''
        echo "cmux dev shell (zig $(zig version 2>/dev/null || echo 'not found'))"
      ''
      + (lib.optionalString stdenv.hostPlatform.isLinux ''
        # GTK icon/settings data
        export XDG_DATA_DIRS=$XDG_DATA_DIRS:${hicolor-icon-theme}/share:${adwaita-icon-theme}/share
        export XDG_DATA_DIRS=$XDG_DATA_DIRS:$GSETTINGS_SCHEMAS_PATH

        echo "  Linux: zig build -Dapp-runtime=cmux"
        echo "  VMs:   nix run .#wayland-gnome"
      '')
      + (lib.optionalString stdenv.hostPlatform.isDarwin ''
        # macOS: rely on system Xcode, not Nix SDK
        unset SDKROOT
        unset DEVELOPER_DIR
        export PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '$0 !~ /xcrun/ || $0 == "/usr/bin" {print}' | sed 's/:$//')

        echo "  macOS: ./scripts/reload.sh --tag dev"
      '');
  }
