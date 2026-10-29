-- ── Lualine — Cyberpunk Statusline ───────────────────────────
return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  config = function()
    local p = {
      bg       = "#06060c",
      bg_alt   = "#0e0e1c",
      fg       = "#c0c0d0",
      fg_dim   = "#707080",
      cyan     = "#0abdc6",
      magenta  = "#ff003c",
      amber    = "#ff8c00",
      green    = "#00ff9f",
      red      = "#ff003c",
    }

    local cyberpunk = {
      normal = {
        a = { fg = p.bg, bg = p.cyan, gui = "bold" },
        b = { fg = p.cyan, bg = p.bg_alt },
        c = { fg = p.fg_dim, bg = p.bg },
      },
      insert = {
        a = { fg = p.bg, bg = p.green, gui = "bold" },
        b = { fg = p.green, bg = p.bg_alt },
      },
      visual = {
        a = { fg = p.bg, bg = p.magenta, gui = "bold" },
        b = { fg = p.magenta, bg = p.bg_alt },
      },
      replace = {
        a = { fg = p.bg, bg = p.red, gui = "bold" },
        b = { fg = p.red, bg = p.bg_alt },
      },
      command = {
        a = { fg = p.bg, bg = p.amber, gui = "bold" },
        b = { fg = p.amber, bg = p.bg_alt },
      },
      inactive = {
        a = { fg = p.fg_dim, bg = p.bg },
        b = { fg = p.fg_dim, bg = p.bg },
        c = { fg = p.fg_dim, bg = p.bg },
      },
    }

    require("lualine").setup({
      options = {
        theme = cyberpunk,
        component_separators = { left = "│", right = "│" },
        section_separators = { left = "", right = "" },
        globalstatus = true,
        disabled_filetypes = {
          statusline = { "alpha", "dashboard" },
        },
      },
      sections = {
        lualine_a = {
          { "mode", fmt = function(str) return "⟨ " .. str .. " ⟩" end },
        },
        lualine_b = {
          { "branch", icon = "" },
          {
            "diff",
            symbols = { added = " ", modified = " ", removed = " " },
            diff_color = {
              added = { fg = p.green },
              modified = { fg = p.amber },
              removed = { fg = p.red },
            },
          },
        },
        lualine_c = {
          {
            "filename",
            path = 1,
            symbols = { modified = " ●", readonly = " ", unnamed = "░░░" },
          },
          {
            "diagnostics",
            sources = { "nvim_diagnostic" },
            symbols = { error = " ", warn = " ", info = " ", hint = " " },
            diagnostics_color = {
              error = { fg = p.red },
              warn = { fg = p.amber },
              info = { fg = p.cyan },
              hint = { fg = p.green },
            },
          },
        },
        lualine_x = {
          {
            -- Show active LSP
            function()
              local clients = vim.lsp.get_clients({ bufnr = 0 })
              if #clients == 0 then return "  none" end
              local names = {}
              for _, client in ipairs(clients) do
                table.insert(names, client.name)
              end
              return "  " .. table.concat(names, ", ")
            end,
            color = { fg = p.cyan },
          },
        },
        lualine_y = {
          { "filetype", colored = true, icon_only = false },
          { "encoding", fmt = string.upper },
        },
        lualine_z = {
          { "location" },
          { "progress" },
        },
      },
    })
  end,
}
