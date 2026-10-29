-- ── Treesitter ───────────────────────────────────────────────
return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("nvim-treesitter").setup({
        ensure_installed = {
          "bash", "c", "css", "dockerfile", "html", "javascript",
          "json", "lua", "markdown", "markdown_inline", "python",
          "query", "regex", "rust", "sql", "toml", "tsx",
          "typescript", "vim", "vimdoc", "yaml",
        },
        auto_install = true,
      })
    end,
  },
}
