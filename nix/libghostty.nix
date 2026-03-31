# Build libghostty as a static/shared library from the ghostty source.
# Uses -Dapp-runtime=none to produce library outputs only (no executable).
# Reuses ghostty's build.zig.zon.nix for Zig dependency resolution.
#
# Aligned with upstream ghostty/nix/package.nix — uses the nixpkgs zig hook
# (zigBuildFlags + --system) instead of a manual buildPhase.
{
  lib,
  stdenv,
  callPackage,
  pkg-config,
  zig_0_15,
  git,
  ncurses,
  gobject-introspection,
  wayland-protocols,
  wayland-scanner,
  libxml2,
  gettext,
  pandoc,
  ghosttySrc,
  optimize ? "ReleaseFast",
  pkgs,
}: let
  gi_typelib_path = import ./build-support/gi-typelib-path.nix {
    inherit pkgs lib stdenv;
  };
  buildInputs = import ./build-support/build-inputs.nix {inherit pkgs lib stdenv;};
  strip = optimize != "Debug" && optimize != "ReleaseSafe";
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "libghostty";
    version = "1.3.0-dev";

    src = ghosttySrc;

    deps = callPackage (ghosttySrc + "/build.zig.zon.nix") {
      inherit zig_0_15;
      name = "ghostty-cache-${finalAttrs.version}";
    };

    nativeBuildInputs = [
      git
      ncurses
      pandoc
      pkg-config
      zig_0_15
      gobject-introspection
      wayland-scanner
      wayland-protocols
      libxml2
      gettext
    ];

    inherit buildInputs;

    dontStrip = !strip;

    GI_TYPELIB_PATH = gi_typelib_path;

    # Use the nixpkgs zig hook (matches upstream ghostty/nix/package.nix)
    dontSetZigDefaultFlags = true;

    zigBuildFlags = [
      "--system"
      "${finalAttrs.deps}"
      "-Dapp-runtime=none"
      "-Dgtk-wayland=true"
      "-Dcpu=baseline"
      "-Doptimize=${optimize}"
      "-Dstrip=${lib.boolToString strip}"
      "-Dpie=true"
    ];

    # Custom install: extract library + headers (not a full app)
    dontUseZigInstall = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib $out/include
      cp zig-out/lib/libghostty.a $out/lib/ 2>/dev/null || true
      cp zig-out/lib/libghostty.so $out/lib/ 2>/dev/null || true
      cp -r include/* $out/include/

      runHook postInstall
    '';

    meta = {
      description = "Ghostty terminal emulation library (libghostty)";
      homepage = "https://github.com/Jesssullivan/ghostty";
      license = lib.licenses.mit;
      platforms = ["x86_64-linux" "aarch64-linux"];
    };
  })
