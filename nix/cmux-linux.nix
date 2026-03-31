# Build cmux-linux GTK4 terminal binary.
# Links against a pre-built libghostty derivation.
# No build.zig.zon — only system library linkage.
#
# Uses the nixpkgs zig hook for cache management and build phase,
# with custom source layout to provide libghostty at the expected path.
{
  lib,
  stdenv,
  pkg-config,
  zig_0_15,
  libghostty,
  pkgs,
}: let
  buildInputs = import ./build-support/build-inputs.nix {inherit pkgs lib stdenv;};
  gi_typelib_path = import ./build-support/gi-typelib-path.nix {
    inherit pkgs lib stdenv;
  };
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

    GI_TYPELIB_PATH = gi_typelib_path;

    # Same as libghostty: Zig build-time tools need /lib64 dynamic linker.
    # See: ziglang/zig#6350
    __noChroot = true;

    dontConfigure = true;
    dontUseZigBuild = true;
    dontUseZigInstall = true;

    buildPhase = ''
      runHook preBuild

      export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache"
      export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"

      # Symlink libghostty into expected relative path for build.zig
      mkdir -p ghostty/zig-out/lib ghostty/include
      ln -sf ${libghostty}/lib/* ghostty/zig-out/lib/
      ln -sf ${libghostty}/include/* ghostty/include/

      cd cmux-linux
      zig build -Doptimize=ReleaseFast -j$NIX_BUILD_CORES

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      cp cmux-linux/zig-out/bin/cmux $out/bin/cmux-linux

      runHook postInstall
    '';

    meta = with lib; {
      description = "cmux Linux GTK4 terminal multiplexer";
      homepage = "https://github.com/Jesssullivan/cmux";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  }
