-- MySpells segment menu: pick which fight the window shows.
-- A copy of Details' segment menu: past fights (oldest at the top) with their length,
-- a divider, then Current and Overall. Orange bullets, the shown segment is highlighted.

local ADDON, ns = ...

local LINE_H, MAX_LINES, MIN_W, MAX_W = 18, 20, 180, 340
local BULLET = [[Interface\QUESTFRAME\UI-Quest-BulletPoint]]
local ORANGE = { 1, 0.65, 0 }

local menu

-- Details shows lengths as mm:ss
local function timer(seconds)
  if not seconds then return "" end
  local s = math.floor(seconds)
  return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

-- everything in the menu, top to bottom
local function entries()
  local list = {}
  for _, fight in ipairs(ns.segmentList()) do
    list[#list + 1] = { value = fight.id, left = fight.name, right = timer(fight.duration) }
  end
  if #list > 0 then list[#list + 1] = { divider = true } end
  list[#list + 1] = { value = "current", left = "Current fight", right = "" }
  list[#list + 1] = { value = "overall", left = "Overall", right = "" }
  return list
end

-- right click on the segment button: step down the list, wrapping around (like Details)
function ns.nextSegment()
  local values = {}
  for _, e in ipairs(entries()) do
    if not e.divider then values[#values + 1] = e.value end
  end
  local index = 0
  for i, v in ipairs(values) do
    if v == ns.db.segment then index = i end
  end
  ns.setSegment(values[index % #values + 1])
end

local function createLine(i)
  local line = CreateFrame("Button", nil, menu)
  line:SetHeight(LINE_H)

  line.selected = line:CreateTexture(nil, "BACKGROUND")
  line.selected:SetAllPoints()
  line.selected:SetColorTexture(1, 1, 1, 0.15)

  local hl = line:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.1)

  line.icon = line:CreateTexture(nil, "ARTWORK")
  line.icon:SetSize(16, 16)
  line.icon:SetPoint("LEFT", 2, 0)
  line.icon:SetTexture(BULLET)
  line.icon:SetVertexColor(unpack(ORANGE))

  line.right = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  line.right:SetPoint("RIGHT", -4, 0)
  line.right:SetJustifyH("RIGHT")
  line.right:SetTextColor(0.7, 0.7, 0.7)

  line.left = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  line.left:SetPoint("LEFT", line.icon, "RIGHT", 2, 0)
  line.left:SetPoint("RIGHT", line.right, "LEFT", -6, 0)
  line.left:SetJustifyH("LEFT")
  line.left:SetWordWrap(false)

  line.divider = line:CreateTexture(nil, "ARTWORK")
  line.divider:SetHeight(1)
  line.divider:SetPoint("LEFT", 6, 0)
  line.divider:SetPoint("RIGHT", -6, 0)
  line.divider:SetColorTexture(0.5, 0.5, 0.5, 0.6)

  line:SetScript("OnClick", function(self)
    if self.value == nil then return end
    menu:Hide()
    ns.setSegment(self.value)
  end)

  menu.lines[i] = line
  return line
end

local function render()
  local list = menu.list
  local shown = math.min(#list, MAX_LINES)
  local widest = 0

  for i = 1, MAX_LINES do
    local line = menu.lines[i] or createLine(i)
    local e = list[i + menu.offset]
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * LINE_H)
    line:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * LINE_H)
    if e then
      local isDivider = e.divider and true or false
      line.divider:SetShown(isDivider)
      line.icon:SetShown(not isDivider)
      line.left:SetShown(not isDivider)
      line.right:SetShown(not isDivider)
      line:EnableMouse(not isDivider)
      line.value = e.value
      if not isDivider then
        line.left:SetText(e.left)
        line.right:SetText(e.right)
        local leftW = line.left.GetUnboundedStringWidth and line.left:GetUnboundedStringWidth() or line.left:GetStringWidth()
        widest = math.max(widest, leftW + line.right:GetStringWidth())
      end
      line.selected:SetShown(not isDivider and e.value == ns.db.segment)
      line:Show()
    else
      line.value = nil
      line:Hide()
    end
  end

  menu:SetWidth(math.max(MIN_W, math.min(MAX_W, widest + 40)))
  menu:SetHeight(shown * LINE_H + 8)
end

local function build()
  menu = ns.newPopupMenu("MySpellsSegmentMenu") -- Menu.lua
  menu.lines, menu.offset, menu.list = {}, 0, {}

  -- scroll when there are more fights than fit
  menu:EnableMouseWheel(true)
  menu:SetScript("OnMouseWheel", function(self, delta)
    local maxOffset = math.max(0, #self.list - MAX_LINES)
    self.offset = math.max(0, math.min(maxOffset, self.offset - delta))
    render()
  end)
end

function ns.toggleSegmentMenu(owner)
  if not menu then build() end
  if menu:IsShown() then menu:Hide() return end
  if ns.hideModeMenu then ns.hideModeMenu() end

  menu.owner = owner
  menu.list = entries()
  -- start scrolled to the bottom: newest fights, Current and Overall
  menu.offset = math.max(0, #menu.list - MAX_LINES)
  render()
  ns.placePopupMenu(menu, owner)
  menu:Show()
end

function ns.segmentMenuShown()
  return menu and menu:IsShown()
end

function ns.hideSegmentMenu()
  if menu then menu:Hide() end
end
