-- ── UI Plugins ───────────────────────────────────────────────
return {
  -- ── Neo-tree (file explorer) ──
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>n", "<cmd>Neotree toggle<cr>", desc = "Toggle file explorer" },
      { "<leader>N", "<cmd>Neotree reveal<cr>", desc = "Reveal in explorer" },
    },
    opts = {
      close_if_last_window = true,
      popup_border_style = "rounded",
      enable_git_status = true,
      window = {
        width = 32,
        mappings = {
          ["<space>"] = "none",
        },
      },
      filesystem = {
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        filtered_items = {
          visible = true,
          hide_dotfiles = false,
          hide_gitignored = true,
        },
      },
      default_component_configs = {
        indent = {
          with_expanders = true,
          expander_collapsed = "",
          expander_expanded = "",
        },
        icon = {
          folder_closed = "",
          folder_open = "",
          folder_empty = "",
        },
        git_status = {
          symbols = {
            added = "",
            modified = "",
            deleted = "",
            renamed = "➜",
            untracked = "★",
            ignored = "◌",
            unstaged = "✗",
            staged = "✓",
            conflict = "",
          },
        },
      },
    },
  },

  -- ── Which Key ──
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      plugins = { spelling = { enabled = true } },
      win = {
        border = "rounded",
      },
      spec = {
        { "<leader>f", group = "Find" },
        { "<leader>g", group = "Git" },
        { "<leader>b", group = "Buffer" },
        { "<leader>c", group = "Code" },
        { "<leader>d", group = "Diagnostics" },
        { "<leader>r", group = "Rename" },
        { "<leader>w", group = "Write" },
      },
    },
  },

  -- ── Indent Guides ──
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      indent = {
        char = "▏",
        tab_char = "▏",
      },
      scope = {
        enabled = true,
        show_start = false,
        show_end = false,
      },
      exclude = {
        filetypes = {
          "help", "alpha", "dashboard", "neo-tree", "Trouble",
          "lazy", "mason", "notify", "toggleterm",
        },
      },
    },
  },

  -- ── Gitsigns ──
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add          = { text = "▎" },
        change       = { text = "▎" },
        delete       = { text = "" },
        topdelete    = { text = "" },
        changedelete = { text = "▎" },
        untracked    = { text = "▎" },
      },
      current_line_blame = true,
      current_line_blame_opts = {
        delay = 500,
        virt_text_pos = "eol",
      },
      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns
        local map = function(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
        end
        map("n", "]h", gs.next_hunk, "Next hunk")
        map("n", "[h", gs.prev_hunk, "Previous hunk")
        map("n", "<leader>gs", gs.stage_hunk, "Stage hunk")
        map("n", "<leader>gr", gs.reset_hunk, "Reset hunk")
        map("n", "<leader>gp", gs.preview_hunk, "Preview hunk")
        map("n", "<leader>gb", gs.blame_line, "Blame line")
        map("n", "<leader>gd", gs.diffthis, "Diff this")
      end,
    },
  },

  -- ── Bufferline (tab bar) ──
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = "nvim-tree/nvim-web-devicons",
    event = "VeryLazy",
    opts = {
      options = {
        mode = "buffers",
        style_preset = 1,
        diagnostics = "nvim_lsp",
        diagnostics_indicator = function(_, _, diag)
          local icons = { error = " ", warning = " ", info = " " }
          local ret = ""
          for severity, icon in pairs(icons) do
            local n = diag[severity]
            if n then ret = ret .. icon .. n .. " " end
          end
          return vim.trim(ret)
        end,
        offsets = {
          {
            filetype = "neo-tree",
            text = "  FILES",
            text_align = "left",
            separator = true,
          },
        },
        separator_style = "thin",
        show_buffer_close_icons = false,
        show_close_icon = false,
      },
      highlights = {
        fill = { bg = "#06060c" },
        background = { fg = "#707080", bg = "#0a0a14" },
        buffer_selected = {
          fg = "#0abdc6",
          bg = "#0e0e1c",
          bold = true,
          italic = false,
        },
        buffer_visible = { fg = "#707080", bg = "#0a0a14" },
        separator = { fg = "#06060c", bg = "#0a0a14" },
        separator_selected = { fg = "#06060c", bg = "#0e0e1c" },
        indicator_selected = { fg = "#0abdc6", bg = "#0e0e1c" },
        modified = { fg = "#ff8c00", bg = "#0a0a14" },
        modified_selected = { fg = "#ff8c00", bg = "#0e0e1c" },
        tab_selected = { fg = "#0abdc6", bg = "#0e0e1c" },
        diagnostic_selected = { bold = true },
      },
    },
  },

  -- ── Noice (cmdline, messages, popups) ──
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
    },
    opts = {
      cmdline = {
        view = "cmdline_popup",
        format = {
          cmdline = { icon = "▸" },
          search_down = { icon = " ⌄" },
          search_up = { icon = " ⌃" },
          filter = { icon = "$" },
          lua = { icon = "" },
          help = { icon = "?" },
        },
      },
      lsp = {
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"] = true,
        },
        hover = { enabled = true },
        signature = { enabled = true },
      },
      presets = {
        bottom_search = false,
        command_palette = true,
        long_message_to_split = true,
        lsp_doc_border = true,
      },
    },
  },

  -- ── Notify ──
  {
    "rcarriga/nvim-notify",
    opts = {
      background_colour = "#0a0a14",
      fps = 60,
      render = "compact",
      stages = "fade",
      timeout = 3000,
      max_width = 60,
    },
  },

  -- ── Dashboard ──
  {
    "goolord/alpha-nvim",
    event = "VimEnter",
    config = function()
      local alpha = require("alpha")
      local dashboard = require("alpha.themes.dashboard")

      -- ATLAS globe — static-quiet-large (living substrate, calm)
      dashboard.section.header.val = {
        "",
        "                     ....  . .",
        "               .. .. .. .. .... . .#",
        "             ..... .  : . .   . . . ...",
        "           .... .  .  :  :.  . : .  .....",
        "         .. : :  .. :: # :   . .  . : . . ..",
        "       ...:  . .   :    :   :  .  . :  :. ...",
        "      ..:. : . : :  : :  : :  :  :  .  : :: ..",
        "     ..: ::    : :     :  : :   :  :  :  :. ...",
        "    .. .: :  :    : :   :     :  :   :  . : ...",
        "    .: . . : : :   : :   :  ::  :  :   ::  .. ..",
        "   .   . : :  : :   :  :   #   : : : : :  :  ..",
        "    . .     :  : :    : :    :   :   :   ::. . .",
        "   ..:: : :  :  :  :   :  :    :   :   ::  :  ..",
        "    :. : : :   :  : :    :  : : : :  ::   : :.",
        "    .:. : : :   :  :  :    :   :    :   :  :: :",
        "     ..: : :  :   :  :  : :  :   :   : : *: ..",
        "      :. : : : :    :  :   :  : :  ::   :: .:",
        "       .::: :  : : :  :  #:  :    ::  ::  :",
        "         :: : : :    : :    :  ::   :  :: .",
        "          .:: : : : :  : : :  ::  :: *: .",
        "            ::: : : : : : : : : :: :: :",
        "               .::: :: : : :: :: : :",
        "                    :. .. :: : :",
        "",
      }

      dashboard.section.buttons.val = {
        dashboard.button("f", "  Find file", "<cmd>Telescope find_files<cr>"),
        dashboard.button("r", "  Recent files", "<cmd>Telescope oldfiles<cr>"),
        dashboard.button("g", "  Live grep", "<cmd>Telescope live_grep<cr>"),
        dashboard.button("n", "  New file", "<cmd>ene <BAR> startinsert<cr>"),
        dashboard.button("c", "  Config", "<cmd>e $MYVIMRC<cr>"),
        dashboard.button("l", "  Lazy", "<cmd>Lazy<cr>"),
        dashboard.button("m", "  Mason", "<cmd>Mason<cr>"),
        dashboard.button("q", "  Quit", "<cmd>qa<cr>"),
      }

      -- Cyberpunk colors for dashboard
      dashboard.section.header.opts.hl = "AlphaHeader"
      for _, button in ipairs(dashboard.section.buttons.val) do
        button.opts.hl = "AlphaButtons"
        button.opts.hl_shortcut = "AlphaShortcut"
      end
      dashboard.section.footer.opts.hl = "AlphaFooter"

      dashboard.section.footer.val = {
        "⟨ SYSTEM://ONLINE ⟩  ⟨ NEURAL://LINKED ⟩  ⟨ READY ⟩",
      }

      alpha.setup(dashboard.opts)

      -- Disable folding on alpha buffer
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "alpha",
        callback = function()
          vim.opt_local.foldenable = false
        end,
      })
    end,
  },

  -- ── Autopairs ──
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require("nvim-autopairs").setup({
        check_ts = true,
      })
      -- Integrate with cmp
      local ok, cmp = pcall(require, "cmp")
      if ok then
        local cmp_autopairs = require("nvim-autopairs.completion.cmp")
        cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
      end
    end,
  },

  -- ── Comment ──
  {
    "numToStr/Comment.nvim",
    keys = {
      { "gcc", mode = "n", desc = "Comment line" },
      { "gc", mode = "v", desc = "Comment selection" },
    },
    opts = {},
  },

  -- ── Surround ──
  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    opts = {},
  },

  -- ── Todo Comments ──
  {
    "folke/todo-comments.nvim",
    dependencies = "nvim-lua/plenary.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      colors = {
        error = { "#ff003c" },
        warning = { "#ff8c00" },
        info = { "#0abdc6" },
        hint = { "#00ff9f" },
        default = { "#ff003c" },
      },
    },
  },

  -- ── Trouble (diagnostics list) ──
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics" },
    },
    opts = {
      use_diagnostic_signs = true,
    },
  },

  -- ── Toggleterm ──
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    keys = {
      { "<C-\\>", desc = "Toggle terminal" },
      { "<leader>tf", desc = "Float terminal" },
      { "<leader>th", desc = "Horizontal terminal" },
    },
    opts = {
      size = function(term)
        if term.direction == "horizontal" then return 15
        elseif term.direction == "vertical" then return vim.o.columns * 0.4
        end
      end,
      open_mapping = [[<C-\>]],
      direction = "float",
      float_opts = {
        border = "rounded",
        winblend = 10,
      },
      highlights = {
        FloatBorder = { link = "FloatBorder" },
      },
    },
  },

  -- ── Web devicons ──
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
    opts = {
      override_by_extension = {
        ["py"] = { icon = "", color = "#0abdc6", name = "Python" },
        ["lua"] = { icon = "", color = "#0abdc6", name = "Lua" },
        ["rs"] = { icon = "", color = "#ff8c00", name = "Rust" },
        ["js"] = { icon = "", color = "#ff8c00", name = "JavaScript" },
        ["ts"] = { icon = "", color = "#0abdc6", name = "TypeScript" },
        ["json"] = { icon = "", color = "#ff8c00", name = "JSON" },
        ["yaml"] = { icon = "", color = "#ff003c", name = "YAML" },
        ["yml"] = { icon = "", color = "#ff003c", name = "YAML" },
        ["toml"] = { icon = "", color = "#ff8c00", name = "TOML" },
        ["md"] = { icon = "", color = "#0abdc6", name = "Markdown" },
        ["sh"] = { icon = "", color = "#00ff9f", name = "Shell" },
        ["dockerfile"] = { icon = "", color = "#0abdc6", name = "Docker" },
      },
    },
  },
}
