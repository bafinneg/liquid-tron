# Tron Compute — Nushell environment
# Managed via Stow — do not edit ~/.config/nushell/env.nu directly

# ── Starship prompt integration ──
mkdir ($nu.default-config-dir | path join "vendor" "autoload")
starship init nu | save -f ($nu.default-config-dir | path join "vendor" "autoload" "starship.nu")

# ── PATH ──
$env.PATH = ($env.PATH | split row (char esep)
    | prepend $"($env.HOME)/.local/bin"
    | prepend $"($env.HOME)/.cargo/bin"
    | uniq)

# ── pyenv ──
if ($"($env.HOME)/.pyenv/bin" | path exists) {
    $env.PYENV_ROOT = $"($env.HOME)/.pyenv"
    $env.PATH = ($env.PATH | prepend $"($env.PYENV_ROOT)/bin"
        | prepend $"($env.PYENV_ROOT)/shims"
        | uniq)
}

# ── nvm ──
$env.NVM_DIR = $"($env.HOME)/.nvm"

# ── fzf ──
$env.FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'
$env.FZF_CTRL_T_COMMAND = $env.FZF_DEFAULT_COMMAND
$env.FZF_ALT_C_COMMAND = 'fd --type d --hidden --follow --exclude .git'
$env.FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border'

# ── zoxide ──
zoxide init nushell | save -f ($nu.default-config-dir | path join "vendor" "autoload" "zoxide.nu")
