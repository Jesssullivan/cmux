# CJK Input Testing (Fcitx5 + IBus)

## Overview

cmux-linux uses GTK4's built-in input method support. CJK (Chinese, Japanese, Korean) input requires testing with the two major Linux input method frameworks.

## Test Matrix

| Framework | DE | Test |
|-----------|-----|------|
| Fcitx5 | GNOME Wayland | Pinyin, Romaji, Hangul composition |
| Fcitx5 | Sway | Same as above |
| IBus | GNOME Wayland | Pinyin, Romaji, Hangul composition |
| IBus | KDE Plasma | Same as above |

## Setup

### Fcitx5
```bash
# Fedora
sudo dnf install fcitx5 fcitx5-chinese-addons fcitx5-anthy fcitx5-hangul fcitx5-gtk4

# Ubuntu
sudo apt install fcitx5 fcitx5-chinese-addons fcitx5-anthy fcitx5-hangul

# Environment
export GTK_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
```

### IBus
```bash
# Fedora
sudo dnf install ibus ibus-libpinyin ibus-anthy ibus-hangul

# Ubuntu
sudo apt install ibus ibus-libpinyin ibus-anthy ibus-hangul

# Environment
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
```

## Test Cases

1. **Preedit display**: Type romaji → verify preedit underlined text appears in terminal
2. **Candidate selection**: Press Space → verify candidate window appears near cursor
3. **Commit**: Select candidate → verify composed character appears in shell
4. **Mixed input**: Alternate between CJK and ASCII without mode switch lag
5. **Multi-surface**: Verify IME state is per-surface (not global across splits)

## libghostty Integration

cmux-linux forwards IME events via the ghostty C API:
- `ghostty_surface_preedit()` — preedit composition string
- `ghostty_surface_text()` — committed text

GTK4 handles the input method framework integration automatically through `GtkIMContext`. The key requirement is that `GtkGLArea` widgets are focusable (`gtk_widget_set_focusable(true)`), which is already set in `surface.zig`.

## Known Issues

- Fcitx5 on Wayland requires `fcitx5-gtk4` package for native integration
- IBus may not work correctly with software-rendered surfaces (headless mode)
- Some IME frameworks need `GDK_BACKEND=wayland` explicitly set
