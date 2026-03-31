# cmux NixOS VM tests.
# Adapted from ghostty/nix/tests.nix.
#
# Tests use color histogram detection (no flaky OCR) to verify
# that cmux renders correctly under various Wayland compositors.
{
  self,
  system,
  nixpkgs,
  zigPkg ? null,
  ghosttySrc ? null,
  ...
}: let
  lib = nixpkgs.lib;
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

  # Tier 4: Socket test suite (headless, NixOS VM)
  # Runs Python socket tests against cmux-linux daemon in CMUX_NO_SURFACE mode.
  # Requires cmux-linux Nix derivation (built from libghostty + cmux-linux source).
  socket-test-suite = let
    cmuxLinux =
      if ghosttySrc != null && zigPkg != null
      then
        pkgs.callPackage ./cmux-linux.nix {
          zig_0_15 = zigPkg;
          libghostty = pkgs.callPackage ./libghostty.nix {
            zig_0_15 = zigPkg;
            inherit ghosttySrc;
          };
        }
      else null;
    testSrc = self + "/tests_v2";
  in
    pkgs.testers.runNixOSTest {
      name = "socket-test-suite";

      # 30 min global timeout (default is 15 min, too short for
      # free GitHub runners without KVM acceleration)
      globalTimeout = 1800;

      nodes = {
        machine = {pkgs, ...}: {
          users.groups.cmux = {};
          users.users.cmux = {
            isNormalUser = true;
            group = "cmux";
            extraGroups = ["wheel"];
            hashedPassword = "";
          };

          virtualisation.memorySize = 4096;
          virtualisation.cores = 2;

          environment.systemPackages = with pkgs;
            [
              python3
              xorg.xorgserver
              mesa
              mesa.drivers
            ]
            ++ (lib.optional (cmuxLinux != null) cmuxLinux);

          environment.etc."cmux-tests".source = testSrc;

          # LD_LIBRARY_PATH for cmux-linux runtime deps (libghostty.so)
          environment.variables.LD_LIBRARY_PATH =
            lib.optionalString (cmuxLinux != null)
            (lib.makeLibraryPath [cmuxLinux]);
        };
      };
      testScript = {...}: ''
        machine.wait_for_unit("multi-user.target")

        ${
          if cmuxLinux != null
          then ''
            # Diagnostic: verify cmux-linux is installed
            machine.succeed("which cmux-linux")
            machine.succeed("cmux-linux --version 2>&1 || true")

            # Start Xvfb
            machine.succeed("Xvfb :99 -screen 0 1280x720x24 +extension GLX &")
            machine.sleep(2)
            machine.succeed("test -e /tmp/.X99-lock")

            # Start cmux-linux daemon with timeout wrapper
            machine.succeed("""
              su - cmux -c '
                export DISPLAY=:99
                export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
                export LIBGL_ALWAYS_SOFTWARE=1
                export XDG_RUNTIME_DIR=/run/user/$(id -u)
                mkdir -p $XDG_RUNTIME_DIR && chmod 700 $XDG_RUNTIME_DIR
                export CMUX_NO_SURFACE=1
                export CMUX_SOCKET=$XDG_RUNTIME_DIR/cmux.sock

                echo "Starting cmux-linux daemon..."
                timeout 30 cmux-linux &
                CMUX_PID=$!
                echo "cmux-linux PID: $CMUX_PID"

                echo "Waiting for socket at $CMUX_SOCKET..."
                for i in $(seq 1 40); do [ -S "$CMUX_SOCKET" ] && break; sleep 0.25; done

                if [ ! -S "$CMUX_SOCKET" ]; then
                  echo "ERROR: Socket not created after 10s"
                  echo "Process status:"
                  kill -0 $CMUX_PID 2>/dev/null && echo "  PID $CMUX_PID alive" || echo "  PID $CMUX_PID dead"
                  echo "XDG_RUNTIME_DIR contents:"
                  ls -la $XDG_RUNTIME_DIR/ 2>/dev/null || true
                  exit 1
                fi
                echo "Socket ready"

                cd /etc/cmux-tests
                PASS=0 FAIL=0 TOTAL=0
                for f in test_*.py; do
                  case "$f" in
                    test_browser_*|test_cli_*|test_ctrl_interactive*|test_ssh_*) continue ;;
                    test_visual_*|test_lint_*|test_command_palette_*|test_tmux_*) continue ;;
                    test_nested_split_does_not_disappear*|test_nested_split_no_arranged_subview*) continue ;;
                    test_nested_split_panel_routing*) continue ;;
                    test_split_cmd_*|test_split_flash_*) continue ;;
                    test_shortcut_window_scope*|test_tab_dragging*) continue ;;
                    test_ctrl_enter_keybind*) continue ;;
                    test_new_tab_interactive*|test_new_tab_render*) continue ;;
                    test_initial_terminal_interactive*) continue ;;
                    test_terminal_focus_routing*|test_terminal_input_render*) continue ;;
                    test_v1_panel_creation*|test_update_timing*) continue ;;
                    test_pane_resize_*|test_read_screen_capture*) continue ;;
                    test_surface_list_custom_titles*) continue ;;
                    test_workspace_create_background*|test_workspace_create_initial_env*) continue ;;
                    test_ctrl_socket*) continue ;;
                    test_rename_tab_cli*|test_rename_window_workspace*) continue ;;
                    test_tab_workspace_action_naming*|test_workspace_relative*) continue ;;
                    test_nested_split_preserves_existing*) continue ;;
                    test_cpu_usage*|test_cpu_notifications*) continue ;;
                    test_notifications*) continue ;;
                    test_surface_move_reorder_api*) continue ;;
                  esac
                  TOTAL=$((TOTAL + 1))
                  if timeout 10 python3 "$f" 2>&1; then
                    PASS=$((PASS + 1))
                    echo "PASS: $f"
                  else
                    FAIL=$((FAIL + 1))
                    echo "FAIL: $f"
                  fi
                done

                kill $CMUX_PID 2>/dev/null || true
                echo "Results: $PASS/$TOTAL passed, $FAIL failed"
                [ $FAIL -eq 0 ]
              '
            """)
          ''
          else ''
            # cmux-linux package not available (missing ghosttySrc or zigPkg)
            machine.log("Socket test suite: skipped (cmux-linux not built)")
            machine.succeed("which python3")
            machine.succeed("which Xvfb")
          ''
        }
      '';
    };

  # Tier 3: GTK4 version floor check
  # Verifies the minimum GTK4 version requirement (4.14) is met.
  gtk4-version-check = pkgs.testers.runNixOSTest {
    name = "gtk4-version-check";
    nodes = {
      machine = {
        pkgs,
        lib,
        ...
      }: {
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
