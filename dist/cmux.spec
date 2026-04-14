Name:           cmux
Version:        0.75.0
Release:        1%{?dist}
Summary:        Terminal multiplexer with GTK4 split panes and workspaces
License:        GPL-3.0-or-later
URL:            https://github.com/Jesssullivan/cmux
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  zig >= 0.15.2
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  pkg-config
BuildRequires:  gtk4-devel >= 4.10
BuildRequires:  libadwaita-devel >= 1.3
BuildRequires:  libsecret-devel
BuildRequires:  libnotify-devel
BuildRequires:  freetype-devel
BuildRequires:  harfbuzz-devel
BuildRequires:  fontconfig-devel
BuildRequires:  libpng-devel
BuildRequires:  oniguruma-devel
BuildRequires:  mesa-libGL-devel

Requires:       gtk4 >= 4.10
Requires:       libadwaita >= 1.3
Requires:       webkitgtk6.0

%description
cmux is a GTK4 terminal multiplexer built on libghostty, providing
tabbed workspaces, split pane management, and a sidebar for workspace
navigation.

Features:
- Tabbed terminal interface using AdwTabView
- Binary tree split pane management
- Workspace model with sidebar navigation
- JSON configuration with hot-reload
- Unix socket JSON-RPC control interface
- Browser panel support on WebKitGTK-capable distros

%prep
%autosetup

%build
# Build libghostty
cd ghostty
zig build -Dapp-runtime=none -Drenderer=opengl -Doptimize=ReleaseFast
cd ..

# Build cmux-linux
cd cmux-linux
zig build -Doptimize=ReleaseFast
cd ..

%install
install -Dm755 cmux-linux/zig-out/bin/cmux %{buildroot}%{_bindir}/cmux
install -Dm755 ghostty/zig-out/lib/libghostty.so %{buildroot}%{_libdir}/cmux/libghostty.so
install -Dm644 dist/linux/com.jesssullivan.cmux.desktop %{buildroot}%{_datadir}/applications/com.jesssullivan.cmux.desktop
install -Dm644 dist/linux/com.jesssullivan.cmux.metainfo.xml %{buildroot}%{_datadir}/metainfo/com.jesssullivan.cmux.metainfo.xml
install -Dm644 dist/linux/icons/com.jesssullivan.cmux_16x16.png %{buildroot}%{_datadir}/icons/hicolor/16x16/apps/com.jesssullivan.cmux.png
install -Dm644 dist/linux/icons/com.jesssullivan.cmux_128x128.png %{buildroot}%{_datadir}/icons/hicolor/128x128/apps/com.jesssullivan.cmux.png
install -Dm644 dist/linux/icons/com.jesssullivan.cmux_256x256.png %{buildroot}%{_datadir}/icons/hicolor/256x256/apps/com.jesssullivan.cmux.png
install -Dm644 dist/linux/icons/com.jesssullivan.cmux_512x512.png %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/com.jesssullivan.cmux.png
install -Dm644 dist/linux/70-u2f.rules %{buildroot}%{_udevrulesdir}/70-u2f.rules

%post
/usr/bin/gtk-update-icon-cache -q %{_datadir}/icons/hicolor 2>/dev/null || :
/usr/bin/udevadm control --reload-rules 2>/dev/null || :
/usr/bin/udevadm trigger --subsystem-match=hidraw 2>/dev/null || :

%postun
/usr/bin/gtk-update-icon-cache -q %{_datadir}/icons/hicolor 2>/dev/null || :
/usr/bin/udevadm control --reload-rules 2>/dev/null || :

%files
%license LICENSE
%doc README.md
%{_bindir}/cmux
%{_libdir}/cmux/libghostty.so
%{_datadir}/applications/com.jesssullivan.cmux.desktop
%{_datadir}/metainfo/com.jesssullivan.cmux.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/com.jesssullivan.cmux.png
%{_udevrulesdir}/70-u2f.rules

%changelog
* Sun Apr 06 2026 Jess Sullivan <jess@jesssullivan.dev> - 0.75.0-1
- Refresh Linux package metadata for current release series
- Expand distro package testing coverage and release packaging
