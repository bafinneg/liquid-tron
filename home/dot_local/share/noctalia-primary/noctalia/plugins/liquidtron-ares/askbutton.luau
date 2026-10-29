-- ASK button (FEAT-lt32 C1): a static bar widget after the HERMES instrument. Owner round 6: glyph and the SUPER SPACE
-- hint only (the word ASK is gone; the hint stays until Brian removes it). A click toggles the centred chat window
-- (askchat.luau); SUPER+SPACE does the same from hyprland.lua.
--
-- Fill only (owner condition, AC1b): rest `#0d0d1a`, hover `#14142a`, open = cyan 14 % tint as a plain fill. No border,
-- outline or ring in any state, so nothing here can touch the bar's own cyan edge rows. Radius 6 matches the capsules.
-- No timers, no polling, no idle work: the widget redraws only on hover, click or when askchat tells it the window
-- opened or closed (`noctalia-primary-msg plugin liquidtron/ares:askbutton all state open|closed`, sent by askchat).

local PANEL = "liquidtron/ares:askchat"
local REST = "#0d0d1a"
local HOVER = "#14142a"
local OPEN = "primary/0.14"

local hovered = false
local isOpen = false

local draw -- forward declaration (the hover callback redraws)

local function onHover(state)
  hovered = state == true
  draw()
end

draw = function()
  local fill = REST
  if isOpen then
    fill = OPEN
  elseif hovered then
    fill = HOVER
  end
  barWidget.render(ui.row({ gap = 7, align = "center", paddingH = 10, paddingV = 4, radius = 6, fill = fill, onHover = onHover }, {
    ui.glyph({ name = "message-chatbot", size = 16, color = "primary" }),
    ui.label({ text = "SUPER SPACE", fontSize = 9.5, color = "on_surface_variant/0.55" }),
  }))
end

function onClick()
  noctalia.togglePanel(PANEL)
end

function onIpc(event, payload)
  if event == "state" then
    isOpen = payload == "open"
    draw()
  end
end

draw()
