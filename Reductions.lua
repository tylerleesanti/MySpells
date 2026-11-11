-- MySpells damage reductions: an estimate of the damage your percent reductions (stances, forms,
-- talents, talent procs) prevented, shown as extra rows in Damage Prevented.
--
-- Addons can't see single hits, but the game's damage meter keeps your damage taken per enemy
-- ability. During each fight MySpells notes how long each reduction was up (its uptime). A reduction
-- r that was up for a share f of the fight works like a reduction of f * r over the whole fight, and
--   prevented = taken * r / (1 - r)
-- Several reductions multiply; each gets its share of the prevented damage by its size.
-- The meter hides its numbers during combat, so the estimate fills in once the fight ends.
--
-- Values: WoW Forever's talents and spells as listed by Talents Forever
-- (https://talentsforever.com, CC BY 4.0), beta client 1.60.1.70755, 2026-11-04.

local ADDON, ns = ...

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function canUse(v) return type(v) ~= "nil" and not isSecret(v) end

-- enemy abilities known to be physical when the meter doesn't say: melee swings and shots.
-- Everything else counts as spell (magic) damage.
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

-- a buff on you, by spell id (or by name when the id isn't known)
local function auraActive(spellID, name, notID)
  if spellID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if ok and aura then return true end
  end
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok or not aura then break end
      local id, auraName = aura.spellId, aura.name
      if canUse(id) and id == spellID then return true end
      if name and canUse(auraName) and auraName == name and not (canUse(id) and id == notID) then return true end
    end
  end
  return false
end

local function petFamily(family)
  if not UnitExists("pet") then return false end
  local f = UnitCreatureFamily and UnitCreatureFamily("pet")
  return canUse(f) and f == family
end

local function spellName(spellID)
  local ok, info = pcall(function() return C_Spell and C_Spell.GetSpellInfo(spellID) end)
  if ok and info and canUse(info.name) then return info.name end
  if GetSpellInfo then
    local ok2, n = pcall(GetSpellInfo, spellID)
    if ok2 and canUse(n) then return n end
  end
end

---------------------------------------------------------------------------
-- talent ranks: WoW Forever's talents are a trait tree (C_Traits); found by talent name
---------------------------------------------------------------------------

local talents = {} -- lower-case name -> { rank, spellID }
local talentsDirty = true

local function scanTalents()
  talentsDirty = false
  wipe(talents)
  if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo then
    pcall(function()
      local configID = C_ClassTalents.GetActiveConfigID()
      local config = configID and C_Traits.GetConfigInfo(configID)
      for _, treeID in ipairs(config and config.treeIDs or {}) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
          local node = C_Traits.GetNodeInfo(configID, nodeID)
          local rank = node and (node.currentRank or node.ranksPurchased) or 0
          if rank > 0 then
            local entryID = node.activeEntry
            if type(entryID) == "table" then entryID = entryID.entryID end
            entryID = entryID or (node.entryIDs and node.entryIDs[1])
            local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
            local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
            local sid = def and (def.spellID or def.overriddenSpellID)
            local name = def and def.overrideName or (sid and spellName(sid))
            if name then talents[name:lower()] = { rank = rank, spellID = sid } end
          end
        end
      end
    end)
  end
  if next(talents) == nil and GetNumTalentTabs and GetTalentInfo then -- older talent frames
    pcall(function()
      for tab = 1, GetNumTalentTabs() do
        for i = 1, GetNumTalents(tab) do
          local name, _, _, _, rank = GetTalentInfo(tab, i)
          if type(name) == "string" and (rank or 0) > 0 then talents[name:lower()] = { rank = rank } end
        end
      end
    end)
  end
end

local function talent(name)
  if talentsDirty then scanTalents() end
  return talents[name:lower()]
end

---------------------------------------------------------------------------
-- the reductions
-- school: "all", "physical" or "magic" (spell damage)
-- percent(): the reduction in % while it is up, or nil while it isn't
-- proc: up only now and then; without a record of the fight it isn't guessed
---------------------------------------------------------------------------

-- a talent with a % per rank, up while condition() (if any) holds
local function talentPercent(name, perRank, condition)
  return function()
    local t = talent(name)
    if not t or (condition and not condition()) then return nil end
    return perRank[math.min(t.rank, #perRank)]
  end
end

local function righteousFury() return auraActive(25780, spellName(25780)) end

local EFFECTS = {
  -- Warrior
  { key = "defensiveStance", class = "WARRIOR", spellID = 71, school = "all",
    percent = function() return (formActive(71) or auraActive(71)) and 10 or nil end },
  -- Paladin
  { key = "improvedRighteousFury", class = "PALADIN", talent = "Improved Righteous Fury", spellID = 20468, school = "all",
    percent = talentPercent("Improved Righteous Fury", { 3, 6, 9 }, righteousFury) },
  { key = "ironCreed", class = "PALADIN", talent = "Iron Creed", spellID = 1311034, school = "all", proc = true,
    percent = talentPercent("Iron Creed", { 2, 4, 6 }, function()
      return righteousFury() and auraActive(1311033, "Iron Creed", 1311034) -- the 6 sec buff from Holy Strike
    end) },
  -- Priest
  { key = "shadowform", class = "PRIEST", spellID = 15473, school = "physical",
    percent = function() return (formActive(15473) or auraActive(15473)) and 15 or nil end },
  { key = "spellWarding", class = "PRIEST", talent = "Spell Warding", school = "magic",
    percent = talentPercent("Spell Warding", { 2, 4, 6, 8, 10 }) },
  -- Shaman (Fire, Frost and Nature only; counted on all spell damage, so it reads high against Shadow or Arcane)
  { key = "elementalWarding", class = "SHAMAN", talent = "Elemental Warding", school = "magic",
    percent = talentPercent("Elemental Warding", { 3, 7, 10 }) },
  -- Warlock
  { key = "soulLink", class = "WARLOCK", spellID = 19028, school = "all", -- damage your demon takes instead
    percent = function() return auraActive(19028) and 30 or nil end },
  { key = "moltenSkin", class = "WARLOCK", talent = "Molten Skin", school = "all",
    percent = talentPercent("Molten Skin", { 2, 4, 6, 8, 10 }) },
  { key = "demonologistVoidwalker", class = "WARLOCK", talent = "Master Demonologist", school = "physical",
    label = "Voidwalker",
    percent = talentPercent("Master Demonologist", { 2, 4, 6, 8, 10 }, function() return petFamily(VOIDWALKER or "Voidwalker") end) },
  { key = "demonologistFelhunter", class = "WARLOCK", talent = "Master Demonologist", school = "magic",
    label = "Felhunter",
    percent = talentPercent("Master Demonologist", { 2, 4, 6, 8, 10 }, function() return petFamily(FELHUNTER or "Felhunter") end) },
}

local function myEffects()
  local _, class = UnitClass("player")
  local out = {}
  for _, e in ipairs(EFFECTS) do
    if e.class == class then out[#out + 1] = e end
  end
  return out
end

-- the row's spell (name and icon): the talent's own spell when the client gives it
local function effectSpell(e)
  if e.talent then
    local t = talent(e.talent)
    if t and t.spellID then return t.spellID end
  end
  return e.spellID
end

---------------------------------------------------------------------------
-- uptime: sampled while in combat, kept per fight (the meter's session id)
-- record = { time = seconds in combat, up = { key = seconds }, pct = { key = % } }
---------------------------------------------------------------------------

local fights = {}      -- session id -> record
local lastFight         -- the most recent fight's record (the window's "Current fight")
local fight            -- the fight being recorded
local SAMPLE_EVERY = 0.2

local function newRecord() return { time = 0, up = {}, pct = {} } end

local function sample(elapsed)
  for _, e in ipairs(myEffects()) do
    local ok, pct = pcall(e.percent)
    if ok and pct then
      fight.up[e.key] = (fight.up[e.key] or 0) + elapsed
      fight.pct[e.key] = pct
    end
  end
  fight.time = fight.time + elapsed
end

-- the fight just ended: file it under the newest session the meter has
local function fileFight(record)
  if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return end
  local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
  if not ok or type(sessions) ~= "table" then return end
  local newest
  for _, s in ipairs(sessions) do
    local id = s.sessionID
    if canUse(id) and type(id) == "number" and (not newest or id > newest) then newest = id end
  end
  if newest and not fights[newest] then fights[newest] = record end
end

local tracker = CreateFrame("Frame")
local acc = 0
tracker:SetScript("OnUpdate", function(_, elapsed)
  if not fight then return end
  acc = acc + elapsed
  if acc >= SAMPLE_EVERY then sample(acc) acc = 0 end
end)
tracker:RegisterEvent("PLAYER_REGEN_DISABLED")
tracker:RegisterEvent("PLAYER_REGEN_ENABLED")
tracker:RegisterEvent("DAMAGE_METER_RESET")
for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
  pcall(tracker.RegisterEvent, tracker, e)
end
tracker:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    fight, acc = newRecord(), 0
    sample(0)
  elseif event == "PLAYER_REGEN_ENABLED" then
    if fight then
      if acc > 0 then sample(acc) end
      local record = fight
      fight, lastFight = nil, record
      C_Timer.After(1, function() fileFight(record) if ns.refresh then ns.refresh() end end)
    end
  elseif event == "DAMAGE_METER_RESET" then
    wipe(fights)
    lastFight = nil
  else
    talentsDirty = true
  end
end)

-- the uptime record for the fight the window shows (combined for Overall), or nil
local function recordFor(segment)
  if type(segment) == "number" then return fights[segment] end
  if segment == "overall" then
    local sum, any = newRecord(), false
    local function add(r)
      any = true
      sum.time = sum.time + r.time
      for k, v in pairs(r.up) do sum.up[k] = (sum.up[k] or 0) + v end
      for k, v in pairs(r.pct) do sum.pct[k] = v end
    end
    local counted = {}
    for _, r in pairs(fights) do add(r) counted[r] = true end
    if lastFight and not counted[lastFight] then add(lastFight) end
    return any and sum or nil
  end
  return lastFight
end

---------------------------------------------------------------------------
-- the estimate
---------------------------------------------------------------------------

local function isPhysical(spell)
  local school = spell.school or spell.spellSchool
  if canUse(school) and type(school) == "number" then
    return school % 2 == 1 -- the physical bit
  end
  return canUse(spell.spellID) and PHYSICAL_SPELLS[spell.spellID] or false
end

-- the reductions for this fight: { effect, r (0..1, uptime included), percent, uptime (0..1) }
local function reductionsFor(segment)
  local record = recordFor(segment)
  local out = {}
  for _, e in ipairs(myEffects()) do
    local pct, uptime
    if record and record.time > 0 then
      pct, uptime = record.pct[e.key], math.min(1, (record.up[e.key] or 0) / record.time)
    elseif not e.proc then
      -- no record (fought before a reload): assume what is up now was up the whole fight
      local ok, now = pcall(e.percent)
      if ok and now then pct, uptime = now, 1 end
    end
    if pct and uptime and uptime > 0 and pct > 0 and pct < 100 then
      out[#out + 1] = { effect = e, r = pct / 100 * uptime, percent = pct, uptime = uptime, guessed = not record }
    end
  end
  return out
end

-- taken: your Damage Taken source from the meter, for the same fight as the window.
-- segment: the window's segment ("current", "overall" or a session id).
-- Returns rows shaped like the meter's spells ({ spellID, totalAmount, amountPerSecond }) with
-- estimated = true and a note for the tooltip, or nil (nothing up, or numbers hidden).
function ns.estimateReductions(taken, segment)
  if not taken or type(taken.combatSpells) ~= "table" then return nil end
  local reductions = reductionsFor(segment)
  if #reductions == 0 then return nil end

  local physical, magic = 0, 0
  for _, spell in ipairs(taken.combatSpells) do
    local amount = spell.totalAmount
    if not canUse(amount) then return nil end -- hidden during combat
    if isPhysical(spell) then physical = physical + amount else magic = magic + amount end
  end
  local takenTotal = physical + magic
  if takenTotal <= 0 then return nil end

  -- per kind of damage: the reductions that apply multiply; split the prevented damage by size
  local prevented = {}
  local function bucket(amount, kind)
    if amount <= 0 then return end
    local sum, applies = 0, {}
    for _, red in ipairs(reductions) do
      local school = red.effect.school
      if school == "all" or school == kind then
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
  bucket(physical, "physical")
  bucket(magic, "magic")

  local aps = taken.amountPerSecond
  local WHAT = { all = "damage", physical = "physical damage (melee and shots)", magic = "spell damage" }
  local rows = {}
  for _, red in ipairs(reductions) do
    local amount = prevented[red]
    if amount and amount >= 1 then
      local e = red.effect
      local note = string.format("Estimate: %d%% less %s taken", red.percent, WHAT[e.school])
      if e.label then note = note .. " with your " .. e.label end
      if red.guessed then
        note = note .. ", assumed up the whole fight"
      else
        note = note .. string.format(", up %d%% of the fight", math.floor(red.uptime * 100 + 0.5))
      end
      rows[#rows + 1] = {
        spellID = effectSpell(e),
        totalAmount = math.floor(amount + 0.5),
        amountPerSecond = canUse(aps) and aps * amount / takenTotal or nil,
        estimated = true,
        note = note .. ".",
      }
    end
  end
  return #rows > 0 and rows or nil
end

-- /myspells reductions: what MySpells sees right now, to check it in game
function ns.printReductions()
  local function say(msg) print("|cffff9933MySpells|r " .. msg) end
  talentsDirty = true
  local list = myEffects()
  if #list == 0 then say("no damage reductions are tracked for your class.") return end
  say("damage reductions for your class:")
  for _, e in ipairs(list) do
    local ok, pct = pcall(e.percent)
    local name = spellName(effectSpell(e) or 0) or e.talent or e.key
    if e.label then name = name .. " (" .. e.label .. ")" end
    local state = (ok and pct) and ("|cff00ff00up, " .. pct .. "%|r") or "|cff888888not up|r"
    if e.talent then
      local t = talent(e.talent)
      state = state .. (t and (", talent rank " .. t.rank) or ", talent not learned")
    end
    if lastFight and lastFight.time > 0 then
      state = state .. string.format(", last fight %d%% uptime", math.floor((lastFight.up[e.key] or 0) / lastFight.time * 100 + 0.5))
    end
    print("  " .. name .. ": " .. state)
  end
end
