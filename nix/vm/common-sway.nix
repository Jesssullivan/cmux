# Sway (wlroots) Wayland VM configuration.
# Representative of the tiling Wayland compositor class (Sway, River, etc.)
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./common.nix
  ];

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      foot
      wmenu
      mako
      grim
      slurp
      wl-clipboard
    ];
  };

  # Software rendering for VM (no GPU required)
  environment.variables = {
    WLR_RENDERER = "pixman";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  # Auto-login to tty1, sway launched from shell profile
  services.displayManager.autoLogin = {
    enable = true;
    user = "cmux";
  };

  # Disable GDM — sway starts from tty
  services.xserver.displayManager.gdm.enable = lib.mkForce false;
  services.xserver.enable = lib.mkForce false;

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.sway}/bin/sway";
        user = "cmux";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    waybar
    fuzzel
  ];
}
