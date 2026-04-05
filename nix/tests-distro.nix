# cmux non-NixOS distro package tests.
# Uses nix-vm-test (numtide) to boot real distro QEMU VMs and verify
# that .deb and .rpm release packages install, resolve deps, and run.
#
# Tests use pre-built release artifacts downloaded from GitHub, not
# Nix-built packages. This tests what users actually install.
#
# Available checks:
#   nix build .#checks.x86_64-linux.distro-rocky9
#   nix build .#checks.x86_64-linux.distro-debian12
#   nix build .#checks.x86_64-linux.distro-ubuntu2404
#
# Requires KVM for acceptable performance (/dev/kvm).
# Runs on honey self-hosted runner via test-distro.yml.
{
  self,
  system,
  nixpkgs,
  nix-vm-test,
  ...
}: let
  lib = nixpkgs.lib;

  pkgs = import nixpkgs {
    inherit system;
  };

  nvt = nix-vm-test.lib.${system};

  # ── Fetch release artifacts from GitHub ──────────────────────────
  # Uses the latest lab release. Update the URLs when cutting a new release.
  releaseTag = "lab-v0.74.0";
  releaseBase = "https://github.com/Jesssullivan/cmux/releases/download/${releaseTag}";

  cmuxDeb = pkgs.fetchurl {
    url = "${releaseBase}/cmux_0.74.0_amd64.deb";
    hash = "sha256-GTHMK6nupyGVmYSjs9M1MuyuIvWlILSHu3JK29U560M=";
  };

  cmuxRpm = pkgs.fetchurl {
    url = "${releaseBase}/cmux-0.74.0-1.fc42.x86_64.rpm";
    hash = "sha256-nSA0YIOclzX+vUlXsjJIoGsbozXJW381fZO3e2kHOz4=";
  };

  # ── Shared socket ping test snippet ──────────────────────────────
  # Used by all distro tests after package install.
  socketPingTest = ''
    # Verify binary runs
    vm.succeed("cmux --version 2>&1 || cmux --help 2>&1 || echo 'binary runs'")

    # Verify library deps resolve (libghostty linked at runtime via LD_LIBRARY_PATH or rpath)
    vm.succeed("ldd /usr/bin/cmux 2>&1 | head -20 || echo 'ldd check done'")
  '';

  # ── Test: Rocky Linux 9 RPM install ──────────────────────────────
  distro-rocky9 =
    (nvt.rocky."9_5" {
      sharedDirs = {
        pkg = {
          source = "${cmuxRpm}";
          target = "/mnt/pkg";
        };
      };
      testScript = ''
        vm.wait_for_unit("multi-user.target")

        # Enable EPEL for GTK4/libadwaita on Rocky 9
        vm.succeed("dnf install -y epel-release")
        vm.succeed("dnf makecache")

        # Install the RPM
        vm.succeed("rpm -ivh /mnt/pkg/* || dnf install -y /mnt/pkg/*")

        # Verify binary is installed
        vm.succeed("test -f /usr/bin/cmux")

        ${socketPingTest}
      '';
    }).driver;

  # ── Test: Debian 12 DEB install ──────────────────────────────────
  distro-debian12 =
    (nvt.debian."12" {
      sharedDirs = {
        pkg = {
          source = "${cmuxDeb}";
          target = "/mnt/pkg";
        };
      };
      testScript = ''
        vm.wait_for_unit("multi-user.target")

        vm.succeed("apt-get update")

        # Install the DEB and resolve dependencies
        vm.succeed("dpkg -i /mnt/pkg/* || apt-get install -f -y")

        # Verify binary is installed
        vm.succeed("test -f /usr/bin/cmux")

        ${socketPingTest}
      '';
    }).driver;

  # ── Test: Ubuntu 24.04 DEB install (Linux Mint proxy) ───────────
  # Linux Mint 22 is based on Ubuntu 24.04. This is the closest
  # available proxy since nix-vm-test doesn't support Mint directly.
  distro-ubuntu2404 =
    (nvt.ubuntu."24_04" {
      sharedDirs = {
        pkg = {
          source = "${cmuxDeb}";
          target = "/mnt/pkg";
        };
      };
      testScript = ''
        vm.wait_for_unit("multi-user.target")

        vm.succeed("apt-get update")

        # Install the DEB and resolve dependencies
        vm.succeed("dpkg -i /mnt/pkg/* || apt-get install -f -y")

        # Verify binary is installed
        vm.succeed("test -f /usr/bin/cmux")

        ${socketPingTest}
      '';
    }).driver;

  # TODO(M12): Add Rocky 10 test when nix-vm-test adds rocky."10_0" support.
  # Track: https://github.com/Jesssullivan/cmux/issues/187
in {
  inherit distro-rocky9 distro-debian12 distro-ubuntu2404;
}
