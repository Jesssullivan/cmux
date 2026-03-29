# Hyprland (wlroots) Wayland VM configuration.
# Primary tiling compositor target alongside Sway.
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./common.nix
  ];

  programs.hyprland = {
    enable = true;
  };

  # Software rendering for VM (no GPU required)
  environment.variables = {
    WLR_RENDERER = "pixman";
    WLR_NO_HARDWARE_CURSORS = "1";
    # Hyprland-specific: allow running in VM without GPU
    WLR_BACKENDS = "drm";
    LIBVA_DRIVER_NAME = "dummy";
  };

  # Disable GDM — Hyprland starts from greetd
  services.displayManager.gdm.enable = lib.mkForce false;
  services.xserver.enable = lib.mkForce false;

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.hyprland}/bin/Hyprland";
        user = "cmux";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    foot
    waybar
    fuzzel
    mako
    grim
    slurp
    wl-clipboard
    hyprpaper
  ];
}
