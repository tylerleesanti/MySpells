-- MySpells minimap button: the MySpells logo on the edge of the minimap.
-- Click shows/hides the window, right-click opens the settings, drag to move it around the minimap.
-- Made with LibDBIcon (bundled in Libs), so button collectors (Leatrix Plus, MBB, ...) show its tooltip.

local ADDON, ns = ...

local ICON = "Interface\\AddOns\\MySpells\\Media\\MySpells_Icon.png"
local NAME = "MySpells"
local DBIcon

local function say(msg) print("|cffff9933MySpells|r " .. msg) end

function ns.createMinimapButton()
  if DBIcon or not LibStub then return end
  local LDB = LibStub("LibDataBroker-1.1", true)
  DBIcon = LibStub("LibDBIcon-1.0", true)
  if not (LDB and DBIcon) then DBIcon = nil return end

  -- LibDBIcon keeps the position in db.minimapPos (degrees, 0 = right, 225 = bottom left) and reads db.hide
  local db = ns.db.minimap
  if db.angle then db.minimapPos = db.angle % 360; db.angle = nil end -- from 1.9.0
  db.minimapPos = db.minimapPos or 225
  db.hide = not db.show

  local launcher = LDB:NewDataObject(NAME, {
    type = "launcher",
    text = NAME,
    icon = ICON,
    OnClick = function(_, mouseButton)
      GameTooltip:Hide()
      if mouseButton == "RightButton" then
        if ns.toggleOptions then ns.toggleOptions() end
      else
        ns.toggleWindow()
      end
    end,
    OnTooltipShow = function(tooltip)
      tooltip:AddLine("MySpells", 1, 0.82, 0)
      tooltip:AddLine("Click to toggle the MySpells window", 1, 1, 1)
      tooltip:AddLine("Right-click: open settings", 1, 1, 1)
      tooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    end,
  })
  DBIcon:Register(NAME, launcher, db)
end

-- show or hide the button (gear menu > Bars > Window, or /myspells minimap)
function ns.applyMinimapButton()
  if not DBIcon then return end
  local db = ns.db.minimap
  db.hide = not db.show
  if db.show then DBIcon:Show(NAME) else DBIcon:Hide(NAME) end
end

function ns.toggleMinimapButton()
  ns.db.minimap.show = not ns.db.minimap.show
  ns.applyMinimapButton()
  say(ns.db.minimap.show and "minimap button shown." or "minimap button hidden. Type /myspells minimap to show it again.")
end
