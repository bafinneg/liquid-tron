# Tron Compute — Nushell config
# Managed via Stow — do not edit ~/.config/nushell/config.nu directly

$env.config = {
    show_banner: false

    color_config: {
        separator: { fg: "#505060" }
        leading_trailing_space_bg: { attr: n }
        header: { fg: "#0abdc6" attr: b }
        empty: { fg: "#0072ff" }
        bool: { fg: "#0abdc6" }
        int: { fg: "#e0e0f0" }
        filesize: { fg: "#0abdc6" }
        duration: { fg: "#e0e0f0" }
        date: { fg: "#ff8c00" }
        range: { fg: "#e0e0f0" }
        float: { fg: "#e0e0f0" }
        string: { fg: "#c0c0d0" }
        nothing: { fg: "#707080" }
        binary: { fg: "#e0e0f0" }
        cell-path: { fg: "#0abdc6" }
        row_index: { fg: "#707080" }
        record: { fg: "#c0c0d0" }
        list: { fg: "#c0c0d0" }
        block: { fg: "#0072ff" }
        hints: { fg: "#707080" }

        shape_and: { fg: "#0072ff" attr: b }
        shape_binary: { fg: "#0072ff" }
        shape_block: { fg: "#0072ff" }
        shape_bool: { fg: "#0abdc6" }
        shape_closure: { fg: "#0072ff" }
        shape_custom: { fg: "#0abdc6" }
        shape_datetime: { fg: "#ff8c00" }
        shape_directory: { fg: "#0abdc6" }
        shape_external: { fg: "#00ff9f" }
        shape_externalarg: { fg: "#c0c0d0" }
        shape_filepath: { fg: "#0abdc6" }
        shape_flag: { fg: "#0072ff" }
        shape_float: { fg: "#e0e0f0" }
        shape_garbage: { fg: "#ff003c" attr: b }
        shape_glob_interpolation: { fg: "#0abdc6" }
        shape_globpattern: { fg: "#0abdc6" }
        shape_int: { fg: "#e0e0f0" }
        shape_internalcall: { fg: "#0abdc6" attr: b }
        shape_keyword: { fg: "#0072ff" attr: b }
        shape_list: { fg: "#0abdc6" }
        shape_literal: { fg: "#0072ff" }
        shape_match_pattern: { fg: "#0abdc6" }
        shape_nothing: { fg: "#707080" }
        shape_operator: { fg: "#ff8c00" }
        shape_or: { fg: "#0072ff" attr: b }
        shape_pipe: { fg: "#0072ff" attr: b }
        shape_range: { fg: "#ff8c00" }
        shape_record: { fg: "#0abdc6" }
        shape_redirection: { fg: "#0072ff" }
        shape_signature: { fg: "#0072ff" }
        shape_string: { fg: "#00ff9f" }
        shape_string_interpolation: { fg: "#0abdc6" }
        shape_table: { fg: "#0072ff" }
        shape_variable: { fg: "#0abdc6" }
        shape_vardecl: { fg: "#0abdc6" attr: b }
        shape_raw_string: { fg: "#00ff9f" }
    }

    history: {
        max_size: 50_000
        sync_on_enter: true
        file_format: "sqlite"
        isolation: false
    }

    completions: {
        case_sensitive: false
        quick: true
        partial: true
        algorithm: "fuzzy"
    }

    keybindings: [
        {
            name: forward_word
            modifier: control
            keycode: right
            mode: [emacs, vi_insert]
            event: { edit: movewordright }
        }
        {
            name: backward_word
            modifier: control
            keycode: left
            mode: [emacs, vi_insert]
            event: { edit: movewordleft }
        }
        {
            name: delete_word_backward
            modifier: control
            keycode: backspace
            mode: [emacs, vi_insert]
            event: { edit: backspaceword }
        }
        {
            name: fzf_file
            modifier: control
            keycode: char_t
            mode: [emacs, vi_insert]
            event: {
                send: executehostcommand
                cmd: "commandline edit --insert (fd --type f --hidden --follow --exclude .git | fzf --height 40% --layout=reverse --border | str trim)"
            }
        }
        {
            name: fzf_dir
            modifier: alt
            keycode: char_c
            mode: [emacs, vi_insert]
            event: {
                send: executehostcommand
                cmd: "cd (fd --type d --hidden --follow --exclude .git | fzf --height 40% --layout=reverse --border | str trim)"
            }
        }
        {
            name: fzf_history
            modifier: control
            keycode: char_r
            mode: [emacs, vi_insert]
            event: {
                send: executehostcommand
                cmd: "commandline edit --replace (history | each { |it| $it.command } | uniq | reverse | str join (char newline) | fzf --height 40% --layout=reverse --border | str trim)"
            }
        }
    ]
}

# ── fastfetch on startup ──
fastfetch

# ── Shared aliases (generated from shared/shell/aliases.toml) ──
source aliases.nu

# ── Email (needs env override, can't be a simple alias) ──
def email [] {
    with-env { TERM: "xterm-direct" } { ^neomutt }
}

# ── SSH with colored terminal ──
def --wrapped ssh [...args: string] {
    print -n $"(ansi -e '10;#39ff14')"
    ^ssh ...$args
    print -n $"(ansi -e '110;')"
}

# ── Alfred (home-infra agent) ──
def --wrapped alfred [...args: string] {
    print -n $"(ansi -e '11;#0a1929')"
    cd ~/home-infra
    ^claude ...$args
    print -n $"(ansi -e '111;')"
}

# ── Music launcher ──
def music [] {
    ^$"($env.HOME)/.local/bin/music"
}

# ── Claude Code tmux session (4-pane split) ──
def t-claude [] {
    if (^tmux has-session -t claude | complete).exit_code == 0 {
        ^tmux attach -t claude
    } else {
        ^tmux new-session -d -s claude -n main claude
        ^tmux split-window -h -t "claude:main" claude
        ^tmux split-window -v -t "claude:main.0" claude
        ^tmux split-window -v -t "claude:main.1" claude
        ^tmux select-layout -t "claude:main" tiled
        ^tmux attach -t claude
    }
}
