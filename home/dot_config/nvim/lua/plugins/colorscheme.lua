-- ── Tron Compute Colorscheme ────────────────────────────────
-- Tron Compute palette: cyan/amber on deep dark. Kanagawa as structural base.
return {
  "rebelot/kanagawa.nvim",  -- base engine, we override everything
  lazy = false,
  priority = 1000,
  config = function()
    -- We don't use kanagawa's colors — we define our own from scratch
    -- But kanagawa gives us a solid highlight structure to override

    -- ── Palette ──
    local p = {
      -- Backgrounds
      bg        = "#0a0a14",
      bg_dark   = "#06060c",
      bg_float  = "#0d0d1a",
      bg_popup  = "#0e0e1c",
      bg_visual = "#1a0a2e",
      bg_search = "#2a1a0a",
      bg_gutter = "#0c0c18",
      bg_curline= "#0e0e1c",

      -- Foregrounds
      fg        = "#c0c0d0",
      fg_dim    = "#707080",
      fg_dark   = "#505060",
      comment   = "#4a4a6a",

      -- Accents
      cyan      = "#0abdc6",
      magenta   = "#ff003c",
      amber     = "#ff8c00",
      green     = "#00ff9f",
      red       = "#ff003c",
      blue      = "#0072ff",
      purple    = "#b040d0",
      pink      = "#ff71ce",
      orange    = "#ff8c00",

      -- UI elements
      border    = "#0abdc6",
      match     = "#ff003c",
      added     = "#00ff9f",
      changed   = "#ff8c00",
      removed   = "#ff003c",

      -- Diagnostics
      error     = "#ff003c",
      warn      = "#ff8c00",
      info      = "#0abdc6",
      hint      = "#00ff9f",
    }

    -- Apply after any colorscheme loads
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function()
        local hi = function(name, opts)
          vim.api.nvim_set_hl(0, name, opts)
        end

        -- ── Editor ──
        hi("Normal",           { fg = p.fg, bg = p.bg })
        hi("NormalFloat",      { fg = p.fg, bg = p.bg_float })
        hi("NormalNC",         { fg = p.fg_dim, bg = p.bg_dark })
        hi("CursorLine",      { bg = p.bg_curline })
        hi("CursorLineNr",    { fg = p.cyan, bold = true })
        hi("LineNr",          { fg = p.fg_dark })
        hi("SignColumn",      { bg = p.bg })
        hi("VertSplit",       { fg = p.border })
        hi("WinSeparator",    { fg = p.border })
        hi("ColorColumn",     { bg = p.bg_curline })
        hi("Folded",          { fg = p.comment, bg = p.bg_dark })
        hi("FoldColumn",      { fg = p.comment })
        hi("NonText",         { fg = p.fg_dark })
        hi("EndOfBuffer",     { fg = p.bg })
        hi("Whitespace",      { fg = p.fg_dark })

        -- ── Cursor & Visual ──
        hi("Cursor",          { fg = p.bg, bg = p.cyan })
        hi("Visual",          { bg = p.bg_visual })
        hi("VisualNOS",       { bg = p.bg_visual })

        -- ── Search ──
        hi("Search",          { fg = p.bg, bg = p.amber })
        hi("IncSearch",       { fg = p.bg, bg = p.magenta })
        hi("CurSearch",       { fg = p.bg, bg = p.cyan })
        hi("Substitute",      { fg = p.bg, bg = p.red })

        -- ── Popup / Float ──
        hi("Pmenu",           { fg = p.fg, bg = p.bg_popup })
        hi("PmenuSel",        { fg = p.bg, bg = p.cyan })
        hi("PmenuSbar",       { bg = p.bg_float })
        hi("PmenuThumb",      { bg = p.cyan })
        hi("FloatBorder",     { fg = p.cyan, bg = p.bg_float })
        hi("FloatTitle",      { fg = p.amber, bg = p.bg_float, bold = true })

        -- ── Statusline ──
        hi("StatusLine",      { fg = p.fg, bg = p.bg_dark })
        hi("StatusLineNC",    { fg = p.fg_dark, bg = p.bg_dark })
        hi("WinBar",          { fg = p.fg, bg = p.bg })
        hi("WinBarNC",        { fg = p.fg_dim, bg = p.bg })

        -- ── Tab line ──
        hi("TabLine",         { fg = p.fg_dim, bg = p.bg_dark })
        hi("TabLineSel",      { fg = p.cyan, bg = p.bg, bold = true })
        hi("TabLineFill",     { bg = p.bg_dark })

        -- ── Messages ──
        hi("MsgArea",         { fg = p.fg })
        hi("ErrorMsg",        { fg = p.red, bold = true })
        hi("WarningMsg",      { fg = p.amber, bold = true })
        hi("MoreMsg",         { fg = p.cyan })
        hi("Question",        { fg = p.cyan })
        hi("Title",           { fg = p.amber, bold = true })
        hi("Directory",       { fg = p.cyan })
        hi("MatchParen",      { fg = p.magenta, bold = true, underline = true })

        -- ── Syntax ──
        hi("Comment",         { fg = p.comment, italic = true })
        hi("Constant",        { fg = p.amber })
        hi("String",          { fg = p.green })
        hi("Character",       { fg = p.green })
        hi("Number",          { fg = p.amber })
        hi("Float",           { fg = p.amber })
        hi("Boolean",         { fg = p.amber })
        hi("Identifier",      { fg = p.fg })
        hi("Function",        { fg = p.cyan, bold = true })
        hi("Statement",       { fg = p.blue })
        hi("Conditional",     { fg = p.blue })
        hi("Repeat",          { fg = p.blue })
        hi("Label",           { fg = p.amber })
        hi("Operator",        { fg = p.pink })
        hi("Keyword",         { fg = p.blue, italic = true })
        hi("Exception",       { fg = p.red })
        hi("PreProc",         { fg = p.cyan })
        hi("Include",         { fg = p.cyan })
        hi("Define",          { fg = p.blue })
        hi("Macro",           { fg = p.blue })
        hi("Type",            { fg = p.cyan })
        hi("StorageClass",    { fg = p.blue })
        hi("Structure",       { fg = p.cyan })
        hi("Typedef",         { fg = p.cyan })
        hi("Special",         { fg = p.amber })
        hi("SpecialChar",     { fg = p.pink })
        hi("Tag",             { fg = p.amber })
        hi("Delimiter",       { fg = p.fg_dim })
        hi("SpecialComment",  { fg = p.cyan, italic = true })
        hi("Debug",           { fg = p.red })
        hi("Underlined",      { fg = p.cyan, underline = true })
        hi("Error",           { fg = p.red })
        hi("Todo",            { fg = p.bg, bg = p.amber, bold = true })

        -- ── Treesitter ──
        hi("@variable",              { fg = p.fg })
        hi("@variable.builtin",      { fg = p.pink })
        hi("@variable.parameter",    { fg = p.amber, italic = true })
        hi("@variable.member",       { fg = p.fg })
        hi("@constant",              { fg = p.amber })
        hi("@constant.builtin",      { fg = p.amber, bold = true })
        hi("@module",                { fg = p.cyan })
        hi("@string",                { fg = p.green })
        hi("@string.escape",         { fg = p.pink })
        hi("@string.regex",          { fg = p.pink })
        hi("@character",             { fg = p.green })
        hi("@boolean",               { fg = p.amber, bold = true })
        hi("@number",                { fg = p.amber })
        hi("@type",                  { fg = p.cyan })
        hi("@type.builtin",          { fg = p.cyan, italic = true })
        hi("@type.qualifier",        { fg = p.blue })
        hi("@attribute",             { fg = p.amber })
        hi("@property",              { fg = p.fg })
        hi("@function",              { fg = p.cyan, bold = true })
        hi("@function.builtin",      { fg = p.cyan })
        hi("@function.macro",        { fg = p.blue })
        hi("@function.method",       { fg = p.cyan })
        hi("@constructor",           { fg = p.amber })
        hi("@keyword",               { fg = p.blue, italic = true })
        hi("@keyword.function",      { fg = p.blue })
        hi("@keyword.return",        { fg = p.amber, bold = true })
        hi("@keyword.operator",      { fg = p.pink })
        hi("@keyword.import",        { fg = p.cyan })
        hi("@operator",              { fg = p.pink })
        hi("@punctuation.bracket",   { fg = p.fg_dim })
        hi("@punctuation.delimiter", { fg = p.fg_dim })
        hi("@punctuation.special",   { fg = p.pink })
        hi("@comment",               { fg = p.comment, italic = true })
        hi("@tag",                   { fg = p.amber })
        hi("@tag.attribute",         { fg = p.cyan })
        hi("@tag.delimiter",         { fg = p.fg_dim })

        -- ── LSP Semantic Tokens ──
        hi("@lsp.type.class",        { fg = p.cyan })
        hi("@lsp.type.decorator",    { fg = p.amber })
        hi("@lsp.type.enum",         { fg = p.cyan })
        hi("@lsp.type.enumMember",   { fg = p.amber })
        hi("@lsp.type.function",     { fg = p.cyan, bold = true })
        hi("@lsp.type.interface",    { fg = p.cyan, italic = true })
        hi("@lsp.type.macro",        { fg = p.blue })
        hi("@lsp.type.method",       { fg = p.cyan })
        hi("@lsp.type.namespace",    { fg = p.cyan })
        hi("@lsp.type.parameter",    { fg = p.amber, italic = true })
        hi("@lsp.type.property",     { fg = p.fg })
        hi("@lsp.type.struct",       { fg = p.cyan })
        hi("@lsp.type.type",         { fg = p.cyan })
        hi("@lsp.type.variable",     { fg = p.fg })

        -- ── Diagnostics ──
        hi("DiagnosticError",          { fg = p.error })
        hi("DiagnosticWarn",           { fg = p.warn })
        hi("DiagnosticInfo",           { fg = p.info })
        hi("DiagnosticHint",           { fg = p.hint })
        hi("DiagnosticUnderlineError", { undercurl = true, sp = p.error })
        hi("DiagnosticUnderlineWarn",  { undercurl = true, sp = p.warn })
        hi("DiagnosticUnderlineInfo",  { undercurl = true, sp = p.info })
        hi("DiagnosticUnderlineHint",  { undercurl = true, sp = p.hint })
        hi("DiagnosticVirtualTextError", { fg = p.error, bg = "#1a0a0a" })
        hi("DiagnosticVirtualTextWarn",  { fg = p.warn, bg = "#1a140a" })
        hi("DiagnosticVirtualTextInfo",  { fg = p.info, bg = "#0a1a1a" })
        hi("DiagnosticVirtualTextHint",  { fg = p.hint, bg = "#0a1a0f" })

        -- ── Git Signs ──
        hi("GitSignsAdd",    { fg = p.added })
        hi("GitSignsChange", { fg = p.changed })
        hi("GitSignsDelete", { fg = p.removed })

        -- ── Diff ──
        hi("DiffAdd",    { bg = "#0a1a0f" })
        hi("DiffChange", { bg = "#1a1a0a" })
        hi("DiffDelete", { bg = "#1a0a0a" })
        hi("DiffText",   { bg = "#2a1a0a" })

        -- ── Indent guides ──
        hi("IndentBlanklineChar",        { fg = "#1a1a2a" })
        hi("IndentBlanklineContextChar", { fg = p.cyan })
        hi("IblIndent",                  { fg = "#1a1a2a" })
        hi("IblScope",                   { fg = p.cyan })

        -- ── Telescope ──
        hi("TelescopeNormal",        { fg = p.fg, bg = p.bg_float })
        hi("TelescopeBorder",        { fg = p.cyan, bg = p.bg_float })
        hi("TelescopeTitle",         { fg = p.amber, bold = true })
        hi("TelescopePromptNormal",  { fg = p.fg, bg = p.bg_popup })
        hi("TelescopePromptBorder",  { fg = p.magenta, bg = p.bg_popup })
        hi("TelescopePromptTitle",   { fg = p.bg, bg = p.magenta, bold = true })
        hi("TelescopePromptPrefix",  { fg = p.magenta })
        hi("TelescopeResultsNormal", { fg = p.fg, bg = p.bg_float })
        hi("TelescopeResultsBorder", { fg = p.cyan, bg = p.bg_float })
        hi("TelescopePreviewNormal", { fg = p.fg, bg = p.bg_dark })
        hi("TelescopePreviewBorder", { fg = p.cyan, bg = p.bg_dark })
        hi("TelescopePreviewTitle",  { fg = p.bg, bg = p.cyan, bold = true })
        hi("TelescopeSelection",     { fg = p.cyan, bg = p.bg_visual })
        hi("TelescopeMatching",      { fg = p.magenta, bold = true })

        -- ── Neo-tree ──
        hi("NeoTreeNormal",        { fg = p.fg, bg = p.bg_dark })
        hi("NeoTreeNormalNC",      { fg = p.fg_dim, bg = p.bg_dark })
        hi("NeoTreeRootName",      { fg = p.amber, bold = true })
        hi("NeoTreeDirectoryName", { fg = p.cyan })
        hi("NeoTreeDirectoryIcon", { fg = p.cyan })
        hi("NeoTreeFileName",      { fg = p.fg })
        hi("NeoTreeFileIcon",      { fg = p.fg_dim })
        hi("NeoTreeGitAdded",      { fg = p.added })
        hi("NeoTreeGitModified",   { fg = p.changed })
        hi("NeoTreeGitDeleted",    { fg = p.removed })
        hi("NeoTreeGitConflict",   { fg = p.red })
        hi("NeoTreeIndentMarker",  { fg = "#1a1a2a" })
        hi("NeoTreeWinSeparator",  { fg = p.bg_dark, bg = p.bg_dark })

        -- ── Which Key ──
        hi("WhichKey",          { fg = p.cyan })
        hi("WhichKeyGroup",     { fg = p.blue })
        hi("WhichKeyDesc",      { fg = p.fg })
        hi("WhichKeySeparator", { fg = p.fg_dark })
        hi("WhichKeyFloat",     { bg = p.bg_float })
        hi("WhichKeyBorder",    { fg = p.cyan })
        hi("WhichKeyValue",     { fg = p.amber })

        -- ── Notify ──
        hi("NotifyERRORBorder", { fg = p.red })
        hi("NotifyWARNBorder",  { fg = p.amber })
        hi("NotifyINFOBorder",  { fg = p.cyan })
        hi("NotifyDEBUGBorder", { fg = p.comment })
        hi("NotifyTRACEBorder", { fg = p.purple })
        hi("NotifyERRORIcon",   { fg = p.red })
        hi("NotifyWARNIcon",    { fg = p.amber })
        hi("NotifyINFOIcon",    { fg = p.cyan })
        hi("NotifyDEBUGIcon",   { fg = p.comment })
        hi("NotifyTRACEIcon",   { fg = p.purple })
        hi("NotifyERRORTitle",  { fg = p.red, bold = true })
        hi("NotifyWARNTitle",   { fg = p.amber, bold = true })
        hi("NotifyINFOTitle",   { fg = p.cyan, bold = true })

        -- ── Dashboard / Alpha ──
        hi("AlphaHeader",   { fg = p.cyan })
        hi("AlphaButtons",  { fg = p.cyan })
        hi("AlphaShortcut",  { fg = p.amber })
        hi("AlphaFooter",   { fg = p.comment, italic = true })

        -- ── Noice ──
        hi("NoiceCmdlinePopupBorder",  { fg = p.cyan })
        hi("NoiceCmdlinePopupTitle",   { fg = p.amber })
        hi("NoiceCmdlineIcon",         { fg = p.cyan })
        hi("NoiceConfirmBorder",       { fg = p.amber })
      end,
    })

    -- Set colorscheme (kanagawa as structural base, then override)
    require("kanagawa").setup({
      compile = false,
      undercurl = true,
      commentStyle = { italic = true },
      keywordStyle = { italic = true },
      statementStyle = { bold = true },
      transparent = false,
      theme = "dragon",
      background = { dark = "dragon", light = "lotus" },
    })
    vim.cmd("colorscheme kanagawa-dragon")
  end,
}
