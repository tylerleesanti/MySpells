-- MySpells minimap button: the MySpells logo on the edge of the minimap.
-- Left-click shows/hides the window, right-click opens the settings, drag to move it around the minimap.
-- Same layout as the common minimap buttons (LibDBIcon style), but with no library needed.

local ADDON, ns = ...

local ICON = "Interface\\AddOns\\MySpells\\Media\\MySpells_Icon.png"
local button

local function say(msg) print("|cffff9933MySpells|r " .. msg) end

-- place the button on the minimap's edge at the saved angle (degrees, 0 = right, 90 = top)
local function updatePosition()
  local angle = math.rad(ns.db.minimap.angle or 225)
  local radius = Minimap:GetWidth() / 2 + 5
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- while dragging, follow the mouse around the minimap
local function followCursor()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  cx, cy = cx / scale, cy / scale
  ns.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
  updatePosition()
end

local function showTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("MySpells", 1, 0.82, 0)
  GameTooltip:AddLine("Click to toggle the MySpells window", 1, 1, 1)
  GameTooltip:AddLine("Right-click: open settings", 1, 1, 1)
  GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

function ns.createMinimapButton()
  if button or not Minimap then return end
  button = CreateFrame("Button", "MySpellsMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  -- round dark background, the logo, and the standard gold ring
  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 6, -5)
  if icon:SetTexture(ICON) == false then
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09") -- if the logo file is missing
  end
  button.icon = icon

  local ring = button:CreateTexture(nil, "OVERLAY")
  ring:SetSize(53, 53)
  ring:SetPoint("TOPLEFT")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button:SetScript("OnClick", function(_, mouseButton)
    GameTooltip:Hide()
    if mouseButton == "RightButton" then
      if ns.toggleOptions then ns.toggleOptions() end
    else
      ns.toggleWindow()
    end
  end)
  -- the logo nudges down a pixel while pressed
  button:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 7, -6) end)
  button:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 6, -5) end)
  button:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", followCursor)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    icon:SetPoint("TOPLEFT", 6, -5)
  end)
  button:SetScript("OnEnter", showTooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  updatePosition()
  ns.applyMinimapButton()
end

-- show or hide the button (gear menu > Bars > Window, or /myspells minimap)
function ns.applyMinimapButton()
  if button then button:SetShown(ns.db.minimap.show) end
end

function ns.toggleMinimapButton()
  ns.db.minimap.show = not ns.db.minimap.show
  ns.applyMinimapButton()
  say(ns.db.minimap.show and "minimap button shown." or "minimap button hidden. Type /myspells minimap to show it again.")
end
