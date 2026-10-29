# liquid-tron

Liquid Tron desktop (Hyprland, Quickshell, Noctalia, themes, shell and editor configs) as a
[chezmoi](https://www.chezmoi.io) source. Files live under `home/` (`.chezmoiroot`). Host-specific values
(monitor serials, identity, URLs) are template data; defaults are placeholders in `.chezmoidata.toml`.

```
chezmoi init --source <this clone> --apply      # then edit ~/.config/chezmoi/chezmoi.toml [data]
scripts/verify-render.sh                         # host render == live files (needs host data file)
scripts/verify-generic.sh                        # placeholders render cleanly
scripts/leak-gate.sh                             # gitleaks + blocklist before any public push
```
Modules are in `docs/modules/`. Secrets never enter this repository.
