-- MySpells: your damage, healing and damage prevented per spell, in a window styled like Details.
-- WoW Forever blocks the combat log, so this reads the game's built-in damage meter
-- (C_DamageMeter), the same source Details uses on this client.
-- During combat the game may hide ("secret") some numbers from addons. Secret values can
-- still be shown on screen, but not compared or added up, so every calculation checks first.
-- Other files: Options.lua (gear menu), Report.lua (report window),
-- Segments.lua (fight list), Modes.lua (mode menu).

local ADDON, ns = ...

-- sizes, matching Details' default "Minimalistic" skin
local TITLE_H, PAD = 20, 1
local MIN_ROWS, MAX_ROWS = 2, 40
local MIN_W, MAX_W = 150, 600

-- defaults: the author's own in-game setup (taken from their saved settings)
local DEFAULTS = {
  shown = true,
  locked = false,
  segment = "current", -- "current", "overall", or a past fight's session id (segment menu)
  mode = "damage", -- "damage", "healing" or "absorbs" (mode menu)
  width = 224,
  height = 132,
  point = { "BOTTOM", "UIParent", "BOTTOM", -463, 0 },
  -- bar layout (the gear menu, Bars tab)
  bars = {
    height = 14,
    spacing = 1,
  },
  -- minimap button (Minimap.lua, LibDBIcon): position in degrees around the minimap (225 = bottom left)
  minimap = {
    show = true,
    minimapPos = 225,
  },
  -- report window (Report.lua); falls back to Raid/Party/Say when Guild isn't available
  report = {
    where = "GUILD",
    lines = 5,
    toWho = "",
    reverse = false,
  },
  -- text options (the gear menu); modeled on Details' "Bars: Text" options
  text = {
    font = "Accidental Presidency",
    size = 12,
    outline = "OUTLINE", -- NONE, OUTLINE, THICKOUTLINE
    shadow = true,
    color = { 1, 1, 1 },
    classColor = false,
    showNumber = false, -- "1. Spell name"
    showTotal = true,
    showPerSecond = false,
    showPercent = true,
    bracket = "(", -- NONE ( [ { <
    separator = "-", -- between per second and percent
    psDecimals = 2, -- decimal places for per second values under 1,000
    titleFont = "Accidental Presidency",
    titleSize = 12,
    titleOutline = "OUTLINE",
    titleShadow = true,
    titleColor = { 1, 1, 1 },
    titleClassColor = false,
    titleShowTotal = true, -- show the total amount in the title bar
    titleBgColor = { 0.047, 0.047, 0.051, 0.957 }, -- r, g, b, opacity
    windowBgColor = { 0.243, 0.235, 0.259, 0.456 }, -- window body: r, g, b, opacity
    rightClickModes = true, -- right-click the window to open the mode menu (like Details)
    estimateReductions = true, -- Damage Prevented: estimated rows for passive reductions (Reductions.lua)
    titleHeight = 17, -- title bar thickness in pixels
    titleIconSize = 14, -- segment, report, gear icons and the close "x"
    titleIconSpacing = 0, -- pixels between the title bar icons
    titleIconsHover = true, -- icons and resize corner only show while the window is hovered
  },
}
ns.DEFAULTS = DEFAULTS

-- Details' own textures (used when Details is installed)
local DETAILS = "Interface\\AddOns\\Details\\"
local STYLE = {
  bar = DETAILS .. "images\\bar_textures\\bar_best.png",
  barBg = DETAILS .. "images\\bar4_reverse",
  body = DETAILS .. "images\\background",
  barBgColor = { 0, 0, 0, 0.15 },
}
local FALLBACK_BAR = "Interface\\TargetingFrame\\UI-StatusBar"

-- what the window can show; each is one of the game's damage meter types.
-- Healing Done counts effective healing only (no overhealing). Absorbs is damage your shields prevented.
-- Both count your spells on anyone, yourself included. Icons are Details' attribute icons.
local MODES = {
  { key = "damage", label = "Damage Done", noun = "damage", perSecond = "DPS",
    meter = "DamageDone", meterFallback = 0,
    icon = DETAILS .. "images\\atributos_icones_damage", coords = { 0, 0.125, 0, 1 },
    fallbackIcon = "Interface\\Icons\\INV_Sword_04" },
  { key = "healing", label = "Healing Done", noun = "healing", perSecond = "HPS",
    meter = "HealingDone", meterFallback = 2,
    icon = DETAILS .. "images\\atributos_icones_heal", coords = { 0, 0.125, 0, 1 },
    fallbackIcon = "Interface\\Icons\\Spell_Holy_FlashHeal" },
  { key = "absorbs", label = "Damage Prevented", noun = "damage prevented", perSecond = "Per second",
    meter = "Absorbs", meterFallback = 4,
    icon = DETAILS .. "images\\atributos_icones_heal", coords = { 0.625, 0.75, 0, 1 },
    fallbackIcon = "Interface\\Icons\\Spell_Holy_PowerWordShield" },
}
ns.MODES = MODES

local BRACKETS = { ["("] = ")", ["["] = "]", ["{"] = "}", ["<"] = ">" }

local db
local frame, title, titleBar, titleBg, bodyBg, emptyText, grip
local iconHolder -- holds the title bar icons so they fade together
local appIcon -- MySpells' icon (the spellbook) on the left end of the title bar
local APP_ICON = "Interface\\Icons\\INV_Misc_Book_09" -- the game's spellbook icon; also in MySpells.toc
local titleTotal -- the total, shown on the right end of the title bar while the icons are hidden
local titleFull = false -- true while the icons are hidden and the title can use the whole bar
local titleModeText, titleTotalText = "", nil -- what the title shows (set by refresh)
local interacting = false -- true while the window is being moved or resized
local dirty = false -- game data changed; the window redraws on its next tick (see OnUpdate)
local REDRAW_EVERY = 0.25 -- at most four redraws a second from game updates
local rows = {}
local hasDetails = false

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local function isSecret(v)
  return issecretvalue and issecretvalue(v) or false
end

-- type() is safe on secret values; == and ~= may not be
local function isNil(v)
  return type(v) == "nil"
end

local function canUse(v)
  return not isSecret(v) and not isNil(v)
end

-- run fn, ignore errors (used wherever a secret value might be involved)
local function try(fn, ...)
  return pcall(fn, ...)
end

local function shortNumber(v)
  if isNil(v) then return "0" end
  if AbbreviateNumbers then
    local ok, s = pcall(AbbreviateNumbers, v)
    if ok and not isNil(s) then return s end
  end
  if isSecret(v) then return "?" end
  if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
  if v >= 1e4 then return string.format("%.1fK", v / 1e3) end
  return tostring(math.floor(v + 0.5))
end

-- per second values: under 1,000 rounded to N decimals, above that 1.2K / 3.45M / 1.23B
local psConfigs = {}
local function psConfig(decimals)
  if not CreateAbbreviateConfig then return nil end
  if psConfigs[decimals] == nil then
    local ok, cfg = pcall(CreateAbbreviateConfig, {
      { breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e7, fractionDivisor = 100, abbreviationIsGlobal = false },
      { breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e4, fractionDivisor = 100, abbreviationIsGlobal = false },
      { breakpoint = 1e3, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10, abbreviationIsGlobal = false },
      { breakpoint = 0.000001, abbreviation = "", significandDivisor = 10 ^ -decimals, fractionDivisor = 10 ^ decimals, abbreviationIsGlobal = false },
    })
    psConfigs[decimals] = ok and cfg and { config = cfg } or false
  end
  return psConfigs[decimals] or nil
end

local function perSecondText(v)
  if isNil(v) then return "0" end
  local d = math.max(0, math.min(3, math.floor(db.text.psDecimals or 2)))
  if canUse(v) then
    if v >= 1e9 then return string.format("%.2fB", v / 1e9) end
    if v >= 1e6 then return string.format("%.2fM", v / 1e6) end
    if v >= 1e3 then return string.format("%.1fK", v / 1e3) end
    return string.format("%." .. d .. "f", v)
  end
  -- hidden (secret) value during combat: let the game format it with the same rules
  local cfg = psConfig(d)
  if cfg and AbbreviateNumbers then
    local ok, s = pcall(AbbreviateNumbers, v, cfg)
    if ok and not isNil(s) then return s end
  end
  return shortNumber(v)
end

-- for hidden (secret) totals: the same trick Details uses, a curve from 0..total to 0..100
-- turns secret numbers into a secret percent. Built once per redraw and shared by all bars.
local function percentCurve(total)
  if canUse(total) or isNil(total) or not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
  local ok, curve = pcall(function()
    local c = C_CurveUtil.CreateCurve()
    c:AddPoint(0, 0)
    c:AddPoint(total, 100)
    return c
  end)
  return ok and curve or nil
end

-- percent of total as text, or nil when the game hides the numbers
-- curve: from percentCurve(total), used only when the numbers are hidden
local function percentText(amount, total, curve)
  if canUse(amount) and canUse(total) then
    if total > 0 then return string.format("%.1f%%", amount / total * 100) end
    return nil
  end
  if curve then
    local ok, text = pcall(function() return string.format("%.1f%%", curve:Evaluate(amount)) end)
    if ok then return text end
  end
  return nil
end

-- spell names and icons never change, so each is looked up once
local spellCache = {}
local function spellNameAndIcon(spellID)
  local cacheable = not isSecret(spellID) and not isNil(spellID)
  if cacheable and spellCache[spellID] then
    return spellCache[spellID][1], spellCache[spellID][2]
  end
  local ok, name, icon = pcall(function()
    local info = C_Spell and C_Spell.GetSpellInfo(spellID)
    if info then return info.name, info.iconID end
    if GetSpellInfo then
      local n, _, i = GetSpellInfo(spellID)
      return n, i
    end
  end)
  if not ok or isNil(name) then return "Unknown", 136243 end
  if isNil(icon) then icon = 136243 end
  -- only remember readable results (a hidden name may become readable later)
  if cacheable and not isSecret(name) and not isSecret(icon) then
    spellCache[spellID] = { name, icon }
  end
  return name, icon
end

local function getEnum(group, key, fallback)
  return (Enum and Enum[group] and Enum[group][key]) or fallback
end

local function detailsInstalled()
  local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
  if not getInfo then return false end
  local ok, name, _, _, _, reason = pcall(getInfo, "Details")
  return ok and name ~= nil and reason ~= "MISSING"
end

-- bar height and the gap between bars come from the settings
local function rowH() return db.bars.height end
local function rowGap() return db.bars.spacing end
local function rowStep() return db.bars.height + db.bars.spacing end
-- title bar height comes from the settings too (Title Bar tab)
local function titleH() return db.text.titleHeight or TITLE_H end

local function classColor()
  local _, class = UnitClass("player")
  local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class]
  if c then return c.r, c.g, c.b end
  return 0.85, 0.55, 0.15
end

---------------------------------------------------------------------------
-- fonts: the game's fonts, Details' fonts, and anything in LibSharedMedia
---------------------------------------------------------------------------

local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function builtinFonts()
  local list = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    ["Skurri"] = "Fonts\\SKURRI.TTF",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
  }
  if hasDetails then
    local f = DETAILS .. "fonts\\"
    list["Accidental Presidency"] = f .. "Accidental Presidency.ttf"
    list["Expressway"] = f .. "Expressway.TTF"
    list["Oswald"] = f .. "Oswald-Regular.ttf"
    list["Nueva Std Cond"] = f .. "Nueva Std Cond.ttf"
    list["Forced Square"] = f .. "FORCED SQUARE.ttf"
  end
  return list
end

local function sharedMedia()
  return LibStub and LibStub("LibSharedMedia-3.0", true)
end

function ns.fontPath(name)
  local lsm = sharedMedia()
  if lsm and name then
    local path = lsm:Fetch("font", name, true)
    if path then return path end
  end
  return builtinFonts()[name] or DEFAULT_FONT
end

-- sorted list of font names for the menu
function ns.fontList()
  local seen, list = {}, {}
  local function add(name)
    if name and not seen[name] then seen[name] = true list[#list + 1] = name end
  end
  for name in pairs(builtinFonts()) do add(name) end
  local lsm = sharedMedia()
  if lsm then
    for _, name in ipairs(lsm:List("font") or {}) do add(name) end
  end
  table.sort(list, function(a, b) return a:lower() < b:lower() end)
  return list
end

local function applyFont(fs, fontName, size, outline, shadow)
  local flags = (outline == "OUTLINE" or outline == "THICKOUTLINE") and outline or ""
  -- SetFont returns false when the font file can't be loaded
  if fs:SetFont(ns.fontPath(fontName), size, flags) == false then
    fs:SetFont(DEFAULT_FONT, size, flags)
  end
  fs:SetShadowColor(0, 0, 0, shadow and 1 or 0)
  fs:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
end

local function barTextColor()
  local t = db.text
  if t.classColor then return classColor() end
  return t.color[1], t.color[2], t.color[3]
end

-- right side text, like Details: total (per second, percent)
local function rightText(spell, pct)
  local t = db.text
  local parts = {}
  if t.showPerSecond and not isNil(spell.amountPerSecond) then
    parts[#parts + 1] = perSecondText(spell.amountPerSecond)
  end
  if t.showPercent and not isNil(pct) then parts[#parts + 1] = pct end

  local extra = ""
  if #parts > 0 then
    local sep = t.separator == " " and " " or (t.separator .. " ")
    local inner = parts[1]
    if parts[2] then inner = inner .. sep .. parts[2] end
    local close = BRACKETS[t.bracket]
    if close then inner = t.bracket .. inner .. close end
    extra = "|cffbbbbbb" .. inner .. "|r"
  end

  if t.showTotal then
    local total = shortNumber(spell.totalAmount)
    if extra == "" then return total end
    return total .. "  " .. extra
  end
  return extra
end

---------------------------------------------------------------------------
-- data
---------------------------------------------------------------------------

function ns.currentMode()
  for _, m in ipairs(MODES) do
    if m.key == db.mode then return m end
  end
  return MODES[1]
end

function ns.setMode(key)
  db.mode = key
  ns.refresh()
end

function ns.hasDetails() return hasDetails end

-- your Title Bar background color (r, g, b, a), so the pop-up windows match the main window
function ns.titleBarColor()
  local c = db.text.titleBgColor
  return c[1], c[2], c[3], c[4] or 1
end

-- your entry in the game's damage meter for one meter type, for the fight the window shows
local function getSource(meterType)
  if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then
    return nil, "The game's damage meter is not available."
  end
  local guid = UnitGUID("player")
  local ok, source
  local seg = db.segment
  if type(seg) == "number" then
    -- a past fight picked in the segment menu
    if not C_DamageMeter.GetCombatSessionSourceFromID then
      return nil, "Past fights are not available."
    end
    ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromID, seg, meterType, guid)
  else
    local sessionType = seg == "overall" and getEnum("DamageMeterSessionType", "Overall", 0)
                                         or getEnum("DamageMeterSessionType", "Current", 1)
    ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, guid)
  end
  if not ok then return nil end
  return source
end

local function getMySpells()
  local mode = ns.currentMode()
  local source, err = getSource(getEnum("DamageMeterType", mode.meter, mode.meterFallback))
  if err then return nil, err end

  local list = {}
  for i, spell in ipairs(source and source.combatSpells or {}) do
    list[i] = spell
  end
  local total, maxAmount = source and source.totalAmount, source and source.maxAmount

  -- Damage Prevented: add the estimated passive reductions (Reductions.lua), once the numbers are readable
  if mode.key == "absorbs" and db.text.estimateReductions and ns.estimateReductions then
    local readable = isNil(total) or canUse(total)
    for _, s in ipairs(list) do
      if not canUse(s.totalAmount) then readable = false break end
    end
    local extra = readable and ns.estimateReductions(getSource(getEnum("DamageMeterType", "DamageTaken", 7)))
    if extra then
      total = isNil(total) and 0 or total
      maxAmount = canUse(maxAmount) and maxAmount or 0
      for _, row in ipairs(extra) do
        list[#list + 1] = row
        total = total + row.totalAmount
        if row.totalAmount > maxAmount then maxAmount = row.totalAmount end
      end
    end
  end
  if not source and #list == 0 then return nil end

  -- biggest first, when the numbers are readable (otherwise keep the game's order)
  local sortable = true
  for _, s in ipairs(list) do
    if not canUse(s.totalAmount) then sortable = false break end
  end
  if sortable then
    table.sort(list, function(a, b) return a.totalAmount > b.totalAmount end)
  end

  return list, nil, total, maxAmount
end

---------------------------------------------------------------------------
-- segments: current fight, overall, and past fights kept by the game
---------------------------------------------------------------------------

local function fightNumber(id)
  if DAMAGE_METER_COMBAT_NUMBER then
    local ok, s = pcall(string.format, DAMAGE_METER_COMBAT_NUMBER, id)
    if ok then return s end
  end
  return "Fight #" .. id
end

-- past fights, oldest first: { id, name, duration (seconds or nil) }
function ns.segmentList()
  local out = {}
  if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return out end
  local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
  if not ok or type(sessions) ~= "table" then return out end
  for _, s in ipairs(sessions) do
    local id = s.sessionID
    if canUse(id) and type(id) == "number" then
      local name = s.name
      if not canUse(name) or name == "" then name = fightNumber(id) end
      local duration = s.durationSeconds
      out[#out + 1] = { id = id, name = name, duration = canUse(duration) and duration or nil }
    end
  end
  return out
end

-- a past fight can disappear (reset, too many fights); fall back to the current one.
-- fights: the fight list, if the caller already has it
local function validateSegment(fights)
  if type(db.segment) ~= "number" then return end
  for _, s in ipairs(fights or ns.segmentList()) do
    if s.id == db.segment then return end
  end
  db.segment = "current"
end

function ns.segmentLabel(fights)
  if db.segment == "overall" then return "Overall" end
  if db.segment == "current" then return "Current fight" end
  for _, s in ipairs(fights or ns.segmentList()) do
    if s.id == db.segment then return s.name end
  end
  return fightNumber(db.segment)
end

function ns.setSegment(value)
  db.segment = value
  ns.refresh()
end

-- shared with Report.lua
ns.getMySpells = getMySpells
ns.isSecret = isSecret
function ns.spellName(spellID)
  local name = spellNameAndIcon(spellID)
  return name
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------

local function savePosition()
  local p, _, rp, x, y = frame:GetPoint()
  db.point = { p, "UIParent", rp, x, y }
end

-- how many rows fit in the current window height
local function visibleRows()
  local n = math.floor((frame:GetHeight() - titleH() - PAD + rowGap()) / rowStep())
  return math.max(1, math.min(MAX_ROWS, n))
end

-- right-click anywhere on the window opens the mode menu at the mouse (like Details)
local function onRightClick(_, button)
  if button == "RightButton" and db.text.rightClickModes and ns.openModeMenuAtCursor then
    GameTooltip:Hide()
    ns.openModeMenuAtCursor()
  end
end

local function startMoving()
  if not db.locked then
    interacting = true
    frame:StartMoving()
  end
end

local function stopMoving()
  interacting = false
  frame:StopMovingOrSizing()
  savePosition()
end

local function rowTooltip(row)
  local spell = row.spell
  if not spell then return end
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  if not try(GameTooltip.SetSpellByID, GameTooltip, spell.spellID) then
    try(function() GameTooltip:AddLine(row.name:GetText()) end)
  end
  GameTooltip:AddLine(" ")
  local mode = ns.currentMode()
  try(GameTooltip.AddDoubleLine, GameTooltip, mode.label, shortNumber(spell.totalAmount), 1, 0.82, 0, 1, 1, 1)
  if not isNil(spell.amountPerSecond) then
    try(GameTooltip.AddDoubleLine, GameTooltip, mode.perSecond, perSecondText(spell.amountPerSecond), 1, 0.82, 0, 1, 1, 1)
  end
  if not isNil(row.pct) then
    try(GameTooltip.AddDoubleLine, GameTooltip, "Share", row.pct, 1, 0.82, 0, 1, 1, 1)
  end
  if spell.note then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(spell.note, 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("Worked out from the damage you took this fight, assuming it was up the whole time.", 0.5, 0.5, 0.5, true)
  end
  GameTooltip:Show()
end

local function styleRowText(row)
  local t = db.text
  applyFont(row.name, t.font, t.size, t.outline, t.shadow)
  applyFont(row.value, t.font, t.size, t.outline, t.shadow)
  local r, g, b = barTextColor()
  row.name:SetTextColor(r, g, b)
  row.value:SetTextColor(r, g, b)
end

-- one row: [icon][ bar with name on the left and amount on the right ]
-- place a row for the current bar height and spacing
local function placeRow(row, i)
  local y = -(titleH() + (i - 1) * rowStep())
  row:SetHeight(rowH())
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
  row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y)
  row.icon:SetSize(rowH(), rowH())
end

local function createRow(i)
  local row = CreateFrame("Frame", nil, frame)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
  placeRow(row, i)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  -- the bar starts after the icon, like Details
  local bar = CreateFrame("StatusBar", nil, row)
  bar:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  bar:SetStatusBarTexture(hasDetails and STYLE.bar or FALLBACK_BAR)
  bar:SetStatusBarColor(classColor())
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  row.bar = bar

  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  if hasDetails then
    bg:SetTexture(STYLE.barBg)
    bg:SetVertexColor(unpack(STYLE.barBgColor))
  else
    bg:SetColorTexture(unpack(STYLE.barBgColor))
  end

  row.value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.value:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
  row.value:SetJustifyH("RIGHT")

  row.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.name:SetPoint("LEFT", bar, "LEFT", 3, 0)
  row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  styleRowText(row)

  row:EnableMouse(true)
  row:SetScript("OnEnter", rowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:RegisterForDrag("LeftButton")
  row:SetScript("OnDragStart", startMoving)
  row:SetScript("OnDragStop", stopMoving)
  row:SetScript("OnMouseUp", onRightClick)

  row:Hide()
  rows[i] = row
  return row
end

local function ensureRows(n)
  for i = #rows + 1, n do createRow(i) end
end

-- icons hidden: the total sits on the right end of the bar; icons showing: right after the title
function ns.updateTitleText()
  if not title then return end
  local totalText = titleTotalText
  if not db.text.titleShowTotal then totalText = nil end -- Title Bar tab > Show Total
  if titleFull and titleTotal and not isNil(totalText) then
    title:SetText(titleModeText)
    if not try(titleTotal.SetText, titleTotal, totalText) then titleTotal:SetText("") end
    titleTotal:Show()
  else
    if titleTotal then
      titleTotal:SetText("") -- a hidden text still takes up its width in the layout
      titleTotal:Hide()
    end
    local ok = not isNil(totalText) and try(function() title:SetText(titleModeText .. "  " .. totalText) end)
    if not ok then title:SetText(titleModeText) end
  end
end

local function refresh()
  dirty = false
  if not frame or not frame:IsShown() then return end

  -- the fight list is only needed when a past fight is picked; fetch it once
  local fights = type(db.segment) == "number" and ns.segmentList() or nil
  validateSegment(fights)
  local list, err, total, maxAmount = getMySpells()
  local current = ns.currentMode()
  titleModeText = current.label .. " |cffaaaaaa(" .. ns.segmentLabel(fights) .. ")|r"
  titleTotalText = not isNil(total) and shortNumber(total) or nil
  ns.updateTitleText()

  list = list or {}
  emptyText:SetText(err or ("No " .. current.noun .. " yet."))
  emptyText:SetShown(#list == 0)

  -- bar scale: the top spell fills the bar
  local barMax = maxAmount
  if isNil(barMax) or (canUse(barMax) and barMax <= 0) then barMax = 1 end

  local shown = visibleRows()
  ensureRows(shown)
  local curve = percentCurve(total) -- one per redraw, only needed while numbers are hidden

  for i = 1, #rows do
    local row = rows[i]
    local spell = i <= shown and list[i]
    if spell then
      row.spell = spell
      local name, icon = spellNameAndIcon(spell.spellID)
      local pet = spell.creatureName
      if canUse(pet) and pet ~= "" then
        try(function() name = name .. " |cffccbbbb(" .. pet .. ")|r" end)
      end
      if spell.estimated then name = name .. " |cff999999(est.)|r" end
      if db.text.showNumber then
        try(function() name = i .. ". " .. name end)
      end
      if not try(row.icon.SetTexture, row.icon, icon) then row.icon:SetTexture(136243) end
      if not try(row.name.SetText, row.name, name) then row.name:SetText("Unknown") end

      row.pct = percentText(spell.totalAmount, total, curve)
      local pct = row.pct
      if not try(function() row.value:SetText(rightText(spell, pct)) end) then
        if not try(row.value.SetText, row.value, shortNumber(spell.totalAmount)) then row.value:SetText("?") end
      end

      local bar = row.bar
      if not try(bar.SetMinMaxValues, bar, 0, barMax) then bar:SetMinMaxValues(0, 1) end
      if not try(bar.SetValue, bar, spell.totalAmount) then bar:SetValue(0) end
      row:Show()
    else
      row.spell, row.pct = nil, nil
      row:Hide()
    end
  end
end
ns.refresh = refresh

-- re-style every text after a change in the gear menu
function ns.applyText()
  if not frame then return end
  local t = db.text
  for _, row in ipairs(rows) do styleRowText(row) end
  local wc = t.windowBgColor
  if bodyBg.usesTexture then
    bodyBg:SetVertexColor(wc[1], wc[2], wc[3], wc[4] or 1)
  else
    bodyBg:SetColorTexture(wc[1], wc[2], wc[3], wc[4] or 1)
  end

  local bg = t.titleBgColor
  for _, piece in ipairs(titleBg) do
    local s = piece.shade
    piece:SetColorTexture(math.min(1, bg[1] * s), math.min(1, bg[2] * s), math.min(1, bg[3] * s), bg[4] or 1)
  end
  for _, fs in ipairs({ title, titleTotal }) do
    applyFont(fs, t.titleFont, t.titleSize, t.titleOutline, t.titleShadow)
    if t.titleClassColor then
      fs:SetTextColor(classColor())
    else
      fs:SetTextColor(t.titleColor[1], t.titleColor[2], t.titleColor[3])
    end
  end
  applyFont(emptyText, t.font, math.max(8, t.size - 2), t.outline, t.shadow)
  if ns.applyIconSize then ns.applyIconSize() end

  -- title bar height: the bar, the body below it, and the bars all move with it
  titleBar:SetHeight(titleH())
  appIcon:SetSize(titleH() - 3, titleH() - 3) -- the app icon fills the bar with a little room
  bodyBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -titleH())
  emptyText:SetPoint("TOP", frame, "TOP", 0, -(titleH() + 6))
  if ns.applyBars then
    ns.applyBars() -- re-places the bars and refreshes
  else
    refresh()
  end
end

local function setResizeLimits()
  local minH = titleH() + MIN_ROWS * rowStep() + PAD
  local maxH = titleH() + MAX_ROWS * rowStep() + PAD
  if frame.SetResizeBounds then
    frame:SetResizeBounds(MIN_W, minH, MAX_W, maxH)
  else
    if frame.SetMinResize then frame:SetMinResize(MIN_W, minH) end
    if frame.SetMaxResize then frame:SetMaxResize(MAX_W, maxH) end
  end
end

-- re-place every bar after a height or spacing change in the gear menu
function ns.applyBars()
  if not frame then return end
  setResizeLimits()
  -- keep the window inside the new limits
  local minH = titleH() + MIN_ROWS * rowStep() + PAD
  local maxH = titleH() + MAX_ROWS * rowStep() + PAD
  local h = math.max(minH, math.min(maxH, frame:GetHeight()))
  if math.abs(h - frame:GetHeight()) > 0.5 then
    frame:SetHeight(h)
    db.height = math.floor(h + 0.5)
  end
  for i, row in ipairs(rows) do placeRow(row, i) end
  refresh()
end

local function updateGrip()
  if grip then grip:SetShown(not db.locked) end
end

-- title bar icons (segment, report, gear) and the close "x"
local titleIcons, closeButton = {}, nil
local ICON_REST_ALPHA = 0.75 -- all icons are white; slightly faded until hovered

-- small icon button for the title bar
local function titleButton(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b:SetAlpha(ICON_REST_ALPHA)
  b:SetScript("OnLeave", function(self)
    self:SetAlpha(ICON_REST_ALPHA)
    GameTooltip:Hide()
  end)
  return b
end

-- grayscale + white so every icon matches, whatever color its texture has
local function whiteIcon(tex)
  tex:SetDesaturated(true)
  tex:SetVertexColor(1, 1, 1)
end

-- size and space the title bar icons (Title Bar tab > Icon Size / Icon Spacing)
local function applyIconSize()
  local s = math.min(db.text.titleIconSize, titleH()) -- never taller than the title bar
  local gap = db.text.titleIconSpacing or 2
  -- titleIcons runs left to right: segment, report, reset, gear; each sits left of the next, the gear left of the x
  for i, b in ipairs(titleIcons) do
    b:SetSize(s, s)
    b:ClearAllPoints()
    b:SetPoint("RIGHT", titleIcons[i + 1] or closeButton, "LEFT", -gap, 0)
  end
  if closeButton then
    closeButton:SetSize(s, s)
    if closeButton.label then -- text "x" when Details' icons are not available
      applyFont(closeButton.label, "Accidental Presidency", s, "NONE", true)
    end
  end
end
ns.applyIconSize = applyIconSize

-- Details' toolbar icon strip: 8 icons of 32 px side by side
-- 1 cog, 2 page (segment), 3 sword, 4 report, 5 reset, 6 close
local DETAILS_ICONS = DETAILS .. "images\\toolbar_icons_2_shadow"
local function detailsIcon(tex, index)
  if not hasDetails or tex:SetTexture(DETAILS_ICONS) == false then return false end
  tex:SetTexCoord((index - 1) * 32 / 256, index * 32 / 256, 0, 1)
  return true
end

local function createWindow()
  hasDetails = detailsInstalled()

  frame = CreateFrame("Frame", "MySpellsFrame", UIParent)
  ns.frame = frame
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", startMoving)
  frame:SetScript("OnDragStop", stopMoving)
  frame:SetScript("OnMouseUp", onRightClick)
  setResizeLimits()
  frame:SetSize(db.width, db.height)

  local p = db.point
  frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])

  -- window body: Details' background texture, tinted with the saved color (applied in ns.applyText)
  bodyBg = frame:CreateTexture(nil, "BACKGROUND")
  bodyBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -titleH())
  bodyBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  bodyBg.usesTexture = hasDetails and bodyBg:SetTexture(STYLE.body) ~= false

  -- title bar: drag to move, right-click for the mode menu; the buttons on it are added below
  local bar = CreateFrame("Button", nil, frame)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  bar:SetHeight(titleH())
  titleBar = bar
  -- title bar background, shaped like Details' Minimalistic title bar artwork:
  -- the top corners are cut in 3 steps (3, 2, 1 px) and the top rows are a little lighter.
  -- It is built from rows; the saved color is applied in ns.applyText.
  titleBg = {}
  local ROWS = { -- inset from each side, brightness (taken from Details' skin texture)
    { inset = 3, shade = 1.36 },
    { inset = 2, shade = 1.36 },
    { inset = 1, shade = 1.14 },
    { inset = 0, shade = 1.03 },
  }
  for i, r in ipairs(ROWS) do
    local row = bar:CreateTexture(nil, "BACKGROUND")
    row:SetPoint("TOPLEFT", bar, "TOPLEFT", r.inset, -(i - 1))
    row:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -r.inset, -(i - 1))
    row:SetHeight(1)
    row.shade = r.shade
    titleBg[#titleBg + 1] = row
  end
  local rest = bar:CreateTexture(nil, "BACKGROUND")
  rest:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -#ROWS)
  rest:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  rest.shade = 1
  titleBg[#titleBg + 1] = rest

  -- the title bar only moves the window; the segment button switches segments
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", startMoving)
  bar:SetScript("OnDragStop", stopMoving)
  bar:SetScript("OnMouseUp", onRightClick)
  bar:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("My Spells")
    GameTooltip:AddLine(db.locked and "Window is locked (/myspells lock)" or "Drag: move the window", 1, 1, 1)
    GameTooltip:AddLine("/myspells for more options", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- all title bar buttons live in one holder so they can fade in and out together
  iconHolder = CreateFrame("Frame", nil, bar)
  iconHolder:SetAllPoints(bar)
  iconHolder:SetFrameLevel(bar:GetFrameLevel() + 1)

  -- close button: Details' close icon (an "x" in text if Details is not installed)
  local close = titleButton(iconHolder, 16)
  close:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
  close.tex = close:CreateTexture(nil, "OVERLAY")
  close.tex:SetAllPoints()
  if detailsIcon(close.tex, 6) then
    whiteIcon(close.tex)
  else
    close.label = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    applyFont(close.label, "Accidental Presidency", 16, "NONE", true)
    close.label:SetPoint("CENTER", close, "CENTER", 0, 1)
    close.label:SetText("x")
    close.label:SetTextColor(1, 1, 1)
  end
  closeButton = close
  close:SetScript("OnClick", function()
    db.shown = false
    frame:Hide()
    if ns.hideOptions then ns.hideOptions() end
    print("|cffff9933MySpells|r hidden. Type /myspells to show it again.")
  end)

  -- gear button: Details' cog icon, opens the options menu (Options.lua)
  local gear = titleButton(iconHolder, 16)
  gear:SetPoint("RIGHT", close, "LEFT", 0, 0)
  gear.tex = gear:CreateTexture(nil, "OVERLAY")
  gear.tex:SetAllPoints()
  if not detailsIcon(gear.tex, 1) then
    gear.tex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  end
  whiteIcon(gear.tex)
  gear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Text options")
    GameTooltip:Show()
  end)
  gear:SetScript("OnClick", function(self)
    if ns.toggleOptions then ns.toggleOptions(self) end
  end)

  -- report button: Details' report icon, opens the report window (Report.lua)
  local report = titleButton(iconHolder, 16)
  report:SetPoint("RIGHT", gear, "LEFT", -2, 0)
  report.tex = report:CreateTexture(nil, "OVERLAY")
  report.tex:SetAllPoints()
  if not detailsIcon(report.tex, 4) then
    report.tex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
  end
  whiteIcon(report.tex)
  report:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Report Results")
    GameTooltip:AddLine("Click to open report dialog", 1, 1, 1)
    GameTooltip:Show()
  end)
  report:SetScript("OnClick", function()
    if ns.toggleReport then ns.toggleReport() end
  end)

  -- reset button: Details' reset icon, clears all fight data (like Details' reset)
  local reset = titleButton(iconHolder, 16)
  reset.tex = reset:CreateTexture(nil, "OVERLAY")
  reset.tex:SetAllPoints()
  if not detailsIcon(reset.tex, 5) then
    reset.tex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
  end
  whiteIcon(reset.tex)
  reset:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Reset")
    GameTooltip:AddLine("Click to clear all fight data", 1, 1, 1)
    GameTooltip:AddLine("The game's damage meter is shared, so this also clears Details.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  reset:SetScript("OnClick", function()
    GameTooltip:Hide()
    if not (C_DamageMeter and C_DamageMeter.ResetAllCombatSessions) then
      print("|cffff9933MySpells|r the game's damage meter can't be reset here.")
      return
    end
    -- with Details installed this goes through Details' own reset, which clears both
    local ok = pcall(C_DamageMeter.ResetAllCombatSessions)
    if not ok then
      print("|cffff9933MySpells|r couldn't reset right now, try again out of combat.")
      return
    end
    db.segment = "current"
    if ns.hideSegmentMenu then ns.hideSegmentMenu() end
    refresh()
  end)

  -- segment button: Details' page icon
  -- left click: list of fights to pick from (Segments.lua), right click: next segment
  local segment = titleButton(iconHolder, 16)
  segment:SetPoint("RIGHT", report, "LEFT", -2, 0)
  segment:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  segment.tex = segment:CreateTexture(nil, "OVERLAY")
  segment.tex:SetAllPoints()
  if not detailsIcon(segment.tex, 2) then
    segment.tex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
  end
  whiteIcon(segment.tex)
  local function segmentTooltip(self)
    if ns.segmentMenuShown and ns.segmentMenuShown() then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Segment")
    GameTooltip:AddLine(ns.segmentLabel(), 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: choose a fight", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: next segment", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end
  segment:SetScript("OnEnter", segmentTooltip)

  -- every title bar button: full brightness while hovered, icon size from the settings
  -- mode button: Details' sword icon
  -- left click: pick Damage Done / Healing Done / Damage Prevented (Modes.lua), right click: next mode
  local mode = titleButton(iconHolder, 16)
  mode:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mode.tex = mode:CreateTexture(nil, "OVERLAY")
  mode.tex:SetAllPoints()
  if not detailsIcon(mode.tex, 3) then
    mode.tex:SetTexture("Interface\\Icons\\INV_Sword_04")
  end
  whiteIcon(mode.tex)
  local function modeTooltip(self)
    if ns.modeMenuShown and ns.modeMenuShown() then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Mode")
    GameTooltip:AddLine(ns.currentMode().label, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: choose a mode", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: next mode", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end
  mode:SetScript("OnEnter", modeTooltip)
  mode:SetScript("OnClick", function(self, button)
    GameTooltip:Hide()
    if button == "RightButton" then
      local index = 1
      for i, m in ipairs(MODES) do if m.key == db.mode then index = i end end
      ns.setMode(MODES[index % #MODES + 1].key)
      modeTooltip(self)
    elseif ns.toggleModeMenu then
      ns.toggleModeMenu(self)
    end
  end)

  titleIcons = { segment, mode, report, reset, gear }
  for _, b in ipairs({ segment, mode, report, reset, gear, close }) do
    b:HookScript("OnEnter", function(self) self:SetAlpha(1) end)
  end
  applyIconSize()
  segment:SetScript("OnClick", function(self, button)
    GameTooltip:Hide()
    if button == "RightButton" then
      if ns.nextSegment then ns.nextSegment() end
      segmentTooltip(self)
    elseif ns.toggleSegmentMenu then
      ns.toggleSegmentMenu(self)
    end
  end)

  title = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)

  -- MySpells' own icon on the left end of the title bar (like Details' icon): the spellbook
  appIcon = bar:CreateTexture(nil, "ARTWORK")
  appIcon:SetPoint("LEFT", bar, "LEFT", 3, 0)
  appIcon:SetSize(titleH() - 3, titleH() - 3)
  appIcon:SetTexture(APP_ICON)
  appIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's built-in border

  -- the total on the right end of the bar (only while the icons are hidden)
  titleTotal = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  titleTotal:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
  titleTotal:SetJustifyH("RIGHT")
  titleTotal:SetWordWrap(false)
  titleTotal:Hide()

  -- icons showing: the title (with the total after it) stops before the icons.
  -- icons hidden: the title uses the bar up to the total, which sits on the right end.
  local function setTitleWidth(full, force)
    if titleFull == full and not force then return end
    titleFull = full
    title:ClearAllPoints()
    title:SetPoint("LEFT", appIcon, "RIGHT", 4, 0)
    if full then
      title:SetPoint("RIGHT", titleTotal, "LEFT", -6, 0)
    else
      title:SetPoint("RIGHT", titleIcons[1], "LEFT", -4, 0) -- the leftmost icon
    end
    ns.updateTitleText()
  end
  setTitleWidth(false, true) -- the icons start out showing; the fade below takes over

  emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("TOP", frame, "TOP", 0, -(titleH() + 6))

  -- resize grip in the bottom-right corner: click and hold, then drag
  grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  grip:SetFrameLevel(frame:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or db.locked then return end
    -- pin the top-left corner so only the bottom-right moves
    local left, top = frame:GetLeft(), frame:GetTop()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    interacting = true
    frame:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    interacting = false
    frame:StopMovingOrSizing()
    db.width, db.height = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
    savePosition()
    refresh()
  end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Drag to resize")
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  updateGrip()

  -- show or hide rows live while resizing
  frame:SetScript("OnSizeChanged", refresh)

  -- redraws: game updates only mark the window dirty, and it redraws at most every REDRAW_EVERY.
  -- In combat it is also marked dirty twice a second, since updates alone can be sparse.
  local sinceRedraw, sinceCombatTick = 0, 0
  local fade = 1
  frame:SetScript("OnUpdate", function(_, dt)
    -- title bar icons and resize corner: only while hovered, moved/resized, or a menu is open
    local want = 1
    if db.text.titleIconsHover then
      local busy = interacting or frame:IsMouseOver()
        or (ns.segmentMenuShown and ns.segmentMenuShown())
        or (ns.modeMenuShown and ns.modeMenuShown())
        or (ns.optionsShown and ns.optionsShown())
        or (ns.reportShown and ns.reportShown())
      want = busy and 1 or 0
    end
    if fade ~= want then
      -- quick fade: about 0.15 seconds
      local step = dt * 7
      fade = want > fade and math.min(want, fade + step) or math.max(want, fade - step)
      iconHolder:SetAlpha(fade)
      grip:SetAlpha(fade)
    end
    -- make room for the icons as soon as they start showing; take it back once they're gone
    if want == 1 then
      setTitleWidth(false)
    elseif fade == 0 then
      setTitleWidth(true)
    end

    sinceRedraw = sinceRedraw + dt
    sinceCombatTick = sinceCombatTick + dt
    if sinceCombatTick >= 0.5 then
      sinceCombatTick = 0
      if UnitAffectingCombat("player") then dirty = true end
    end
    if dirty and sinceRedraw >= REDRAW_EVERY then
      sinceRedraw = 0
      refresh()
    end
  end)
  frame:SetScript("OnShow", refresh)

  ns.applyText()
  frame:SetShown(db.shown)
end

---------------------------------------------------------------------------
-- slash command
---------------------------------------------------------------------------

local function say(msg) print("|cffff9933MySpells|r " .. msg) end

-- show or hide the window (/myspells, the minimap button)
function ns.toggleWindow()
  if not frame then return end
  db.shown = not frame:IsShown()
  frame:SetShown(db.shown)
  if not db.shown then
    if ns.hideOptions then ns.hideOptions() end
    if ns.hideSegmentMenu then ns.hideSegmentMenu() end
    if ns.hideModeMenu then ns.hideModeMenu() end
  end
end

SLASH_MYSPELLS1 = "/myspells"
SLASH_MYSPELLS2 = "/mys"
SlashCmdList.MYSPELLS = function(msg)
  local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "" or cmd == "toggle" then
    ns.toggleWindow()
  elseif cmd == "minimap" then
    if ns.toggleMinimapButton then ns.toggleMinimapButton() end
  elseif cmd == "current" then
    ns.setSegment("current") say("showing the current fight.")
  elseif cmd == "overall" then
    ns.setSegment("overall") say("showing overall.")
  elseif cmd == "lock" then
    db.locked = not db.locked
    updateGrip()
    say(db.locked and "window locked." or "window unlocked.")
  elseif cmd == "rows" and tonumber(arg) then
    local n = math.max(MIN_ROWS, math.min(MAX_ROWS, math.floor(tonumber(arg))))
    db.height = titleH() + n * rowStep() + PAD
    frame:SetHeight(db.height)
    refresh()
    say("showing " .. n .. " rows.")
  elseif cmd == "options" or cmd == "config" then
    if not frame:IsShown() then db.shown = true frame:Show() end
    if ns.toggleOptions then ns.toggleOptions() end
  elseif cmd == "reset" then
    db.point = { unpack(DEFAULTS.point) }
    db.width, db.height = DEFAULTS.width, DEFAULTS.height
    frame:ClearAllPoints()
    frame:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
    frame:SetSize(db.width, db.height)
    db.shown = true frame:Show()
    say("window size and position reset.")
  else
    say("commands:")
    print("  /myspells - show or hide the window")
    print("  /myspells options - open the text options (or click the gear)")
    print("  /myspells current | overall - which fight to show")
    print("  /myspells rows <" .. MIN_ROWS .. "-" .. MAX_ROWS .. "> - set the height in rows")
    print("  /myspells lock - lock or unlock the window (hides the resize grip)")
    print("  /myspells reset - reset the window size and position")
    print("  /myspells minimap - show or hide the minimap button")
  end
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
ns.copy = copy

-- fill in any missing settings (one level deep for the text and bars tables)
local NESTED = { text = true, bars = true, report = true, minimap = true }
local function applyDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then
      target[k] = copy(v)
    elseif NESTED[k] and type(target[k]) == "table" then
      applyDefaults(target[k], v)
    end
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    MySpellsDB = MySpellsDB or {}
    db = MySpellsDB
    ns.db = db
    -- settings from earlier versions that are no longer used
    db.rows, db.overall, db.psDefault2 = nil, nil, nil
    -- past fight ids do not survive a reload; start on the current fight
    if type(db.segment) == "number" then db.segment = "current" end
    applyDefaults(db, DEFAULTS)
    createWindow()
    if ns.createMinimapButton then ns.createMinimapButton() end -- Minimap.lua
    self:UnregisterEvent("ADDON_LOADED")
    for _, e in ipairs({
      "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
      "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET",
    }) do
      pcall(self.RegisterEvent, self, e) -- skip events this client does not have
    end
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    -- fonts from other addons (SharedMedia) may only be registered by now
    ns.applyText()
    return
  end
  if event == "DAMAGE_METER_RESET" then
    -- the game cleared its fights; go back to the current one
    db.segment = "current"
    if ns.hideSegmentMenu then ns.hideSegmentMenu() end
  end
  if event == "PLAYER_REGEN_ENABLED" then
    -- numbers often become readable a moment after combat ends
    if C_Timer and C_Timer.After then C_Timer.After(1, function() dirty = true end) end
  end
  -- game updates can come many times a second; mark for the next redraw instead of redrawing now
  dirty = true
end)
