-- MySpells mode menu: the pop-up behind the sword icon.
-- Picks what the window shows: Damage Done, Healing Done or Damage Prevented (shields).
-- Same look as the segment menu; each line has Details' attribute icon for that mode.

local ADDON, ns = ...

local LINE_H, ICON = 20, 18
local menu

local function render()
  local widest = 0
  for i, m in ipairs(ns.MODES) do
    local line = menu.lines[i]
    if not line then
      line = CreateFrame("Button", nil, menu)
      line:SetHeight(LINE_H)
      line:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * LINE_H)
      line:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * LINE_H)

      line.selected = line:CreateTexture(nil, "BACKGROUND")
      line.selected:SetAllPoints()
      line.selected:SetColorTexture(1, 1, 1, 0.15)
      local hl = line:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 1, 1, 0.1)

      line.icon = line:CreateTexture(nil, "ARTWORK")
      line.icon:SetSize(ICON, ICON)
      line.icon:SetPoint("LEFT", 2, 0)

      line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      line.text:SetPoint("LEFT", line.icon, "RIGHT", 4, 0)
      line.text:SetJustifyH("LEFT")

      line:SetScript("OnClick", function(self)
        menu:Hide()
        ns.setMode(self.key)
      end)
      menu.lines[i] = line
    end

    line.key = m.key
    -- Details' attribute icon when Details is installed, a game icon otherwise
    if ns.hasDetails() and line.icon:SetTexture(m.icon) ~= false then
      line.icon:SetTexCoord(unpack(m.coords))
    else
      line.icon:SetTexture(m.fallbackIcon)
      line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    line.text:SetText(m.label)
    line.selected:SetShown(m.key == ns.db.mode)
    widest = math.max(widest, line.text:GetStringWidth())
  end
  menu:SetWidth(math.max(150, widest + ICON + 24))
  menu:SetHeight(#ns.MODES * LINE_H + 8)
end

local function build()
  menu = ns.newPopupMenu("MySpellsModeMenu") -- Menu.lua
  menu.lines = {}
end

function ns.toggleModeMenu(owner)
  if not menu then build() end
  if menu:IsShown() then menu:Hide() return end
  if ns.hideSegmentMenu then ns.hideSegmentMenu() end

  menu.owner = owner
  render()
  ns.placePopupMenu(menu, owner)
  menu:Show()
end

-- right-click on the window (like Details): the same menu, opened at the mouse
function ns.openModeMenuAtCursor()
  if not menu then build() end
  if menu:IsShown() then menu:Hide() return end
  if ns.hideSegmentMenu then ns.hideSegmentMenu() end

  menu.owner = nil
  render()
  ns.placePopupMenuAtCursor(menu)
  menu:Show()
end

function ns.modeMenuShown()
  return menu and menu:IsShown()
end

function ns.hideModeMenu()
  if menu then menu:Hide() end
end
