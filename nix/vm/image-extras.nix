# Image-specific overrides for QCOW2 demo images.
#
# nixos-generators "qcow" format uses GRUB (not systemd-boot) and sets its
# own boot/filesystem config.  common.nix enables systemd-boot, which
# conflicts — so we disable it here with mkForce.
#
# cmux-linux is passed via specialArgs from image-builder.nix to avoid
# the infinite recursion that occurs with nixpkgs.overlays in modules.
{
  lib,
  pkgs,
  cmuxPkg ? null,
  ...
}: {
  # ── Boot: let nixos-generators own the bootloader ──────────────
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # ── Disk ───────────────────────────────────────────────────────
  # 10 GB raw, compresses to <2 GB with qemu-img convert -c.
  virtualisation.diskSize = 10 * 1024; # MiB

  # ── Identity ───────────────────────────────────────────────────
  networking.hostName = "cmux-demo";

  # ── Packages ───────────────────────────────────────────────────
  environment.systemPackages =
    lib.optionals (cmuxPkg != null) [cmuxPkg];

  # ── XDG autostart for cmux ─────────────────────────────────────
  # Drop a .desktop file so cmux launches on login in GNOME/Sway/Hyprland.
  environment.etc."xdg/autostart/cmux.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=cmux
    Exec=cmux
    X-GNOME-Autostart-enabled=true
  '';

  # ── SPICE: not needed in downloadable images ───────────────────
  # Users importing into GNOME Boxes / virt-manager get their own agent.
  services.spice-vdagentd.enable = lib.mkForce false;

  # ── Nix: keep the image self-contained ─────────────────────────
  nix.settings.experimental-features = ["nix-command" "flakes"];

  system.stateVersion = lib.trivial.release;
}
