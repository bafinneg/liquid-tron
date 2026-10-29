# qt-bridge Stow package

Sets QT_QPA_PLATFORMTHEME=qt5ct and provides a Tokyonight-Tron
color scheme so Qt5 apps render with black background, cyan text,
and ~85% opacity — matching the Liquid Tron aesthetic.

## What's in the package

- `.config/environment.d/qt-bridge.conf` — sets QT_QPA_PLATFORMTHEME=qt5ct
- `.config/qt5ct/qt5ct.conf` — qt5ct config pointing to the color scheme
- `.config/qt5ct/colors/tokyonight-tron.conf` — Tokyonight-Tron QPalette

## Required packages (not Stow-managed)

- `qt5ct` (extra) — Qt5 platform theme with color scheme support

## How it works

qt5ct intercepts Qt5 palette construction and applies the custom
color scheme. The env var is set via environment.d (session-wide)
and also in hyprland.conf env (for Hyprland-dispatched apps).

KDE Frameworks apps (kdeconnect) use their own style engine and
ignore QT_QPA_PLATFORMTHEME — this is expected and accepted.

## Surviving Qt apps (post-spec-5b/5c)

- openrgb (Qt5) — themed by qt5ct
- kdeconnect (Qt6, KDE Frameworks) — unaffected, background daemon

## Not Qt any more (FEAT-lt26r-2)

- The authentication prompt left Qt: `hyprpolkitagent` 0.2.0 links
  `libhyprtoolkit.so.6` and no Qt, and `hyprland-dialog` uses the same
  toolkit. They are themed by `~/.config/hypr/hyprtoolkit.conf` (`hypr`
  Stow package), not by this package or qt6ct. The archived 07B Qt6
  dialog bridge is obsolete.
- KDE Frameworks message boxes (`kdialog`) read `~/.config/kdeglobals`, not
  qt5ct. `machines/7800x/scripts/kdeglobals-retire-daemon.sh` retires the
  legacy Daemon palette there when needed (backup first, `--dry-run`).

## Related

- Spec 5a — installed Tokyonight GTK theme
- Spec 5b — removed Plasma and shrunk Qt surface
- Spec 5c — this spec
