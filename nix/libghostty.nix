# Build libghostty as a static/shared library from the ghostty source.
# Uses -Dapp-runtime=none to produce library outputs only (no executable).
# Pattern follows ghostty/nix/package.nix closely.
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
  ghosttySrc,
  optimize ? "ReleaseFast",
  pkgs,
}:
let
  gi_typelib_path = import ./build-support/gi-typelib-path.nix {
    inherit pkgs lib stdenv;
  };
  buildInputs = import ./build-support/build-inputs.nix {inherit pkgs lib stdenv;};
  deps = callPackage (ghosttySrc + "/build.zig.zon.nix") {
    inherit zig_0_15;
    name = "ghostty-cache";
  };
  strip = optimize != "Debug" && optimize != "ReleaseSafe";
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "libghostty";
    version = "1.3.0-dev";

    # ghosttySrc is a flake input (store path), use directly as src
    src = ghosttySrc;

    inherit deps;

    nativeBuildInputs = [
      git
      ncurses
      pkg-config
      zig_0_15
      gobject-introspection
      wayland-scanner
      wayland-protocols
    ];

    inherit buildInputs;

    dontStrip = !strip;

    GI_TYPELIB_PATH = gi_typelib_path;

    dontSetZigDefaultFlags = true;

    # Use zigBuildFlags (processed by stdenv Zig hook) instead of manual buildPhase
    zigBuildFlags = [
      "--system"
      "${finalAttrs.deps}"
      "-Dapp-runtime=none"
      "-Drenderer=opengl"
      "-Dgtk-wayland=true"
      "-Dcpu=baseline"
      "-Doptimize=${optimize}"
      "-Dstrip=${lib.boolToString strip}"
    ];

    # libghostty outputs go to zig-out/ — copy to $out
    postInstall = ''
      mkdir -p $out/lib $out/include
      cp zig-out/lib/libghostty.a $out/lib/ 2>/dev/null || true
      cp zig-out/lib/libghostty.so $out/lib/ 2>/dev/null || true
      cp -r include/* $out/include/
    '';

    meta = {
      description = "Ghostty terminal emulation library (libghostty)";
      homepage = "https://github.com/Jesssullivan/ghostty";
      license = lib.licenses.mit;
      platforms = ["x86_64-linux" "aarch64-linux"];
    };
  })
