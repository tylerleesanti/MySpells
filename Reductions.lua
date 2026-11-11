-- MySpells passive damage reductions: an estimate of the damage your always-on percent reductions
-- (stances, forms, talents) prevented, shown as extra rows in Damage Prevented.
--
-- Addons can't see single hits, but the game's damage meter keeps your damage taken per enemy
-- ability. If a reduction of r was up, you took (1 - r) of the damage, so
--   prevented = taken * r / (1 - r)
-- Several reductions multiply; each gets its share of the prevented damage by its size.
-- The meter hides its numbers during combat, so the estimate fills in once the fight ends.
-- It uses what is active now (stance, form, buff, pet), so it assumes that was up for the fight.

local ADDON, ns = ...

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function canUse(v) return type(v) ~= "nil" and not isSecret(v) end

-- enemy abilities known to be physical when the meter doesn't say: melee swings and shots
local PHYSICAL_SPELLS = { [1] = true, [6603] = true, [75] = true, [3018] = true }
local PHYSICAL_SCHOOL = 1

---------------------------------------------------------------------------
-- what is active
---------------------------------------------------------------------------

-- stances and forms (Defensive Stance, Shadowform)
local function formActive(spellID)
  if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then return false end
  for i = 1, GetNumShapeshiftForms() or 0 do
    local ok, _, active, _, id = pcall(GetShapeshiftFormInfo, i)
    if ok and active and id == spellID then return true end
  end
  return false
end

local function auraActive(spellID)
  if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if ok and aura then return true end
  end
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok or not aura then break end
      if canUse(aura.spellId) and aura.spellId == spellID then return true end
    end
  end
  return false
end

local function knows(spellID)
  if IsPlayerSpell then
    local ok, known = pcall(IsPlayerSpell, spellID)
    if ok and known then return true end
  end
  if IsSpellKnown then
    local ok, known = pcall(IsSpellKnown, spellID)
    if ok and known then return true end
  end
  return false
end

local function voidwalkerOut()
  if not UnitExists("pet") then return false end
  local family = UnitCreatureFamily and UnitCreatureFamily("pet")
  return canUse(family) and family == (VOIDWALKER or "Voidwalker")
end

---------------------------------------------------------------------------
-- the percent: read from the spell's own text when possible (WoW Forever may differ from the
-- original game), the original value otherwise
---------------------------------------------------------------------------

local percentCache = {}
local function spellText(spellID)
  local parts = {}
  if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
    local ok, data = pcall(C_TooltipInfo.GetSpellByID, spellID)
    if ok and data and data.lines then
      for _, line in ipairs(data.lines) do
        if canUse(line.leftText) then parts[#parts + 1] = line.leftText end
      end
    end
  end
  if #parts == 0 then
    local get = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    local ok, desc = pcall(get, spellID)
    if ok and canUse(desc) then parts[1] = desc end
  end
  return table.concat(parts, " ")
end

local function readPercent(spellID, pattern, fallback)
  if percentCache[spellID] then return percentCache[spellID] end
  local value = tonumber(spellText(spellID):match(pattern) or "")
  if value and value > 0 and value < 100 then
    percentCache[spellID] = value -- only remember what was read (the text can load late)
    return value
  end
  return fallback
end

---------------------------------------------------------------------------
-- the reductions (vanilla class data, as on WoW Forever)
-- school: "all" (any damage) or "physical"
---------------------------------------------------------------------------

local EFFECTS = {
  { class = "WARRIOR", spell = 71, school = "all", default = 10, -- Defensive Stance
    pattern = "damage taken by (%d+)%%",
    active = function() return formActive(71) or auraActive(71) end },
  { class = "PRIEST", spell = 15473, school = "physical", default = 15, -- Shadowform
    pattern = "[Pp]hysical damage done to you by (%d+)%%",
    active = function() return formActive(15473) or auraActive(15473) end },
  { class = "WARLOCK", spell = 19028, school = "all", default = 30, -- Soul Link (damage your demon takes instead)
    pattern = "(%d+)%% of all damage taken",
    active = function() return auraActive(19028) end },
  { class = "WARLOCK", ranks = { 23785, 23822, 23823, 23824, 23825 }, perRank = 2, -- Master Demonologist
    school = "physical", pattern = "Voidwalker %- Reduces physical damage taken by (%d+)%%",
    active = voidwalkerOut },
}

-- the reductions up right now: { spellID, r (0..1), school, percent }
local function activeReductions()
  local _, class = UnitClass("player")
  local out = {}
  for _, e in ipairs(EFFECTS) do
    if e.class == class and e.active() then
      local spellID, default = e.spell, e.default
      if e.ranks then -- a talent: the highest rank learned
        spellID = nil
        for rank = #e.ranks, 1, -1 do
          if knows(e.ranks[rank]) then spellID, default = e.ranks[rank], rank * e.perRank break end
        end
      end
      if spellID then
        local pct = readPercent(spellID, e.pattern, default)
        out[#out + 1] = { spellID = spellID, r = pct / 100, school = e.school, percent = pct }
      end
    end
  end
  return out
end

local function isPhysical(spell)
  local school = spell.school or spell.spellSchool
  if canUse(school) and type(school) == "number" then
    return bit and bit.band(school, PHYSICAL_SCHOOL) ~= 0 or school % 2 == 1
  end
  return canUse(spell.spellID) and PHYSICAL_SPELLS[spell.spellID] or false
end

---------------------------------------------------------------------------
-- the estimate
---------------------------------------------------------------------------

-- taken: your Damage Taken source from the meter, for the same fight as the window.
-- Returns rows shaped like the meter's spells ({ spellID, totalAmount, amountPerSecond }) with
-- estimated = true and a note for the tooltip, or nil (nothing active, or numbers hidden).
function ns.estimateReductions(taken)
  if not taken or type(taken.combatSpells) ~= "table" then return nil end
  local reductions = activeReductions()
  if #reductions == 0 then return nil end

  local physical, other = 0, 0
  for _, spell in ipairs(taken.combatSpells) do
    local amount = spell.totalAmount
    if not canUse(amount) then return nil end -- hidden during combat
    if isPhysical(spell) then physical = physical + amount else other = other + amount end
  end
  local takenTotal = physical + other
  if takenTotal <= 0 then return nil end

  -- per bucket: the reductions that apply multiply; split the prevented damage by each one's size
  local prevented = {}
  local function bucket(amount, isPhysicalBucket)
    if amount <= 0 then return end
    local sum, applies = 0, {}
    for _, red in ipairs(reductions) do
      if red.school == "all" or isPhysicalBucket then
        local weight = -math.log(1 - red.r)
        sum = sum + weight
        applies[#applies + 1] = { red = red, weight = weight }
      end
    end
    if sum <= 0 then return end
    local total = amount * (math.exp(sum) - 1) -- what you would have taken, minus what you took
    for _, a in ipairs(applies) do
      prevented[a.red] = (prevented[a.red] or 0) + total * a.weight / sum
    end
  end
  bucket(other, false)
  bucket(physical, true)

  local aps = taken.amountPerSecond
  local rows = {}
  for _, red in ipairs(reductions) do
    local amount = prevented[red]
    if amount and amount >= 1 then
      rows[#rows + 1] = {
        spellID = red.spellID,
        totalAmount = math.floor(amount + 0.5),
        amountPerSecond = canUse(aps) and aps * amount / takenTotal or nil,
        estimated = true,
        note = red.school == "physical"
          and string.format("Estimate: %d%% less physical damage taken (melee and shots)", red.percent)
          or string.format("Estimate: %d%% less damage taken", red.percent),
      }
    end
  end
  return #rows > 0 and rows or nil
end
