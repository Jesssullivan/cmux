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
in
  stdenv.mkDerivation {
    pname = "libghostty";
    version = "1.3.0-dev";
    src = ghosttySrc;

    nativeBuildInputs = [
      git ncurses pkg-config zig_0_15 pkgs.pandoc
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

      # Zig 0.15 + Nix sandbox: C++ deps need glibc but Zig defaults to musl.
      # Use --libc config + -Dtarget=native-native-gnu for correct headers.
      # Symlink the dynamic linker so build-time binaries (framegen) can run.
      cat > "$TMPDIR/zig-libc.conf" <<LIBC
include_dir=${pkgs.glibc.dev}/include
sys_include_dir=${pkgs.glibc.dev}/include
crt_dir=${pkgs.glibc}/lib
msvc_lib_dir=
kernel32_lib_dir=
gcc_dir=
LIBC
      mkdir -p "$TMPDIR/lib64"
      ln -sf ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 "$TMPDIR/lib64/"

      # Tell the Nix sandbox to bind-mount our fake /lib64
      export LD_LIBRARY_PATH="${pkgs.glibc}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      export NIX_ENFORCE_PURITY=0

      zig build \
        --system ${deps} \
        -Dapp-runtime=none \
        -Drenderer=opengl \
        -Dgtk-wayland=true \
        -Dcpu=baseline \
        -Doptimize=${optimize} \
        -Dpie=true \
        -Dtarget=native-native-gnu \
        --libc "$TMPDIR/zig-libc.conf"

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
