# chrome-theme — Liquid Tron for Google Chrome

## Purpose

A colors-only Liquid Tron Chrome theme (manifest v3 `theme.colors`). It has no permissions, scripts,
images, remote content or Web Store listing. Spec: `FEAT-lt26r-2-toolkit-parity` (carries over the
archived `FEAT-lt26-06-chrome-browser-parity` OD1 = A and OD2 = cyan selected-tab title).

| Surface | Token | Hex |
|---|---|---|
| Tab strip (focused and unfocused) | `bg_dark` | `#06060c` |
| Toolbar, selected tab, New Tab page | `bg` | `#0a0a14` |
| Address field | `bg_inset` | `#0e0e1c` |
| Selected tab title, New Tab links | `cyan` | `#0abdc6` |
| Background tab titles | `fg_dim` | `#707080` |
| Toolbar text and icons, bookmarks, address text, New Tab text | `fg` | `#c0c0d0` |

Incognito windows keep Chrome's own styling.

## Install

Always stow this package with `--no-folding`. Stow then creates `~/.local/share/liquid-tron/` and
`~/.local/share/liquid-tron/chrome-theme/` as real directories, and only `manifest.json` is a symlink
into the repository. Chrome writes its `Cached Theme.pak` next to the manifest, so the real
directory keeps that file out of the repository. Stow ignores this README and `.gitignore` by default.

```bash
cd ~/home-infra
stow -d machines/7800x/dotfiles -t ~ -n -v --no-folding chrome-theme   # dry run: MKDIR/LINK only, no CONFLICT
stow -d machines/7800x/dotfiles -t ~ --no-folding chrome-theme
```

Then load it once in Chrome: `chrome://extensions` → Developer mode on → **Load unpacked** →
select `~/.local/share/liquid-tron/chrome-theme`.

## Update

Edit `manifest.json` to follow the palette mapping above (a change to `bg_dark`, `bg`, `bg_inset`,
`fg`, `fg_dim` or `cyan` in `shared/themes/palettes/tron-compute.yaml` is not propagated
automatically; `machines/7800x/tests/test_chrome_theme.py` fails until the manifest matches), bump
`version`, then click the reload arrow on the Liquid Tron card in `chrome://extensions`. After a Chrome
upgrade, check that the card still shows no errors.

## Remove

1. Remove Liquid Tron in `chrome://extensions`.
2. Re-select the previous theme mode, Mode and color in `chrome://settings/appearance`.
3. Archive the target directory by a non-overwriting rename, for example
   `mv -n ~/.local/share/liquid-tron/chrome-theme ~/.local/share/liquid-tron/chrome-theme.retired-$(date +%Y%m%d)`.
   Never use `stow -D`, `rm` or `rmdir` here.

## Notes

- Keep Developer mode on. The extension ID derives from the absolute path, so keep the path stable.
- Chrome holds one theme at a time. A Web Store theme, a Customize-Chrome color or a theme policy
  replaces this one.
- Never edit Chrome's `Preferences` by hand, and never automate Chrome against Brian's profile.
