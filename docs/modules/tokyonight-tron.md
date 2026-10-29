# tokyonight-tron Stow package

Forked GTK 3 + GTK 4 theme. Maps Tokyonight-Teal-Dark's three-tier
dark surface stack onto the Tron Compute palette's surface tokens,
closing the ~16-lightness-point gap between Thunar and
terminal/editor surfaces. Built at **compact** size so the
headerbar, buttons, and root font don't dwarf kitty/MOCR-Q bar.

## Surface mapping

Three SCSS palette tokens rerouted in
`_color-palette-default.scss`; every other Tokyonight color stays as
upstream defines it.

| Upstream Tokyonight         | Fork value     | Tron Compute token | What it drives in the live CSS                                                |
|-----------------------------|----------------|--------------------|-------------------------------------------------------------------------------|
| `$black       = #1a1b26`    | **`#0a0a14`**  | `bg`               | `.background`, headerbar, menubar, sidebar, `$titlebar`, `$frame`, `$border` |
| `$grey-750    = #292e42`    | **`#0d0d1a`**  | `bg_alt`           | `$surface` → cards, popovers, elevated chrome                                 |
| `$grey-700    = #323449`    | **`#0e0e1c`**  | `bg_inset`         | `$base` / `$card` → `.view`, treeview content pane, input fields, textview   |

The initial fork only patched `$black` (single-token approach). That
left Thunar's content pane (driven by `.view` → `$base` → `$grey-700`)
rendering at storm-grey `#323449`, which Brian flagged as "entirely
different shade" from kitty. The fix was to map all three dark
surface tiers onto Tron's native four-tier palette
(`bg` / `bg_dark` / `bg_alt` / `bg_inset`) rather than collapsing
them flat — Thunar now has a subtle inset-surface hint for its content
pane (`#0e0e1c`, ~4 lightness points above `bg`) that matches the
pattern nvim uses for `cursorline`, while sidebar and chrome
surfaces all sit on `bg` proper.

## Compact size

Built with upstream `install.sh -s compact`. That switches
`_tweaks.scss` `$compact: 'false' → 'true'`, which affects
`_variables.scss`:

- `$space-size`      6px → 4px
- `$small-size`      24px → 22px
- `$medium-size`     34px → 30px
- `$large-size`      **46px → 38px** (drives headerbar buttons)
- `$root-font-size`  14px → 13px
- `$menuitem-size`   28px → 24px

Without this flag, Thunar's headerbar (hamburger, back/forward/up/home
buttons, path bar) renders chunky enough to visibly disagree with
kitty's slimmer chrome. The compact size keeps the fork proportional
to the rest of the Liquid Tron rice.

## Radius conformance (Liquid Tron §4)

Liquid Tron's radius rule is **chrome 8px / interactive 6px /
hard-edged 0px**. Upstream Tokyonight uses 12/9/12 for
window/modal/corner and builds compound expressions like
`$modal-radius + $space-size` that compute to 12px in
compact mode. The fork's `_variables.scss` edit sets the base
variables:

- `$window-radius` 12px → **8px** (matches Hyprland
  `decoration { rounding = 8 }` — eliminates the corner-clipping
  artifact where GTK's larger corner was trimmed by the compositor
  corner)
- `$modal-radius`  9px → **8px**
- `$corner-radius` 12px → **8px**
- `$menuitem-radius` inherited → **6px** (explicit override)

The variable edit alone doesn't flatten every radius because
Tokyonight's widget stylesheets (`_common-3.0.scss`,
`_common-4.0.scss`, plus two `apps/` subfiles) contain 12 compound
expressions of the form `$modal-radius + $space-size` or
`$corner-radius + 1px`. Those were producing 9 / 10 / 12 px radii
that violate the §4 scale (and, for the 12px cases, the §1
anti-pattern "no radii above 10px"). The radius half of the patch
hand-flattens each compound expression to either `$corner-radius`/
`$modal-radius` (chrome) or `$menuitem-radius` (interactive).

### Selectors patched

**Chrome → `$corner-radius` / `$modal-radius` (8 px):**

- `notebook.frame` (GTK 3 + GTK 4)
- `%toolbar_osd` / `.app-notification` / `.toolbar.osd` (GTK 4)

**Interactive → `$menuitem-radius` (6 px):**

- `notebook > header` (GTK 3 + GTK 4)
- `%circular_list` (GTK 3 + GTK 4)
- `list row:selected` (GTK 3)
- Toolbar with inset `-2px` shadow (GTK 3 + GTK 4)
- `stackswitcher` (GTK 3 + GTK 4)
- `viewswitcher` (libadwaita)
- Epiphany `tabbox` (GTK 3 GNOME apps file — not used on this
  machine but patched for correctness)

**Left at upstream 9 px (intentionally unpatched dead code):**

- `#MatePanelPopupWindow`, `.mate-panel-applet-slider`,
  `.lock-dialog` — MATE desktop-specific GTK 3 selectors that
  never render on a Hyprland-only machine. Fixing them would add
  three patch hunks for zero visible benefit.

## What's in the package

```
.themes/Tokyonight-Tron/
├── index.theme
├── gtk-3.0/
│   ├── assets/
│   ├── gtk.css
│   ├── gtk-dark.css
│   └── thumbnail.png
└── gtk-4.0/
    ├── assets/
    ├── gtk.css
    ├── gtk-dark.css
    └── thumbnail.png
```

## What's NOT in the package

- `gtk-2.0/`, `gnome-shell/`, `cinnamon/`, `metacity-1/`, `xfwm4/`,
  `plank/` — upstream emits these during build, but nothing on the
  7800X consumes them:
  - GTK2 apps aren't themed at all (no GTK2 app surface on this box).
  - GNOME Shell / Cinnamon / metacity / xfwm / plank aren't running
    anywhere on this machine.
- Upstream install.sh also emits `-hdpi` and `-xhdpi` sibling
  directories for xfwm4 only — ignored for the same reason.

Keeping the package to GTK 3 + GTK 4 only makes it ~1.3 MB instead of
~5 MB and keeps the diff reviewable.

## Why GTK 3 is included (post-addendum note)

The original fork ship was GTK 4 only, on the stated rationale that
spec 5a had pivoted GTK 3 to `Adwaita-dark` because the Tokyonight
GTK 3 variant needed `gtk-engine-murrine` (broken in AUR). That was
wrong — the *repo state* said Adwaita-dark, but the *runtime state*
was still on Tokyonight-Teal-Dark GTK 3 because **`gsettings
org.gnome.desktop.interface gtk-theme` overrides
`gtk-3.0/settings.ini`** for GTK 3 apps that read gsettings (which
is most modern GTK 3 apps, including Thunar). The `settings.ini`
line spec 5a set was dead state.

After shipping the GTK-4-only fork, Thunar rendered solid white
because it was following gsettings → `Tokyonight-Tron` → tried to
load `~/.themes/Tokyonight-Tron/gtk-3.0/gtk.css` → not present →
fell through to the GTK default (Adwaita light). Adding the GTK 3
subdir fixed it.

Empirical fact: the Tokyonight GTK 3 theme **does render without
murrine installed**. GTK 3 silently skips murrine engine hooks and
continues. You may see a GTK parsing warning about `border-spacing`
on theme load — that's an upstream CSS quirk unrelated to murrine,
and it was present under Tokyonight-Teal-Dark too.

The lesson: when a repo config file disagrees with its `gsettings`
equivalent, `gsettings` is what you actually get at runtime. Check
both when reasoning about theme state.

## What this fork does and does not change

- The source patch remaps the dark surface stack and both teal accent tokens to
  Tron Compute cyan `#0abdc6`, and reduces chrome/interactive radii to the Liquid
  Tron scale. Warning, error, success, selection, and other semantic roles remain
  upstream application-native values unless the reproducible source patch states
  otherwise.
- `decoration { margin: 10px }` — upstream's drop-shadow reservation
  area around CSD windows. Creates a visible 10px transparent gap
  between the window content and what the compositor considers the
  window boundary. Leaving it at upstream default for now — Hyprland's
  own shadow config would compete if we reduced it. If chrome still
  reads as "chunky" after this commit, the `decoration { margin }`
  value is the next thing to tune.
- libadwaita CSS symlinks in `~/.config/gtk-4.0/` — those are
  maintained by hand (not Stow-managed), same pattern as the `gtk`
  package. See that package's README.

## Stow target

Targets `~/.themes/Tokyonight-Tron/`. This is a new convention for the
repo: upstream `Tokyonight-Teal-Dark` was never Stow-managed because
its upgrade path is `install.sh` re-run (per `gtk/README.md`). The
fork is Stow-managed because *we* own it — the repo is the source of
truth and upstream no longer knows about it.

## Rebuilding the fork

See `shared/themes/sources/tokyonight-tron/` for the SCSS rebuild
recipe. It pins the upstream commit we forked from, carries the patch
as a single-file diff, and ships a `build.sh` that reproduces the
build from scratch.

When upstream ships a new version worth pulling in:

1. Update `shared/themes/sources/tokyonight-tron/UPSTREAM` with the
   new commit SHA.
2. Re-apply the patch (may need a rebase if upstream refactored
   `_color-palette-default.scss`).
3. Run `shared/themes/sources/tokyonight-tron/build.sh` — it
   installs to `/tmp/tokyonight-tron-build/Tokyonight-Tron/`.
4. `rsync` the rebuilt `gtk-4.0/` and `index.theme` into this
   package, restow, regenerate libadwaita symlinks.

## Activation (already done at ship time)

```bash
cd machines/7800x/dotfiles
stow -t ~ tokyonight-tron
# Re-point libadwaita CSS symlinks
cd ~/.config/gtk-4.0
ln -sfn ~/.themes/Tokyonight-Tron/gtk-4.0/assets      assets
ln -sfn ~/.themes/Tokyonight-Tron/gtk-4.0/gtk.css      gtk.css
ln -sfn ~/.themes/Tokyonight-Tron/gtk-4.0/gtk-dark.css gtk-dark.css
# gsettings + settings.ini already updated by this commit
```

## Rollback

```bash
cd ~/home-infra/machines/7800x/dotfiles
stow -D -t ~ tokyonight-tron          # unlinks ~/.themes/Tokyonight-Tron/
# Re-point libadwaita at the upstream theme
cd ~/.config/gtk-4.0
ln -sfn ~/.themes/Tokyonight-Teal-Dark/gtk-4.0/assets      assets
ln -sfn ~/.themes/Tokyonight-Teal-Dark/gtk-4.0/gtk.css      gtk.css
ln -sfn ~/.themes/Tokyonight-Teal-Dark/gtk-4.0/gtk-dark.css gtk-dark.css
# Revert gtk-4.0/settings.ini gtk-theme-name line
# gsettings set org.gnome.desktop.interface gtk-theme Tokyonight-Teal-Dark
```

The upstream `~/.themes/Tokyonight-Teal-Dark/` is untouched by this
fork — rollback is purely a pointer change.

## Parent spec

Polish addendum to spec 5a (`aesthetic-gtk-theme`, `specs/done/`). Not
a new spec — the fork is a palette remapping + a build-flag choice,
not a new surface.
