-- AI BRIEF button (FEAT-lt32 owner round 6): a static, glyph-only bar widget between the System Map / Wallpaper capsule
-- and the Ares instrument. A click toggles the Return Brief card (brief.luau), the same panel SUPER+SHIFT+A replays.
--
-- Same fill-only grammar as the ASK button (askbutton.luau): rest `#0d0d1a`, hover `#14142a`, radius 6. No border,
-- outline or ring, so nothing touches the bar's cyan edge rows. No timers, no polling, no idle work: it redraws only on
-- hover. The tooltip names the card and its keybind.

local PANEL = "liquidtron/ares:brief"
local REST = "#0d0d1a"
local HOVER = "#14142a"

local hovered = false

local draw -- forward declaration (the hover callback redraws)

local function onHover(state)
  hovered = state == true
  draw()
end

draw = function()
  local fill = REST
  if hovered then
    fill = HOVER
  end
  barWidget.render(ui.row({ gap = 0, align = "center", paddingH = 8, paddingV = 4, radius = 6, fill = fill, onHover = onHover }, {
    ui.glyph({ name = "file-text-ai", size = 16, color = "primary" }),
  }))
end

function onClick()
  noctalia.togglePanel(PANEL)
end

barWidget.setTooltip("AI BRIEF  SUPER+SHIFT+A")
draw()
