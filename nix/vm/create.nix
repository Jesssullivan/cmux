# VM factory — adapted from ghostty/nix/vm/create.nix
# Builds a NixOS VM for testing cmux under various desktop environments.
# On macOS (aarch64-darwin), the system is translated to aarch64-linux.
{
  system,
  nixpkgs,
  overlay,
  module,
  common ? ./common.nix,
  uid ? 1000,
  gid ? 1000,
}: let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [
      overlay
    ];
  };
in
  nixpkgs.lib.nixosSystem {
    system = builtins.replaceStrings ["darwin"] ["linux"] system;
    modules = [
      {
        virtualisation.vmVariant = {
          virtualisation.host.pkgs = pkgs;
        };

        nixpkgs.overlays = [
          overlay
        ];

        users.groups.cmux = {
          gid = gid;
        };

        users.users.cmux = {
          uid = uid;
        };

        system.stateVersion = nixpkgs.lib.trivial.release;
      }
      common
      module
    ];
  }
