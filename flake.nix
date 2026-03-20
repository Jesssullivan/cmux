{
  description = "cmux LAB - fork with FIDO2/WebAuthn support for enterprise auth testing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        version = "0.62.1-lab";
      in
      {
        packages = {
          # Darwin .app bundle (macOS only)
          cmux-darwin = pkgs.stdenv.mkDerivation {
            pname = "cmux-lab";
            inherit version;
            src = ./.;

            # The macOS .app is built via xcodebuild externally;
            # this derivation packages a pre-built .app from CI artifacts.
            # For local dev, use ./scripts/reload.sh --tag lab
            phases = [ "installPhase" ];

            installPhase = ''
              mkdir -p $out/Applications
              if [ -d "$src/build/Build/Products/Release/cmux.app" ]; then
                cp -R "$src/build/Build/Products/Release/cmux.app" "$out/Applications/cmux LAB.app"
              else
                echo "No pre-built .app found. Build with xcodebuild first."
                exit 1
              fi

              # Install CLI wrapper
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

          # RPM package spec (Linux)
          cmux-rpm = pkgs.stdenv.mkDerivation {
            pname = "cmux-lab";
            inherit version;
            src = ./.;

            nativeBuildInputs = with pkgs; [ rpm ];

            buildPhase = ''
              # Build cmuxd for Linux
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

          default = if pkgs.stdenv.isDarwin
            then self.packages.${system}.cmux-darwin
            else self.packages.${system}.cmux-rpm;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig_0_14
            python3
            python3Packages.pillow
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            rpm
            dpkg
          ];

          shellHook = ''
            echo "cmux LAB dev shell"
            echo "  macOS: ./scripts/reload.sh --tag lab"
            echo "  Icons: nix-shell -p python3Packages.pillow --run 'python3 scripts/generate_fork_icon.py'"
          '';
        };
      }
    );
}
