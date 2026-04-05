{
  description = "cmux — terminal multiplexer with browser panel, FIDO2/WebAuthn, and Linux GTK4 port";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";
    flake-utils.url = "github:numtide/flake-utils";

    # Zig toolchain overlay (provides zig 0.15.x)
    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    # Non-NixOS distro VM testing (Fedora, Ubuntu, Rocky)
    nix-vm-test = {
      url = "github:numtide/nix-vm-test";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Ghostty source for libghostty Nix derivation
    ghostty-src = {
      url = "github:Jesssullivan/ghostty";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig,
    nix-vm-test,
    ghostty-src,
    ...
  }: let
    inherit (nixpkgs) lib legacyPackages;

    # All platforms where dev shells work
    allPlatforms = lib.attrNames zig.packages;

    # Platforms that can build Linux packages and VMs
    buildablePlatforms = lib.filter (p: !(lib.systems.elaborate p).isDarwin) allPlatforms;

    # Platforms that can define VMs (includes macOS via linux-builder translation)
    vmPlatforms = allPlatforms;

    forAllPlatforms = f: lib.genAttrs allPlatforms (s: f legacyPackages.${s});
    forBuildablePlatforms = f: lib.genAttrs buildablePlatforms (s: f legacyPackages.${s});
    forVMPlatforms = f: lib.genAttrs vmPlatforms (s: f legacyPackages.${s});

    version = "0.72.0-lab";
  in {
    # ── Dev Shells ───────────────────────────────────────────────────
    devShells = forAllPlatforms (pkgs: {
      default = pkgs.callPackage ./nix/devShell.nix {
        zig = zig.packages.${pkgs.stdenv.hostPlatform.system}."0.15.2";
      };
    });

    # ── Packages ─────────────────────────────────────────────────────
    packages = forAllPlatforms (pkgs:
      {
        # macOS: package a pre-built .app from xcodebuild CI artifacts
        cmux-darwin = pkgs.stdenv.mkDerivation {
          pname = "cmux-lab";
          inherit version;
          src = ./.;

          phases = ["installPhase"];

          installPhase = ''
            mkdir -p $out/Applications
            if [ -d "$src/build/Build/Products/Release/cmux.app" ]; then
              cp -R "$src/build/Build/Products/Release/cmux.app" "$out/Applications/cmux LAB.app"
            else
              echo "No pre-built .app found. Build with xcodebuild first."
              exit 1
            fi

            mkdir -p $out/bin
            if [ -f "$out/Applications/cmux LAB.app/Contents/Resources/bin/cmux" ]; then
              ln -s "$out/Applications/cmux LAB.app/Contents/Resources/bin/cmux" $out/bin/cmux-lab
            fi
          '';

          meta = with pkgs.lib; {
            description = "cmux LAB - terminal multiplexer with FIDO2/WebAuthn browser support";
            homepage = "https://github.com/Jesssullivan/cmux";
            license = licenses.mit;
            platforms = platforms.darwin;
            mainProgram = "cmux-lab";
          };
        };

        # Linux: build cmuxd remote daemon via Zig
        cmux-rpm = pkgs.stdenv.mkDerivation {
          pname = "cmux-lab";
          inherit version;
          src = ./.;

          nativeBuildInputs = with pkgs; [rpm];

          buildPhase = ''
            if command -v zig &>/dev/null && [ -d cmuxd ]; then
              cd cmuxd && zig build -Doptimize=ReleaseFast && cd ..
            fi
          '';

          installPhase = ''
            mkdir -p $out/bin $out/share/cmux-lab
            if [ -f cmuxd/zig-out/bin/cmuxd ]; then
              cp cmuxd/zig-out/bin/cmuxd $out/bin/cmuxd-lab
            fi
            cp -r scripts $out/share/cmux-lab/ 2>/dev/null || true
          '';

          meta = with pkgs.lib; {
            description = "cmux LAB remote daemon for Linux";
            homepage = "https://github.com/Jesssullivan/cmux";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };

        default =
          if pkgs.stdenv.isDarwin
          then self.packages.${pkgs.stdenv.hostPlatform.system}.cmux-darwin
          else self.packages.${pkgs.stdenv.hostPlatform.system}.cmux-rpm;
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        libghostty = pkgs.callPackage ./nix/libghostty.nix {
          zig_0_15 = zig.packages.${pkgs.stdenv.hostPlatform.system}."0.15.2";
          ghosttySrc = ghostty-src;
        };
        cmux-linux = pkgs.callPackage ./nix/cmux-linux.nix {
          zig_0_15 = zig.packages.${pkgs.stdenv.hostPlatform.system}."0.15.2";
          libghostty = self.packages.${pkgs.stdenv.hostPlatform.system}.libghostty;
        };
      });

    # ── Interactive VM Apps ──────────────────────────────────────────
    # Usage: nix run .#wayland-gnome
    #        nix run .#wayland-sway
    #        nix run .#wayland-hyprland
    apps = forVMPlatforms (pkgs: let
      runVM = module: let
        vm = import ./nix/vm/create.nix {
          inherit (pkgs.stdenv.hostPlatform) system;
          inherit module nixpkgs;
          # Empty overlay for interactive VMs — cmux packages are only
          # needed in test checks, not in manual desktop environments.
          overlay = _final: _prev: {};
        };
        program = pkgs.writeShellScript "run-cmux-vm" ''
          SHARED_DIR=$(pwd)
          export SHARED_DIR

          ${pkgs.lib.getExe vm.config.system.build.vm} "$@"
        '';
      in {
        type = "app";
        program = "${program}";
        meta.description = "start a cmux test VM from ${toString module}";
      };
    in {
      wayland-gnome = runVM ./nix/vm/wayland-gnome.nix;
      wayland-sway = runVM ./nix/vm/wayland-sway.nix;
      wayland-hyprland = runVM ./nix/vm/wayland-hyprland.nix;
    });

    # ── Automated Checks ─────────────────────────────────────────────
    # Usage: nix flake check
    #        nix build .#checks.x86_64-linux.basic-version-check
    #        nix build .#checks.x86_64-linux.distro-rocky9
    #        nix build .#checks.x86_64-linux.distro-debian12
    #        nix build .#checks.x86_64-linux.distro-ubuntu2404
    checks = forAllPlatforms (pkgs: let
      sys = pkgs.stdenv.hostPlatform.system;
      zigPkg = zig.packages.${sys}."0.15.2";
    in
      (import ./nix/tests.nix {
        inherit nixpkgs self;
        system = sys;
        inherit zigPkg;
        ghosttySrc = ghostty-src;
      })
      // (lib.optionalAttrs pkgs.stdenv.isLinux
        (import ./nix/tests-distro.nix {
          inherit nixpkgs self nix-vm-test;
          system = sys;
          inherit zigPkg;
          ghosttySrc = ghostty-src;
        })));

    # ── Overlays ─────────────────────────────────────────────────────
    overlays = {
      default = final: prev:
        lib.optionalAttrs final.stdenv.isLinux {
          libghostty = final.callPackage ./nix/libghostty.nix {
            zig_0_15 = zig.packages.${final.stdenv.hostPlatform.system}."0.15.2";
            ghosttySrc = ghostty-src;
          };
          cmux-linux = final.callPackage ./nix/cmux-linux.nix {
            zig_0_15 = zig.packages.${final.stdenv.hostPlatform.system}."0.15.2";
            inherit (final) libghostty;
          };
        };
    };

    # ── Formatter ────────────────────────────────────────────────────
    formatter = forAllPlatforms (pkgs: pkgs.alejandra);
  };

  nixConfig = {
    extra-substituters = ["https://ghostty.cachix.org"];
    extra-trusted-public-keys = ["ghostty.cachix.org-1:QB389yTa6gTyneehvqG58y0WnHjQOqgnA+wBnpWWxns="];
  };
}
