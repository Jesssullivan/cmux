{
  pkgs,
  lib,
  stdenv,
}:
lib.makeLibraryPath (import ./build-inputs.nix {
  inherit pkgs lib stdenv;
})
