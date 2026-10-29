-- ── Options ──────────────────────────────────────────────────
local opt = vim.opt

-- UI
opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.termguicolors = true
opt.pumblend = 15          -- popup menu transparency
opt.winblend = 10          -- floating window transparency
opt.showmode = false       -- lualine handles this
opt.laststatus = 3         -- global statusline
opt.cmdheight = 0          -- hide command line when not in use
opt.scrolloff = 8
opt.sidescrolloff = 8

-- Indentation
opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- Splits
opt.splitright = true
opt.splitbelow = true

-- Files
opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.undodir = vim.fn.stdpath("data") .. "/undo"

-- Performance
opt.updatetime = 200
opt.timeoutlen = 300

-- Completion
opt.completeopt = { "menu", "menuone", "noselect" }

-- Clipboard — system clipboard integration
opt.clipboard = "unnamedplus"

-- Wrap
opt.wrap = false
opt.linebreak = true

-- Fill chars for cleaner UI
opt.fillchars = {
  eob = " ",
  fold = " ",
  foldopen = "▾",
  foldsep = "│",
  foldclose = "▸",
  vert = "│",
  horiz = "─",
  horizup = "┴",
  horizdown = "┬",
  vertleft = "┤",
  vertright = "├",
  verthoriz = "┼",
}

-- Mouse
opt.mouse = "a"
opt.mousemoveevent = true

-- Fold (using treesitter)
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevel = 99
opt.foldlevelstart = 99
