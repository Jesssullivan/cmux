Name:           cmux
Version:        0.75.0
Release:        1%{?dist}
Summary:        Terminal multiplexer with GTK4 split panes and workspaces
License:        GPL-3.0-or-later
URL:            https://github.com/Jesssullivan/cmux

# COPR source builds need a source archive that already contains submodules.
# GitHub auto-generated tag archives are not enough for this repo.
Source0:        %{name}-%{version}.tar.gz

# Fedora COPR should use the broad-feature build by default. Rocky/RHEL-class
# builds should pass `--without webkit` and stay terminal-first.
%bcond_without webkit

BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  git
BuildRequires:  glslang
BuildRequires:  pkg-config
BuildRequires:  systemd-rpm-macros
BuildRequires:  zig >= 0.15.2
BuildRequires:  fontconfig-devel
BuildRequires:  freetype-devel
BuildRequires:  gtk4-devel >= 4.10
BuildRequires:  harfbuzz-devel
BuildRequires:  libadwaita-devel >= 1.3
BuildRequires:  libnotify-devel
BuildRequires:  libpng-devel
BuildRequires:  libsecret-devel
BuildRequires:  mesa-libGL-devel
BuildRequires:  oniguruma-devel
BuildRequires:  wayland-devel
BuildRequires:  wayland-protocols-devel
%if %{with webkit}
BuildRequires:  webkitgtk6.0-devel
%endif

Requires:       gtk4 >= 4.10
Requires:       libadwaita >= 1.3
%if %{with webkit}
Requires:       webkitgtk6.0
%endif

%description
cmux is a GTK4 terminal multiplexer built on libghostty, providing tabbed
workspaces, split pane management, and a Unix socket JSON-RPC control surface.

%prep
%autosetup -n %{name}-%{version}
git -C ghostty tag -l 'xcframework-*' | xargs -r git -C ghostty tag -d || true

%build
pushd vendor/ctap2
zig build -Doptimize=ReleaseFast
popd
pushd vendor/zig-crypto
zig build -Doptimize=ReleaseFast
popd
pushd vendor/zig-keychain
zig build -Doptimize=ReleaseFast
popd
pushd vendor/zig-notify
zig build -Doptimize=ReleaseFast
popd

pushd ghostty
zig build -Dapp-runtime=none -Drenderer=opengl -Doptimize=ReleaseFast
popd
bash scripts/ghostty-compat-symlinks.sh

pushd cmux-linux
%if %{with webkit}
zig build -Doptimize=ReleaseFast
%else
zig build -Doptimize=ReleaseFast -Dno-webkit=true
%endif
popd

%install
install -Dm755 cmux-linux/zig-out/bin/cmux %{buildroot}%{_bindir}/cmux
install -Dm755 ghostty/zig-out/lib/libghostty.so %{buildroot}%{_libdir}/cmux/libghostty.so
install -Dm644 dist/linux/com.jesssullivan.cmux.desktop %{buildroot}%{_datadir}/applications/com.jesssullivan.cmux.desktop
install -Dm644 dist/linux/com.jesssullivan.cmux.metainfo.xml %{buildroot}%{_datadir}/metainfo/com.jesssullivan.cmux.metainfo.xml
for size in 16 128 256 512; do
  install -Dm644 "dist/linux/icons/com.jesssullivan.cmux_${size}x${size}.png" \
    "%{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps/com.jesssullivan.cmux.png"
done
install -Dm644 dist/linux/70-u2f.rules %{buildroot}%{_udevrulesdir}/70-u2f.rules
install -Dm644 LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE
install -Dm644 README.md %{buildroot}%{_docdir}/%{name}/README.md

%post
/usr/bin/gtk-update-icon-cache -q %{_datadir}/icons/hicolor 2>/dev/null || :
/usr/bin/udevadm control --reload-rules 2>/dev/null || :
/usr/bin/udevadm trigger --subsystem-match=hidraw 2>/dev/null || :

%postun
/usr/bin/gtk-update-icon-cache -q %{_datadir}/icons/hicolor 2>/dev/null || :
/usr/bin/udevadm control --reload-rules 2>/dev/null || :

%files
%license %{_licensedir}/%{name}/LICENSE
%doc %{_docdir}/%{name}/README.md
%{_bindir}/cmux
%{_libdir}/cmux/libghostty.so
%{_datadir}/applications/com.jesssullivan.cmux.desktop
%{_datadir}/metainfo/com.jesssullivan.cmux.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/com.jesssullivan.cmux.png
%{_udevrulesdir}/70-u2f.rules

%changelog
* Sat Apr 25 2026 Jess Sullivan <jess@jesssullivan.dev> - 0.75.0-1
- Add COPR source-build scaffold for human review
