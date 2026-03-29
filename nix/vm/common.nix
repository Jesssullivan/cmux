# Base VM configuration shared by all desktop variants.
# Provides: bootloader, user account, SPICE agent, basic packages.
{pkgs, ...}: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  documentation.nixos.enable = false;

  virtualisation.vmVariant = {
    virtualisation.memorySize = 4096;
    virtualisation.cores = 4;
  };

  nix = {
    settings = {
      trusted-users = [
        "root"
        "cmux"
      ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  users.mutableUsers = false;

  users.groups.cmux = {};

  users.users.cmux = {
    isNormalUser = true;
    description = "cmux";
    group = "cmux";
    extraGroups = ["wheel"];
    hashedPassword = "";
  };

  environment.systemPackages = with pkgs; [
    ghostty
    kitty
    fish
    helix
    neovim
    xterm
    zsh
    # GTK4 development tools
    gtk4
    libadwaita
    webkitgtk_6_0
  ];

  security.polkit = {
    enable = true;
  };

  services.dbus = {
    enable = true;
  };

  services.displayManager = {
    autoLogin = {
      enable = true;
      user = "cmux";
    };
  };

  services.libinput = {
    enable = true;
  };

  services.qemuGuest = {
    enable = true;
  };

  services.spice-vdagentd = {
    enable = true;
  };

  services.xserver = {
    enable = true;
  };
}
