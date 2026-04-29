{
  # Checked-in default release manifest for distro package-install tests.
  # Workflow/manual validation can generate release-artifacts.override.nix to
  # point at a different GitHub release tag without editing this file.
  releaseTag = "lab-v0.75.0";
  assets = {
    deb = {
      name = "cmux_0.75.0_amd64.deb";
      hash = "sha256-BCGGL/CSv2IbcxVVssYq8GIRVxwJss5/OcVy3rfcw4M=";
    };
    rpm = {
      name = "cmux-0.75.0-1.fc42.x86_64.rpm";
      hash = "sha256-fApOZUcz0zQCur0Oo8XDziUg0pYfT4DRsKQNqMTQurw=";
    };
    rpmFedora = {
      name = "cmux-0.75.0-1.fc42.x86_64.rpm";
      hash = "sha256-fApOZUcz0zQCur0Oo8XDziUg0pYfT4DRsKQNqMTQurw=";
    };
    # `debDebian` is intentionally absent from this checked-in manifest until a
    # published Debian 12 baseline/no-WebKit DEB exists.
    # `rpmRocky` is intentionally absent from the checked-in manifest until a
    # published Rocky 10 terminal-first RPM exists.
  };
}
