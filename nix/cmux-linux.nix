# Build cmux-linux GTK4 terminal binary.
# Links against a pre-built libghostty derivation.
# No build.zig.zon — only system library linkage.
{
  lib,
  stdenv,
  pkg-config,
  zig_0_15,
  libghostty,
  pkgs,
}:
let
  buildInputs = import ./build-support/build-inputs.nix {inherit pkgs lib stdenv;};
in
  stdenv.mkDerivation {
    pname = "cmux-linux";
    version = "0.73.0-lab";
    src = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions [
        ../cmux-linux
      ];
    };

    nativeBuildInputs = [zig_0_15 pkg-config];
    buildInputs = buildInputs ++ [libghostty];

    dontConfigure = true;
    dontSetZigDefaultFlags = true;

    buildPhase = ''
      export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache"
      export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"
      export HOME="$TMPDIR"

      # Symlink libghostty into expected relative path for build.zig
      mkdir -p ghostty/zig-out/lib ghostty/include
      ln -sf ${libghostty}/lib/* ghostty/zig-out/lib/
      ln -sf ${libghostty}/include/* ghostty/include/

      cd cmux-linux
      zig build -Doptimize=ReleaseFast
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp cmux-linux/zig-out/bin/cmux $out/bin/cmux-linux
    '';

    meta = with lib; {
      description = "cmux Linux GTK4 terminal multiplexer";
      homepage = "https://github.com/Jesssullivan/cmux";
      platforms = platforms.linux;
    };
  }
