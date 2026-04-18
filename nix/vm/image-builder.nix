# QCOW2 disk image builder — produces downloadable demo images.
#
# Reuses the same desktop modules as interactive VMs (wayland-gnome.nix,
# wayland-sway.nix, wayland-hyprland.nix) but outputs a persistent QCOW2
# disk image instead of an ephemeral QEMU runner.
#
# Usage from flake.nix:
#   qcow2-gnome = import ./nix/vm/image-builder.nix {
#     inherit nixpkgs nixos-generators;
#     module = ./nix/vm/wayland-gnome.nix;
#     overlay = self.overlays.default;
#   };
#
# Build:
#   nix build .#qcow2-gnome   (x86_64-linux only)
{
  nixpkgs,
  nixos-generators,
  module,
  overlay ? (_: _: {}),
}: let
  # Pre-apply the overlay so cmux-linux is available in pkgs, then
  # pass via specialArgs to avoid nixpkgs.overlays module recursion.
  pkgs = import nixpkgs {
    system = "x86_64-linux";
    overlays = [overlay];
  };
in
  nixos-generators.nixosGenerate {
    system = "x86_64-linux";
    format = "qcow";
    specialArgs = {
      cmuxPkg = pkgs.cmux-linux or null;
    };
    modules = [
      # image-extras.nix MUST come before common.nix (imported via module)
      # so it can override boot/virtualisation settings with lib.mkForce.
      ./image-extras.nix
      module
    ];
  }
