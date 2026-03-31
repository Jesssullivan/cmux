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

    # The zig overlay doesn't provide a setup hook, so we use explicit phases.
    # Flags aligned with upstream ghostty/nix/package.nix.
    dontConfigure = true;
    dontInstall = true;

    buildPhase = ''
      runHook preBuild

      export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache"
      export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"
      export HOME="$TMPDIR"

      zig build \
        --system ${finalAttrs.deps} \
        -Dapp-runtime=none \
        -Dgtk-wayland=true \
        -Dcpu=baseline \
        -Doptimize=${optimize} \
        -Dstrip=${lib.boolToString strip} \
        -Dpie=true \
        -j$NIX_BUILD_CORES

      runHook postBuild
    '';

    postBuild = ''
      mkdir -p $out/lib $out/include
      # Library outputs from zig build (static and/or shared)
      cp zig-out/lib/libghostty.a $out/lib/ || echo "WARN: no static lib"
      cp zig-out/lib/libghostty.so $out/lib/ || echo "WARN: no shared lib"
      # Headers for downstream consumers
      cp -r include/* $out/include/
      # Verify at least one library was produced
      test -f $out/lib/libghostty.a || test -f $out/lib/libghostty.so || \
        { echo "ERROR: no libghostty library produced"; exit 1; }
    '';

    meta = {
      description = "Ghostty terminal emulation library (libghostty)";
      homepage = "https://github.com/Jesssullivan/ghostty";
      license = lib.licenses.mit;
      platforms = ["x86_64-linux" "aarch64-linux"];
    };
  })
