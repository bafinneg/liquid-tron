-- REPO GRID button (FEAT-lt36 owner round 1): a glyph-only bar widget on the centre bar, right of the System Map /
-- Wallpaper capsule. A click toggles the Repo Grid dropdown (grid.luau) attached under this bar.
--
-- SUPER+C reaches the same toggle through `repo-grid`, which sends `plugin liquidtron/repogrid:button all toggle`.
-- Only the centre bar carries this widget, so the panel always opens on the PG42UQ (the host anchors a widget's
-- panel to that widget's own bar), whichever monitor has focus.
--
-- Same fill-only grammar as the ASK and AI BRIEF buttons: rest `#0d0d1a`, hover `#14142a`, open = cyan 14 % tint.
-- No border or ring, so nothing touches the bar's cyan edge rows. No timers and no polling: it redraws only on
-- hover, click, or when grid.luau reports open / closed.

local PANEL = "liquidtron/repogrid:grid"
local REST = "#0d0d1a"
local HOVER = "#14142a"
local OPEN = "primary/0.14"

local hovered = false
local isOpen = false

local draw -- forward declaration (the hover callback redraws)

local function onHover(state)
  hovered = state == true or state == "true"
  draw()
end

draw = function()
  local fill = REST
  if isOpen then
    fill = OPEN
  elseif hovered then
    fill = HOVER
  end
  barWidget.render(ui.row({ gap = 0, align = "center", paddingH = 8, paddingV = 4, radius = 6, fill = fill, onHover = onHover }, {
    ui.glyph({ name = "git-fork", size = 16, color = "primary" }),
  }))
end

function onClick()
  noctalia.togglePanel(PANEL)
end

function onIpc(event, payload)
  if event == "toggle" then
    noctalia.togglePanel(PANEL)
  elseif event == "state" then
    isOpen = payload == "open"
    draw()
  end
end

barWidget.setTooltip("REPO GRID  SUPER+C")
draw()
