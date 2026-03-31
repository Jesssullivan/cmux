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

  # Get the Nix dynamic linker path for the build platform
  dynamicLinker = "${stdenv.cc.libc}/lib/ld-linux-x86-64.so.2";
in
  stdenv.mkDerivation {
    pname = "libghostty";
    version = "1.3.0-dev";
    src = ghosttySrc;

    nativeBuildInputs = [
      git ncurses pkg-config zig_0_15 pkgs.pandoc pkgs.patchelf
      gobject-introspection wayland-scanner wayland-protocols
    ];
    inherit buildInputs;

    GI_TYPELIB_PATH = gi_typelib_path;

    dontConfigure = true;
    dontInstall = true;

    buildPhase = ''
      runHook preBuild

      export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache"
      export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"
      export HOME="$TMPDIR"

      # Zig compiles and runs build-time tools (framegen) which get linked
      # against /lib64/ld-linux-x86-64.so.2. In Nix sandbox this doesn't
      # exist. Wrap zig to patchelf any freshly-compiled ELF before Zig
      # tries to execute it.
      REAL_ZIG="$(which zig)"
      mkdir -p "$TMPDIR/wrapbin"
      cat > "$TMPDIR/wrapbin/zig" <<WRAPPER
      #!/usr/bin/env bash
      # Run real zig, then if it produced executables in zig-cache, patchelf them
      "\$REAL_ZIG" "\$@"
      ret=\$?
      # Patchelf any new ELFs in zig-cache (best effort, ignore failures)
      find "$TMPDIR/zig-cache" -type f -executable -newer "$TMPDIR/.zig-stamp" 2>/dev/null | while read f; do
        file "\$f" 2>/dev/null | grep -q "ELF" && patchelf --set-interpreter ${dynamicLinker} "\$f" 2>/dev/null || true
      done
      exit \$ret
      WRAPPER
      chmod +x "$TMPDIR/wrapbin/zig"
      touch "$TMPDIR/.zig-stamp"

      # Use system spirv-cross and glslang (avoids C++ in Zig's sandbox)
      # Disable SIMD (avoids simdutf/highway C++ deps)
      PATH="$TMPDIR/wrapbin:$PATH" zig build \
        --system ${deps} \
        -Dapp-runtime=none \
        -Drenderer=opengl \
        -Dgtk-wayland=true \
        -Dcpu=baseline \
        -Doptimize=${optimize} \
        -Dpie=true \
        -Dsimd=false \
        -fsys=spirv-cross \
        -fsys=glslang

      runHook postBuild
    '';

    postBuild = ''
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
  }
