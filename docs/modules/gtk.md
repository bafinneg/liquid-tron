# gtk Stow package

This package manages GTK 3 and GTK 4 **settings** — not theme files.

## What's in the package

- `.config/gtk-3.0/settings.ini` — GTK 3 settings (theme name, icon
  theme, cursor, font, etc.)
- `.config/gtk-4.0/settings.ini` — GTK 4 settings (same)

## What's NOT in the package (lives loose in `~/.config/gtk-4.0/`)

- `assets/` — symlink to `~/.themes/<theme>/gtk-4.0/assets`
- `gtk.css` — symlink to `~/.themes/<theme>/gtk-4.0/gtk.css`
- `gtk-dark.css` — symlink to `~/.themes/<theme>/gtk-4.0/gtk-dark.css`

Created by the upstream Tokyonight installer with `--libadwaita`.
Intentionally NOT Stow-managed: theme upgrades happen via
`install.sh` re-runs, not repo commits, and committing regenerated
assets would bloat the repo.

## Theme strategy (post-spec 5a)

**GTK4 / libadwaita:** `Tokyonight-Tron` (repo-owned fork of
`Tokyonight-Teal-Dark`; base bg shifted to `#0a0a14` to match Tron
Compute). This is the surface that matters — most modern GUI apps
are GTK4/libadwaita. The file picker is **GTK3**, not GTK4:
`xdg-desktop-portal-gtk` 1.15.3 links `libgtk-3` and serves
`FileChooser=gtk` (`~/.config/xdg-desktop-portal/portals.conf`), so the
portal chooser follows the GTK3 sheet (corrected in FEAT-lt26r-2).

A libadwaita 1.10 completion fragment (sidebar, secondary-sidebar and
thumbnail colours on Tron tokens, accent fill Tron blue `#0072ff`,
`--window-radius: 8px`) was built and reviewed in FEAT-lt26r-2 but **not
merged**: Brian judged Thunar, the portal chooser and satty conforming
without it (2026-10-20). It is kept on branch
`lt26r/FEAT-lt26r-2-g-libadwaita` for a later material gap.

The upstream `~/.themes/Tokyonight-Teal-Dark/` is left installed but
no longer referenced. It's kept as a fallback and as the reference
the fork was built from. See
`machines/7800x/dotfiles/tokyonight-tron/README.md` and
`shared/themes/sources/tokyonight-tron/` for the fork's build
recipe.

**GTK3:** `Tokyonight-Tron` (same fork as GTK4). GTK3 apps follow
`gsettings org.gnome.desktop.interface gtk-theme` at runtime, which
overrides the `gtk-theme-name=` line in `gtk-3.0/settings.ini`.
Spec 5a set `gtk-3.0/settings.ini` to `Adwaita-dark` as a pure-CSS
fallback because the Tokyonight GTK3 variant *at build time*
required `gtk-engine-murrine`, which depends on `gtk2`, which is
broken in AUR (Python 3.12's `distutils` removal). But empirically,
**the built GTK3 theme works without murrine at runtime** — upstream
Tokyonight-Teal-Dark was already rendering Thunar correctly on this
box with no murrine installed. GTK3 silently skips the
murrine-specific engine hooks and renders the pure-CSS portions of
the stylesheet, which include all the base bg / fg / headerbar /
treeview declarations that matter for Tron Compute parity.

The post-addendum `gtk-3.0/settings.ini` reflects this: it now
points at `Tokyonight-Tron`, aligning file state with runtime state.
GTK3 apps like Thunar load
`~/.themes/Tokyonight-Tron/gtk-3.0/gtk-dark.css` (because
`gtk-application-prefer-dark-theme=true` prefers the dark variant).
You may see a GTK parsing warning on startup about `border-spacing`
not being a valid property name — that's an upstream CSS quirk in a
property GTK3 doesn't recognize; GTK3 skips it and continues
rendering. It was present under Tokyonight-Teal-Dark too.

If you want to return to Adwaita-dark as GTK3's fallback (e.g. to
isolate a rendering problem), set both `gsettings gtk-theme
Adwaita-dark` *and* `gtk-3.0/settings.ini` — changing only one of
the two leaves a precedence discrepancy that will surface as
"repo says X, runtime is Y."

**Icons:** Nordzy-cyan-dark (switched from Papirus-Dark during spec 5).
`gtk-icon-theme-name=` in both `gtk-3.0/settings.ini` and
`gtk-4.0/settings.ini`.

**Cursor:** Bibata-Original-Tron @ 24 (renamed from Bibata-Original-Amber
post-spec-5a; same Bibata base, rice-specific variant).

## Theme upgrade procedure

The active theme is now the `Tokyonight-Tron` fork, not upstream
Tokyonight-Teal-Dark. Upgrades go through the fork's rebuild recipe:

```bash
~/home-infra/shared/themes/sources/tokyonight-tron/build.sh
```

That script clones upstream at the pinned commit in `UPSTREAM`,
applies `tokyonight-tron.patch`, rebuilds, and deposits the result
at `/tmp/tokyonight-tron-build/Tokyonight-Tron/`. After reviewing
the diff, rsync `gtk-4.0/` and `index.theme` into
`machines/7800x/dotfiles/tokyonight-tron/.themes/Tokyonight-Tron/`
and commit. See `shared/themes/sources/tokyonight-tron/README.md`
for details.

**Do not re-run upstream `install.sh --libadwaita` from `/tmp/
Tokyonight-GTK-Theme` on this machine.** It will overwrite the
libadwaita symlinks in `~/.config/gtk-4.0/` to point at
`Tokyonight-Teal-Dark`, silently detaching the live GTK4 surface
from the repo-managed fork. If you need the fallback theme
refreshed (spec 5a's `~/.themes/Tokyonight-Teal-Dark/` is kept as
a reference), run install.sh **without** `--libadwaita` and then
re-point the symlinks manually to the Tron fork.

Historical note: the upstream theme directory name is
**`Tokyonight-Teal-Dark`** — the `-B` suffix from the upstream
README's abbreviation table (for "Bordered / outline tweak") is
stale. `--tweaks outline` modifies the compiled CSS but does NOT
append `-B` to the theme directory name as of the upstream commit
pinned in `shared/themes/sources/tokyonight-tron/UPSTREAM`.

## Uninstall / rollback

```bash
cd ~/home-infra/machines/7800x/dotfiles
stow -D gtk                    # unlink GTK3 + GTK4 settings.ini
cd /tmp/Tokyonight-GTK-Theme/themes
./install.sh -u --libadwaita   # remove libadwaita symlinks from ~/.config/gtk-4.0/
./install.sh -u                # remove ~/.themes/Tokyonight-Teal-Dark/
```

Orphan Breeze CSS fragments removed by spec 5a are backed up at
`~/.config/gtk-orphan-breeze.bak.<timestamp>/` — copy back if
Breeze/KDE theming is ever needed again.

## Related specs

- Spec 5a (`aesthetic-gtk-theme`) — this spec
- Spec 5b (`aesthetic-plasma-purge`) — KDE Plasma package removal;
  switches `xdg-desktop-portal-kde` → `-gtk` (gtk is already
  installed, but the routing config needs updating)
- Spec 5c (`aesthetic-kvantum-activation`) — Qt app theming
- Spec 5d (`aesthetic-firefox-userchrome`) — Firefox `userChrome.css`
