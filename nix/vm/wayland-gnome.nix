# GNOME Wayland session (primary target)
{...}: {
  imports = [
    ./common-gnome.nix
  ];

  services.displayManager = {
    defaultSession = "gnome";
  };
}
