-- ╔══════════════════════════════════════════════════════════════╗
-- ║  CYBERPUNK NEON — Neovim Config                            ║
-- ║  Palette: Cyan #0abdc6 · Magenta #ff003c · Amber #ff8c00  ║
-- ║  Base: #0a0a14 · Font: IosevkaTerm Nerd Font               ║
-- ╚══════════════════════════════════════════════════════════════╝

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Leader key before lazy
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Core options
require("config.options")

-- Plugin manager
require("lazy").setup("plugins", {
  install = { colorscheme = { "cyberpunk-neon" } },
  checker = { enabled = true, notify = false },
  change_detection = { notify = false },
  ui = {
    border = "rounded",
    icons = {
      cmd = " ",
      config = " ",
      event = " ",
      ft = " ",
      init = " ",
      keys = " ",
      plugin = " ",
      runtime = " ",
      source = " ",
      start = " ",
      task = " ",
    },
  },
})

-- Keymaps and autocommands
require("config.keymaps")
require("config.autocmds")
