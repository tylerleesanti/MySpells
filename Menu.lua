-- MySpells pop-up menus: the shared frame behind the fight list (Segments.lua)
-- and the mode menu (Modes.lua). Dark Details-style box, Escape closes it, and it closes
-- by itself once the mouse has been away from it (and its button) for a moment.

local ADDON, ns = ...

local CLOSE_AFTER = 1 -- seconds the mouse may be away before the menu closes

-- a new, hidden pop-up menu frame. menu.owner (set when opening) is the button it belongs to.
function ns.newPopupMenu(globalName)
  local menu = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("DIALOG")
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  menu:SetBackdrop({ bgFile = [[Interface\Buttons\WHITE8X8]], edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1 })
  menu:SetBackdropColor(0.0549, 0.0549, 0.0549, 0.95)
  menu:SetBackdropBorderColor(0, 0, 0, 1)
  menu:Hide()
  tinsert(UISpecialFrames, globalName) -- Escape closes it

  local away = 0
  menu:SetScript("OnUpdate", function(self, dt)
    if self:IsMouseOver() or (self.owner and self.owner:IsMouseOver()) then
      away = 0
    else
      away = away + dt
      if away > CLOSE_AFTER then self:Hide() end
    end
  end)
  menu:SetScript("OnShow", function() away = 0 end)
  return menu
end

-- open below the owner button, or above it when there is no room below
function ns.placePopupMenu(menu, owner)
  menu:ClearAllPoints()
  local bottom = owner:GetBottom() or 0
  if bottom - menu:GetHeight() - 4 > 0 then
    menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
  else
    menu:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 4)
  end
end

-- open at the mouse, with the mouse just inside the top-left corner
function ns.placePopupMenuAtCursor(menu)
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 10, y / scale + 10)
end
