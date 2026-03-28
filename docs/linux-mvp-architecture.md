# cmux Linux MVP — Architecture Decision Record

> Compiled from 7 parallel research agents, 2026-03-27.
> Scope: Wayland-only. No X11-based DEs.

## Target Environments

| DE/Compositor | Priority | Wayland Status |
|---------------|----------|----------------|
| **GNOME** (Ubuntu, Fedora, Rocky) | Primary | Wayland-only since GNOME 50 |
| **Hyprland / Sway** (tiling WM class) | Primary | Wayland-native from inception |
| **Budgie** (labwc) | Secondary | Wayland-only since 10.10 |

## Architecture Decisions

### 1. GTK4 Runtime Strategy: New apprt Variant (Approach C)

**Decision:** Create a new Ghostty apprt variant (`cmux_gtk`) that builds a Zig GTK4/libadwaita application reusing Ghostty's core infrastructure.

**Rationale:** Ghostty's GTK4 runtime is 20K+ LOC across 45 files with mature tab/split/window management. Three approaches were evaluated:
- (A) Fork Ghostty's GTK apprt — tight coupling, merge conflicts
- (B) Embed libghostty in a GTK4 host — no Linux platform tag in embedded mode
- **(C) New apprt variant** — cleanest separation, maximum reuse

**Reusable from Ghostty:**
- `datastruct/SplitTree` — runtime-agnostic binary tree for splits (shared code)
- `key.zig` — GDK keysym translation (535 LOC)
- `winproto.zig` — Wayland/X11 protocol abstraction
- `class.zig` — GObject class infrastructure
- Custom main loop pattern: `glib.MainContext.iteration()` + `core_app.tick()`

**Widget hierarchy:**
```
CmuxApplication (Adw.Application)
  └─ CmuxWindow (Adw.ApplicationWindow)
       ├─ Sidebar (workspace list)
       └─ CmuxWorkspace
            └─ AdwTabView
                 └─ CmuxTab (GtkBox)
                      └─ SplitTree (reused from Ghostty)
                           ├─ Terminal panels (GhosttySurface)
                           └─ Browser panels (WebKitGTK WebView)
```

**Minimum GTK4:** 4.14 (Ubuntu 24.04 LTS floor, Ghostty 1.3 requirement)

### 2. Browser Engine: WebKitGTK 6.0

**Decision:** Use WebKitGTK 6.0 (GTK4 API). Not CEF.

**Rationale:**
- JS bridge API is **identical** to WKWebView: `window.webkit.messageHandlers.<name>.postMessage()` + `register_script_message_handler_with_reply()`
- Native Wayland support (CEF's Wayland embedding is broken — issue #2804)
- Zero bundle size (system dependency or GNOME Flatpak runtime)
- WebAuthn JS injection works unchanged — same `WebKitUserScript` + `UserContentManager` pattern
- CEF would add 200MB+ bundled Chromium binaries

**Rocky Linux 10 caveat:** WebKitGTK removed from RHEL 10 repos. Rocky users must use Flatpak (GNOME runtime includes it) or terminal-only mode.

**API mapping:**

| macOS (WKWebView) | Linux (WebKitGTK 6.0) |
|--------------------|-----------------------|
| WKScriptMessageHandlerWithReply | `register_script_message_handler_with_reply()` |
| WKUserScript | `WebKitUserScript` |
| WKNavigationDelegate | `decide-policy` signal |
| WKWebsiteDataStore | `WebKitWebsiteDataManager` |
| evaluateJavaScript | `webkit_web_view_evaluate_javascript()` |
| WKFindInteraction | `WebKitFindController` |
| WKWebInspector | `WebKitWebInspector` |

### 3. D-Bus Integration: GDBus (GIO)

**Decision:** Use GDBus for all D-Bus communication. Not libnotify, not a pure Zig D-Bus library.

**Rationale:** Ghostty already uses GDBus extensively (IPC, global shortcuts, systemd cgroups, Flatpak host commands). Consistent with the GTK4 stack.

| Integration | Approach |
|------------|---------|
| **Notifications** | `GNotification` via `GApplication` (not libnotify) |
| **Secrets** | libsecret (already in zig-keychain) |
| **Session lock** | Subscribe to `org.freedesktop.login1` signals |
| **Global shortcuts** | XDG Desktop Portal (already in Ghostty) |

**zig-notify pivot:** The current zig-notify scaffold uses libnotify. For the GTK4 app, switch to `GNotification` which routes through GLib automatically. zig-notify's libnotify backend remains useful for non-GTK tools (CLI, daemon).

### 4. Wayland Protocol Support

**Decision:** Wayland-first, no X11-specific code paths.

| Protocol | Purpose | Used By |
|----------|---------|---------|
| xdg-shell | Window management | Core |
| xdg-decoration | CSD vs SSD negotiation | Hyprland/Sway prefer SSD |
| wp-fractional-scale-v1 | Per-monitor scaling | All compositors |
| zwp-text-input-v3 | IME / CJK input | All compositors |
| wlr-layer-shell-v1 | Quick terminal overlay | Hyprland/Sway |
| zwlr-data-control-v1 | Clipboard managers | Hyprland/Sway |

**CSD vs SSD:** GNOME requires CSD (libadwaita header bar). Hyprland/Sway/labwc support SSD. Ghostty's `window-decoration=auto` handles this correctly.

**CJK/Japanese input:** Don't set `GTK_IM_MODULE`. Rely on native `text-input-v3`. Document Kimpanel extension for GNOME candidate popup positioning.

### 5. Packaging: Flatpak Primary

**Priority order:**

| # | Format | Target | Notes |
|---|--------|--------|-------|
| 1 | **Flatpak** | All distros | WebKitGTK in GNOME runtime. `--device=all` for FIDO2. |
| 2 | **Nix Flake** | NixOS users | Already partially done. Add Cachix binary cache. |
| 3 | **DEB + PPA** | Ubuntu 24.04+ | Follow ghostty-ubuntu pattern. |
| 4 | **Fedora COPR** | Fedora | `zig-rpm-macros` exist. |
| 5 | **Arch AUR** | Arch | Community will likely contribute. |
| — | ~~AppImage~~ | — | Skip. WebKitGTK bundling is unreliable. |
| — | ~~Rocky RPM~~ | — | Skip. WebKitGTK removed from RHEL 10. Use Flatpak. |

**Flatpak manifest template:** Based on Ghostty's `flatpak/com.mitchellh.ghostty.yml`:
- Runtime: `org.gnome.Platform` 49+
- SDK: `org.gnome.Sdk`
- Zig installed as build dependency
- finish-args: `--device=all` (PTY + FIDO2), `--socket=wayland`, `--talk-name=org.freedesktop.secrets`

### 6. USB HID / FIDO2: Harden hidraw

**Decision:** Keep zig-ctap2's direct hidraw approach. Do not adopt libfido2.

**Rationale:** Chrome, Firefox, and libfido2 all use hidraw. Direct approach matches the ecosystem. Zero runtime dependencies.

**Hardening needed:**
1. Replace fixed `hidraw0-15` scan with `/sys/class/hidraw/` directory enumeration
2. Add `flock(LOCK_EX|LOCK_NB)` exclusive locking on device open
3. Add `HIDIOCGRDESC` ioctl as alternative to sysfs descriptor reading
4. Bundle or document `70-u2f.rules` for non-root access
5. Hot-plug: re-enumerate at ceremony start (no background monitor needed)

**Flatpak:** Requires `--device=all` for now. No FIDO2 portal exists yet (xdg-desktop-portal issue #989). The emerging `credentialsd` project may provide a portal-based path in future.

## Package Version Matrix (Wayland targets only)

| Package | Ubuntu 24.04 | Fedora 42 | Arch | Rocky 10 |
|---------|-------------|-----------|------|----------|
| GTK4 | 4.14 | 4.18 | 4.20 | 4.16 |
| WebKitGTK 6.0 | 2.50 | 2.48 | 2.50 | **REMOVED** |
| glib | 2.80 | 2.84 | 2.86 | 2.80 |
| libsecret | 0.21 | 0.21 | 0.21 | 0.21 |
| Zig | None | 0.14 | 0.15 | None |
| Wayland | Default | Default | Default | Default |

## Implementation Phases

### Phase 1: Terminal MVP (8-10 weeks)
- New `cmux_gtk` apprt in Ghostty fork
- Window + tabs (AdwTabView) + splits (reuse SplitTree)
- Socket IPC (already cross-platform)
- Nix flake for dev environment
- CI: ubuntu-latest + fedora:42 containers

### Phase 2: Browser Panel (4-6 weeks)
- WebKitGTK 6.0 integration
- JS bridge for WebAuthn (same injection pattern)
- Cookie management, devtools, find-in-page
- Flatpak manifest

### Phase 3: Platform Integration (2-3 weeks)
- GNotification for notifications
- libsecret via zig-keychain
- Session lock (logind D-Bus)
- hidraw hardening + udev rules

### Phase 4: Packaging + Polish (2-3 weeks)
- Flatpak on Flathub
- DEB/PPA for Ubuntu
- COPR for Fedora
- Desktop file, metainfo, icons
- CJK input testing (Fcitx5 + IBus)

## CI Matrix

```yaml
jobs:
  build-ubuntu:
    runs-on: ubuntu-latest        # GTK4 4.14 floor test

  build-fedora:
    runs-on: ubuntu-latest
    container: fedora:42           # Modern GNOME/GTK4 4.18

  build-arch:
    runs-on: ubuntu-latest
    container: archlinux:latest    # Bleeding-edge regression test
```

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Rocky 10 no WebKitGTK | Browser panel unavailable | Flatpak or terminal-only mode |
| GTK 4.20 dead keys regression | Japanese input broken on GNOME 49+ | Detect GTK version, apply `GTK_IM_MODULE=simple` fallback |
| Flatpak FIDO2 sandbox | Requires `--device=all` | Monitor credentialsd + USB portal progress |
| Ghostty GTK apprt churn | Upstream changes break fork | Pin Ghostty submodule, merge carefully |
| WebKitGTK stability | Documented rendering glitches | Test thoroughly, report upstream bugs |

## Sources

Full citations in individual research agent outputs. Key references:
- Ghostty GTK4 source: `ghostty/src/apprt/gtk/`
- WebKitGTK 6.0 API: webkitgtk.org/reference/webkitgtk/stable/
- Flatpak template: `ghostty/flatpak/com.mitchellh.ghostty.yml`
- RHEL 10 removed features: docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/
- Hyprland protocols: wiki.hypr.land
- FIDO2 udev rules: github.com/Yubico/libfido2/blob/main/udev/70-u2f.rules
