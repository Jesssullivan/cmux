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
    buildInputs = buildInputs ++ [pkgs.glibc.dev];

    dontConfigure = true;
    dontSetZigDefaultFlags = true;

    # Zig needs to find the C library headers in the Nix sandbox
    env.ZIG_LOCAL_CACHE_DIR = "/tmp/zig-cache";
    env.ZIG_GLOBAL_CACHE_DIR = "/tmp/zig-global";

    buildPhase = ''
      export HOME="$TMPDIR"

      # Help Zig find the C compiler and sysroot in Nix sandbox
      export CC="${stdenv.cc}/bin/cc"

      zig build \
        --system ${deps} \
        -Dapp-runtime=none \
        -Drenderer=opengl \
        -Dgtk-wayland=true \
        -Dcpu=baseline \
        -Doptimize=${optimize} \
        -Dpie=true
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
