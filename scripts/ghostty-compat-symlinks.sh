#!/usr/bin/env bash
# ghostty-compat-symlinks.sh
#
# Compat shim: ghostty upstream commit 4fd16ef9b
# ("build: install ghostty-internal dll/static with new names")
# renamed the internal-glue library outputs:
#
#   libghostty.so  ->  ghostty-internal.so
#   libghostty.a   ->  ghostty-internal.a
#   ghostty.dll    ->  ghostty-internal.dll
#
# The Linux outputs lost the conventional `lib` prefix, which means
# Zig's `linkSystemLibrary("ghostty")` no longer finds them and every
# packaging step that copied `libghostty.so` into `/usr/lib/cmux/` breaks.
#
# This script re-creates the historical filenames as symlinks so that
# cmux-linux/build.zig and the .deb/.rpm/Flatpak/Nix packagers continue
# to work with no further changes. Idempotent.
#
# Usage:
#   bash scripts/ghostty-compat-symlinks.sh                        # default: ghostty/zig-out/lib
#   bash scripts/ghostty-compat-symlinks.sh path/to/zig-out/lib    # explicit dir
#
# Remove this script (and its callers) once the upstream rename is
# either reverted or fully absorbed by renaming everything downstream.

set -eu

LIB_DIR="${1:-ghostty/zig-out/lib}"

if [ ! -d "$LIB_DIR" ]; then
  echo "ghostty-compat-symlinks: directory not found: $LIB_DIR" >&2
  exit 1
fi

made_any=0
for ext in so a; do
  src="ghostty-internal.$ext"
  dst="libghostty.$ext"
  if [ -f "$LIB_DIR/$src" ] && [ ! -e "$LIB_DIR/$dst" ]; then
    ln -sf "$src" "$LIB_DIR/$dst"
    echo "ghostty-compat-symlinks: $LIB_DIR/$dst -> $src"
    made_any=1
  fi
done

if [ "$made_any" -eq 0 ]; then
  # Nothing to do — either upstream still uses the old names, or the
  # symlinks already exist from a prior run. Both are fine.
  echo "ghostty-compat-symlinks: nothing to do in $LIB_DIR"
fi
