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

    # WORKAROUND: Zig compiles and executes build-time tools (framegen,
    # helpgen, mdgen, props-unigen, symbols-unigen, uucode_build_tables)
    # which are dynamically-linked ELF binaries with /lib64/ld-linux-x86-64.so.2
    # as interpreter. This path doesn't exist in the Nix sandbox.
    # See: https://github.com/ziglang/zig/issues/6350 (still open)
    # __noChroot allows the build to access the host /lib64.
    # TODO: Remove when Zig supports configurable build-time dynamic linker.
    __noChroot = true;

    # The zig overlay doesn't provide a setup hook, so we use explicit phases.
    # Flags aligned with upstream ghostty/nix/package.nix.
    dontConfigure = true;
    dontInstall = true;

    buildPhase = ''
      runHook preBuild

      export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache"
      export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"
      export HOME="$TMPDIR"

      # -fsys: use system spirv-cross and glslang (avoids C++ compilation
      #   errors from building these complex C++ libs in Nix sandbox)
      # -Dsimd=false: skip simdutf/highway C++ deps (musl/glibc conflict)
      zig build \
        --system ${finalAttrs.deps} \
        -Dapp-runtime=none \
        -Dgtk-wayland=true \
        -Dcpu=baseline \
        -Doptimize=${optimize} \
        -Dstrip=${lib.boolToString strip} \
        -Dpie=true \
        -Dsimd=false \
        -fsys=spirv-cross \
        -fsys=glslang \
        -j$NIX_BUILD_CORES

      runHook postBuild
    '';

    postBuild = ''
      mkdir -p $out/lib $out/include
      # Library outputs from zig build (static and/or shared).
      #
      # Compat shim: ghostty upstream commit 4fd16ef9b
      # ("build: install ghostty-internal dll/static with new names")
      # renamed libghostty.{so,a} -> ghostty-internal.{so,a} (no `lib`
      # prefix on Linux). Accept either name and install under the
      # historical libghostty.{so,a} so downstream consumers
      # (cmux-linux/build.zig linkSystemLibrary, .deb/.rpm packagers)
      # don't have to change. Remove once the rename is either reverted
      # or fully absorbed.
      for ext in a so; do
        if [ -f zig-out/lib/libghostty.$ext ]; then
          cp zig-out/lib/libghostty.$ext $out/lib/
        elif [ -f zig-out/lib/ghostty-internal.$ext ]; then
          cp zig-out/lib/ghostty-internal.$ext $out/lib/libghostty.$ext
        else
          echo "WARN: no libghostty.$ext (neither old nor new name) produced"
        fi
      done
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
