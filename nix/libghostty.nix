# Build libghostty as a static/shared library from the ghostty source.
# Uses -Dapp-runtime=none to produce library outputs only (no executable).
# Reuses ghostty's build.zig.zon.nix for Zig dependency resolution.
{
  lib,
  stdenv,
  callPackage,
  pkg-config,
  zig_0_15,
  git,
  ncurses,
  ghosttySrc,
  optimize ? "ReleaseFast",
  pkgs,
}:
let
  buildInputs = import ./build-support/build-inputs.nix {inherit pkgs lib stdenv;};
  deps = callPackage (ghosttySrc + "/build.zig.zon.nix") {
    inherit zig_0_15;
    name = "ghostty-cache";
  };
in
  stdenv.mkDerivation {
    pname = "libghostty";
    version = "1.3.0-dev";
    src = ghosttySrc;

    nativeBuildInputs = [zig_0_15 pkg-config git ncurses];
    inherit buildInputs;

    dontConfigure = true;
    dontSetZigDefaultFlags = true;

    buildPhase = ''
      export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache"
      export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"
      export HOME="$TMPDIR"

      zig build \
        --system ${deps} \
        -Dapp-runtime=none \
        -Drenderer=opengl \
        -Dgtk-wayland=true \
        -Dcpu=baseline \
        -Doptimize=${optimize}
    '';

    installPhase = ''
      mkdir -p $out/lib $out/include
      cp zig-out/lib/libghostty.a $out/lib/ 2>/dev/null || true
      cp zig-out/lib/libghostty.so $out/lib/ 2>/dev/null || true
      cp -r include/* $out/include/
    '';

    meta = with lib; {
      description = "Ghostty terminal emulation library (libghostty)";
      homepage = "https://github.com/Jesssullivan/ghostty";
      platforms = platforms.linux;
    };
  }
