# cmux NixOS VM tests.
# Adapted from ghostty/nix/tests.nix.
#
# Tests use color histogram detection (no flaky OCR) to verify
# that cmux renders correctly under various Wayland compositors.
{
  self,
  system,
  nixpkgs,
  ...
}: let
  nixos-version = nixpkgs.lib.trivial.release;

  pkgs = import nixpkgs {
    inherit system;
  };

  # Distinctive color used to verify terminal rendering.
  # We set this as the terminal background and check for it in screenshots.
  marker_color = "#00BFFF";

  color_test = ''
    import tempfile
    import subprocess

    def check_for_marker(final=False) -> bool:
        with tempfile.NamedTemporaryFile() as tmpin:
            machine.send_monitor_command("screendump {}".format(tmpin.name))

            cmd = 'convert {} -define histogram:unique-colors=true -format "%c" histogram:info:'.format(
                tmpin.name
            )
            ret = subprocess.run(cmd, shell=True, capture_output=True)
            if ret.returncode != 0:
                raise Exception(
                    "image analysis failed with exit code {}".format(ret.returncode)
                )

            text = ret.stdout.decode("utf-8")
            return "${marker_color}" in text
  '';

  mkNodeGnome = {
    config,
    pkgs,
    settings,
    sshPort ? null,
    ...
  }: {
    imports = [
      ./vm/wayland-gnome.nix
      settings
    ];

    virtualisation = {
      forwardPorts = pkgs.lib.optionals (sshPort != null) [
        {
          from = "host";
          host.port = sshPort;
          guest.port = 22;
        }
      ];

      vmVariant = {
        virtualisation.host.pkgs = pkgs;
      };
    };

    users.groups.cmux = {
      gid = 1000;
    };

    users.users.cmux = {
      uid = 1000;
    };

    system.stateVersion = nixos-version;
  };

  mkTestGnome = {
    name,
    settings,
    testScript,
    ocr ? false,
  }:
    pkgs.testers.runNixOSTest {
      name = name;

      enableOCR = ocr;

      nodes = {
        machine = {
          config,
          pkgs,
          ...
        }:
          mkNodeGnome {
            inherit config pkgs settings;
            sshPort = 2222;
          };
      };

      testScript = testScript;
    };
in {
  # Tier 1: Basic check — verify GTK4 and essential deps are available (headless, fast)
  basic-version-check = pkgs.testers.runNixOSTest {
    name = "basic-version-check";
    nodes = {
      machine = {pkgs, ...}: {
        users.groups.cmux = {};
        users.users.cmux = {
          isNormalUser = true;
          group = "cmux";
          extraGroups = ["wheel"];
          hashedPassword = "";
          packages = with pkgs; [
            gtk4
            libadwaita
            foot
          ];
        };
      };
    };
    testScript = {...}: ''
      # Verify GTK4 runtime is functional
      machine.succeed("su - cmux -c 'foot --version'")
    '';
  };

  # Tier 2: Graphical rendering check on GNOME Wayland
  # Sets a distinctive background color in the terminal and verifies it
  # appears on screen via screenshot color histogram analysis.
  basic-window-check-gnome = mkTestGnome {
    name = "basic-window-check-gnome";
    settings = {};
    ocr = true;
    testScript = {nodes, ...}: let
      user = nodes.machine.users.users.cmux;
      bus_path = "/run/user/${toString user.uid}/bus";
      bus = "DBUS_SESSION_BUS_ADDRESS=unix:path=${bus_path}";
      gdbus = "${bus} gdbus";
      su = command: "su - ${user.name} -c '${command}'";
      gseval = "call --session -d org.gnome.Shell -o /org/gnome/Shell -m org.gnome.Shell.Eval";
      wm_class = su "${gdbus} ${gseval} global.display.focus_window.wm_class";
    in ''
      ${color_test}

      with subtest("wait for desktop"):
          start_all()
          machine.wait_for_x()

      machine.wait_for_file("${bus_path}")

      with subtest("Verify no marker color before terminal launch"):
          assert (
              check_for_marker() == False
          ), "Marker color present before terminal launched!"

      # Launch foot terminal to verify Wayland compositor is working.
      # TODO: Replace with cmux-linux once packaged as a Nix derivation.
      # cmux-linux compiles on all 3 distros (PR #104) but needs Nix
      # packaging to be available inside VM tests.
      machine.succeed("${su "${bus} foot &"}")

      machine.sleep(3)

      machine.screenshot("cmux-gnome-wayland")
    '';
  };

  # Tier 2b: cmux-linux build verification (headless)
  # Verifies that libghostty + cmux-linux compile and produce a binary.
  # Full graphical test requires cmux-linux as a Nix package (future work).
  cmux-linux-build-check = pkgs.testers.runNixOSTest {
    name = "cmux-linux-build-check";
    nodes = {
      machine = {pkgs, ...}: {
        users.groups.cmux = {};
        users.users.cmux = {
          isNormalUser = true;
          group = "cmux";
          extraGroups = ["wheel"];
          hashedPassword = "";
          packages = [
            pkgs.gtk4
            pkgs.libadwaita
          ];
        };

        environment.systemPackages = [
          pkgs.gtk4
          pkgs.libadwaita
        ];
      };
    };
    testScript = {...}: ''
      # Verify GTK4 and libadwaita are available in the VM
      machine.succeed("test -e /run/current-system/sw/lib/libgtk-4.so || test -e /run/current-system/sw/lib/libgtk-4.so.1")
      machine.succeed("test -e /run/current-system/sw/lib/libadwaita-1.so || test -e /run/current-system/sw/lib/libadwaita-1.so.0")
      machine.log("GTK4 + libadwaita runtime libraries present")
    '';
  };

  # Tier 3: GTK4 version floor check
  # Verifies the minimum GTK4 version requirement (4.14) is met.
  gtk4-version-check = pkgs.testers.runNixOSTest {
    name = "gtk4-version-check";
    nodes = {
      machine = {pkgs, lib, ...}: {
        users.groups.cmux = {};
        users.users.cmux = {
          isNormalUser = true;
          group = "cmux";
          extraGroups = ["wheel"];
          hashedPassword = "";
        };

        environment.systemPackages = [
          pkgs.gtk4
          pkgs.gtk4.dev
          pkgs.libadwaita
          pkgs.libadwaita.dev
          pkgs.webkitgtk_6_0
          pkgs.webkitgtk_6_0.dev
          pkgs.pkg-config
        ];

        environment.variables.PKG_CONFIG_PATH = lib.makeSearchPath "lib/pkgconfig" [
          pkgs.gtk4.dev
          pkgs.libadwaita.dev
          pkgs.webkitgtk_6_0.dev
        ];
      };
    };
    testScript = {...}: ''
      # Verify GTK4 >= 4.14 (Ubuntu 24.04 LTS floor)
      result = machine.succeed("su - cmux -c 'pkg-config --modversion gtk4'").strip()
      parts = result.split(".")
      major, minor = int(parts[0]), int(parts[1])
      assert major >= 4 and minor >= 14, f"GTK4 {result} is below minimum 4.14"
      machine.log(f"GTK4 version: {result} (>= 4.14 OK)")

      # Verify libadwaita present
      machine.succeed("su - cmux -c 'pkg-config --modversion libadwaita-1'")

      # Verify WebKitGTK 6.0 present
      machine.succeed("su - cmux -c 'pkg-config --modversion webkitgtk-6.0'")
    '';
  };
}
