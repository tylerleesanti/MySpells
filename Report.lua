-- MySpells report window: send the current segment's spells to chat.
-- A copy of Details' report dialog ("Link Details!"): channel dropdown, whisper name,
-- Lines slider (1-25), Reverse, Send, and a Copy & Paste window.
-- Lines go out one every 0.2 seconds, the same as Details.

local ADDON, ns = ...

local SendChat = SendChatMessage or (C_ChatInfo and C_ChatInfo.SendChatMessage)
local DETAILS = "Interface\\AddOns\\Details\\"
local SEND_DELAY = 0.2
local INSERT_NAME = "insert player name"

local win, copyFrame, ddList
local R -- db.report

local function say(msg) print("|cffff9933MySpells|r " .. msg) end

---------------------------------------------------------------------------
-- look: Details' report window backdrops
---------------------------------------------------------------------------

local DARK_BACKDROP = {
  bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
  edgeFile = [[Interface\Buttons\WHITE8X8]],
  edgeSize = 1, tile = true, tileSize = 64,
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local function darkBox(f, bgAlpha)
  f:SetBackdrop(DARK_BACKDROP)
  f:SetBackdropBorderColor(0, 0, 0, 0.5)
  f:SetBackdropColor(0, 0, 0, bgAlpha or 0.3)
end

local function smallText(parent, size, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  local font, _, flags = fs:GetFont()
  if font then fs:SetFont(font, size or 10, flags) end
  return fs
end

---------------------------------------------------------------------------
-- channels (same list, icons and colors as Details)
---------------------------------------------------------------------------

local TOAST = [[Interface\FriendsFrame\UI-Toast-ToastIcons]]
local function inGroup() return GetNumSubgroupMembers() > 0 end

local BASE_CHANNELS = {
  { label = "Party", value = "PARTY", show = inGroup, icon = TOAST, coords = { 0.53125, 0.7265625, 0.078125, 0.40625 }, color = { 0.66, 0.65, 1 } },
  { label = "Raid", value = "RAID", show = IsInRaid, icon = TOAST, coords = { 0.53125, 0.7265625, 0.078125, 0.40625 }, color = { 1, 0.49, 0 } },
  { label = "Guild", value = "GUILD", show = IsInGuild, icon = TOAST, coords = { 0.8046875, 0.96875, 0.125, 0.390625 }, color = { 0.25, 0.98, 0.25 } },
  { label = "Officer Channel", value = "OFFICER", show = IsInGuild, icon = TOAST, coords = { 0.8046875, 0.96875, 0.125, 0.390625 }, color = { 0.25, 0.74, 0.25 } },
  { label = "Whisper", value = "WHISPER", icon = TOAST, coords = { 0.0546875, 0.1953125, 0.625, 0.890625 }, color = { 1, 0.49, 1 } },
  { label = "Whisper Target", value = "WHISPER2", icon = TOAST, coords = { 0.0546875, 0.1953125, 0.625, 0.890625 }, color = { 1, 0.49, 1 } },
  { label = "Say", value = "SAY", show = IsInInstance, icon = TOAST, coords = { 0.0390625, 0.203125, 0.09375, 0.375 }, color = { 1, 1, 1 } },
  { label = "Copy & Paste", value = "COPY", icon = [[Interface\Buttons\UI-GuildButton-PublicNote-Disabled]], coords = { 0, 1, 0, 1 }, color = { 1, 1, 1 } },
}

local function channelList()
  local list = {}
  for _, c in ipairs(BASE_CHANNELS) do
    if not c.show or c.show() then list[#list + 1] = c end
  end
  -- chat channels you have joined (General, Trade, custom ones)
  local channels = { GetChannelList() } -- id, name, disabled, id, name, disabled, ...
  for i = 1, #channels, 3 do
    if channels[i + 1] then
      list[#list + 1] = {
        label = channels[i] .. ". " .. channels[i + 1], value = "CHANNEL|" .. channels[i + 1],
        icon = TOAST, coords = { 0.3046875, 0.4453125, 0.109375, 0.390625 }, color = { 149 / 255, 112 / 255, 112 / 255 },
      }
    end
  end
  -- online Battle.net friends
  pcall(function()
    local _, online = BNGetNumFriends()
    for i = 1, online or 0 do
      local info = C_BattleNet.GetFriendAccountInfo(i)
      local game = info and info.gameAccountInfo
      if game and game.isOnline and info.battleTag then
        list[#list + 1] = {
          label = info.battleTag:gsub("#.*", ""), value = "REALID|" .. info.bnetAccountID,
          icon = [[Interface\FriendsFrame\Battlenet-Battleneticon]], coords = { 0.125, 0.875, 0.125, 0.875 }, color = { 1, 1, 1 },
        }
      end
    end
  end)
  return list
end

-- if the saved channel is not available, pick one like Details does
local function validChannel(where)
  for _, c in ipairs(channelList()) do
    if c.value == where then return where end
  end
  if IsInRaid() then return "RAID" end
  if inGroup() then return "PARTY" end
  if IsInGuild() then return "GUILD" end
  return "SAY"
end

---------------------------------------------------------------------------
-- building the report lines
---------------------------------------------------------------------------

-- Details' ToK: 12.3K / 1.23M, whole numbers below
local function toK(n)
  if n > 999999999 then return string.format("%.2fB", n / 1e9) end
  if n > 1000000 then return string.format("%.2fM", n / 1e6) end
  if n > 999 then return string.format("%.1fK", n / 1e3) end
  return string.format("%.0f", n)
end

-- an invisible text used to measure how wide a line is in chat
local measure

-- set the measuring font to the chat window's font size (like Details); once per report
local function prepareMeasure()
  if not measure then
    measure = UIParent:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
    measure:Hide()
  end
  local size = 12
  if FCF_GetChatWindowInfo then
    local _, s = FCF_GetChatWindowInfo(1)
    if s and s >= 1 then size = s end
  end
  local font, _, flags = GameFontNormal:GetFont()
  measure:SetFont(font, size, flags)
end

local function textWidth(text)
  measure:SetText(text)
  return measure:GetStringWidth()
end

local function buildLines()
  local list, err, total = ns.getMySpells()
  if err then return nil, err end
  if not list or #list == 0 then return nil, "nothing to report." end
  -- in combat the game may hide the numbers; Details says the same thing here
  if ns.isSecret(total) then return nil, "Report data is secret, try after combat." end
  local sum = 0
  for _, s in ipairs(list) do
    if ns.isSecret(s.totalAmount) then return nil, "Report data is secret, try after combat." end
    sum = sum + (s.totalAmount or 0)
  end
  if type(total) ~= "number" then total = sum end

  local amount = math.min(R.lines, #list)
  local rows = {}
  for i = 1, amount do
    local s = list[i]
    local name = ns.spellName(s.spellID)
    local pet = s.creatureName
    if not ns.isSecret(pet) and type(pet) == "string" and pet ~= "" then
      name = name .. " (" .. pet:gsub(" <.*", "") .. ")"
    end
    local value = s.totalAmount > 10000 and toK(s.totalAmount) or string.format("%.0f", s.totalAmount)
    local pct = string.format("%.1f%%", total > 0 and s.totalAmount / total * 100 or 0)
    rows[i] = { index = i, name = i .. ". " .. name, value = value .. " (" .. pct .. ")" }
  end
  if R.reverse then
    local reversed = {}
    for i = #rows, 1, -1 do reversed[#reversed + 1] = rows[i] end
    rows = reversed
  end

  -- pad names with dots so the numbers line up (Details caps this at 130)
  prepareMeasure()
  local widest = textWidth("DEFAULT NAME")
  for _, r in ipairs(rows) do widest = math.max(widest, textWidth(r.name)) end
  widest = math.min(widest, 130)

  local who = UnitName("player")
  local segment = ns.segmentLabel()
  local lines = { "MySpells! " .. ns.currentMode().label .. " by " .. who .. " (" .. segment .. ")" .. (R.reverse and " (reversed)" or "") }
  for _, r in ipairs(rows) do
    local name = r.name .. " "
    local guard = 0
    while textWidth(name) < widest and guard < 60 do
      name = name .. "."
      guard = guard + 1
    end
    lines[#lines + 1] = name .. " " .. r.value
  end
  return lines
end

---------------------------------------------------------------------------
-- Copy & Paste window (Details' "Export Text")
---------------------------------------------------------------------------

local function showCopyWindow(lines)
  if not copyFrame then
    copyFrame = CreateFrame("Frame", "MySpellsCopyFrame", UIParent, "BackdropTemplate")
    copyFrame:SetFrameStrata("TOOLTIP")
    copyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    copyFrame:SetSize(400, 400)
    copyFrame:SetBackdrop({ bgFile = [[Interface\Buttons\WHITE8X8]], edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1 })
    copyFrame:SetBackdropColor(0.0549, 0.0549, 0.0549, 0.934)
    copyFrame:SetBackdropBorderColor(0, 0, 0, 1)
    tinsert(UISpecialFrames, "MySpellsCopyFrame")

    local bar = copyFrame:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 1, -1) bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(20)
    copyFrame.bar = bar
    local title = smallText(copyFrame, 12)
    title:SetPoint("TOP", copyFrame, "TOP", 0, -5)
    title:SetText("Export Text")
    title:SetTextColor(0.8, 0.8, 0.8)

    local edit = CreateFrame("EditBox", nil, copyFrame)
    edit:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", 4, -26)
    edit:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -4, 4)
    edit:SetAutoFocus(false)
    edit:SetMultiLine(true)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    edit:SetScript("OnEditFocusLost", function() copyFrame:Hide() end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() copyFrame:Hide() end)
    edit:SetScript("OnChar", function(self) self:ClearFocus() copyFrame:Hide() end)
    copyFrame.edit = edit
  end
  copyFrame.bar:SetColorTexture(ns.titleBarColor()) -- same as your window's title bar
  copyFrame:Show()
  copyFrame.edit:SetText(table.concat(lines, "\n") .. "\n")
  copyFrame.edit:HighlightText()
  copyFrame.edit:SetFocus()
end

---------------------------------------------------------------------------
-- sending
---------------------------------------------------------------------------

local function sendLines(lines, chatType, target)
  for i, line in ipairs(lines) do
    C_Timer.After(i * SEND_DELAY, function() SendChat(line, chatType, nil, target) end)
  end
end

local function send()
  local lines, err = buildLines()
  if not lines then say(err) return end

  local where = R.where
  if where == "COPY" then
    showCopyWindow(lines)
    return
  end

  if where:find("^CHANNEL|") then
    local name = where:gsub(".*|", "")
    if name == "Trade" then name = "Trade - City" end
    local id = GetChannelName(name)
    sendLines(lines, "CHANNEL", id)

  elseif where:find("^REALID|") then
    local id = tonumber((where:gsub(".*|", "")))
    for i, line in ipairs(lines) do
      C_Timer.After(i * SEND_DELAY, function() BNSendWhisper(id, line) end)
    end

  elseif where == "WHISPER" then
    if not R.toWho or R.toWho == "" then say("Whisper target not found") return end
    sendLines(lines, "WHISPER", R.toWho)

  elseif where == "WHISPER2" then
    if not (UnitExists("target") and UnitIsPlayer("target")) then say("Whisper target not found") return end
    local name, realm = UnitName("target")
    if realm and realm ~= "" then name = name .. "-" .. realm end
    sendLines(lines, "WHISPER", name)

  else
    if (where == "RAID" or where == "PARTY") and LE_PARTY_CATEGORY_INSTANCE
      and GetNumGroupMembers(LE_PARTY_CATEGORY_INSTANCE) > 0 then
      where = "INSTANCE_CHAT"
    end
    sendLines(lines, where)
  end
end

---------------------------------------------------------------------------
-- channel dropdown
---------------------------------------------------------------------------

local function setIcon(tex, c)
  tex:SetTexture(c.icon)
  tex:SetTexCoord(unpack(c.coords))
  tex:SetVertexColor(unpack(c.color))
end

local function updateDropdown()
  local dd = win.dropdown
  for _, c in ipairs(channelList()) do
    if c.value == R.where then
      setIcon(dd.icon, c)
      dd.text:SetText(c.label)
      return
    end
  end
  dd.text:SetText(R.where)
end

local LIST_MAX, ITEM_H = 12, 18

local function openList()
  if not ddList then
    ddList = CreateFrame("Frame", nil, win, "BackdropTemplate")
    ddList:SetFrameStrata("FULLSCREEN_DIALOG")
    ddList:SetClampedToScreen(true)
    ddList:EnableMouseWheel(true)
    ddList:SetBackdrop({ bgFile = [[Interface\Buttons\WHITE8X8]], edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1 })
    ddList:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
    ddList:SetBackdropBorderColor(0, 0, 0, 1)
    ddList.items, ddList.offset = {}, 0
    function ddList:render()
      for i = 1, LIST_MAX do
        local item = self.items[i]
        if not item then
          item = CreateFrame("Button", nil, self)
          item:SetHeight(ITEM_H)
          item:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ITEM_H)
          item:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * ITEM_H)
          local hl = item:CreateTexture(nil, "HIGHLIGHT")
          hl:SetAllPoints() hl:SetColorTexture(1, 1, 1, 0.12)
          item.icon = item:CreateTexture(nil, "ARTWORK")
          item.icon:SetSize(16, 16)
          item.icon:SetPoint("LEFT", 2, 0)
          item.text = smallText(item, 10)
          item.text:SetPoint("LEFT", item.icon, "RIGHT", 4, 0)
          item.text:SetPoint("RIGHT", -2, 0)
          item.text:SetJustifyH("LEFT")
          item.text:SetWordWrap(false)
          item:SetScript("OnClick", function(btn)
            R.where = btn.value
            ddList:Hide()
            updateDropdown()
          end)
          self.items[i] = item
        end
        local c = self.options[i + self.offset]
        if c then
          item.value = c.value
          setIcon(item.icon, c)
          item.text:SetText(c.label)
          item:Show()
        else
          item:Hide()
        end
      end
      self:SetHeight(math.min(#self.options, LIST_MAX) * ITEM_H + 4)
    end
    ddList:SetScript("OnMouseWheel", function(self, delta)
      local maxOffset = math.max(0, #self.options - LIST_MAX)
      self.offset = math.max(0, math.min(maxOffset, self.offset - delta))
      self:render()
    end)
  end
  ddList.options, ddList.offset = channelList(), 0
  ddList:ClearAllPoints()
  ddList:SetPoint("TOPLEFT", win.dropdown, "BOTTOMLEFT", 0, -1)
  ddList:SetWidth(win.dropdown:GetWidth())
  ddList:render()
  ddList:Show()
end

---------------------------------------------------------------------------
-- the window (Details' report window, default skin)
---------------------------------------------------------------------------

local function savePos()
  local x, y = win:GetCenter()
  local ux, uy = UIParent:GetCenter()
  R.pos = { x - ux, y - uy }
end

local function build()
  win = CreateFrame("Frame", "MySpellsReportWindow", UIParent, "BackdropTemplate")
  tinsert(UISpecialFrames, "MySpellsReportWindow")
  win:SetSize(342 / 2 + 5, 195)
  win:SetFrameStrata("DIALOG")
  win:SetClampedToScreen(true)
  win:EnableMouse(true)
  win:SetMovable(true)
  win:SetPoint("CENTER", UIParent, "CENTER", R.pos and R.pos[1] or 0, R.pos and R.pos[2] or 0)
  win:SetBackdrop({ bgFile = [[Interface\Buttons\WHITE8X8]], edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1 })
  win:SetBackdropColor(0.0549, 0.0549, 0.0549, 0.934) -- Details' frame background color
  win:SetBackdropBorderColor(0, 0, 0, 1)

  -- left drag moves, right click closes (like Details)
  win:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
      self:StartMoving() self.moving = true
    elseif button == "RightButton" then
      if self.moving then self:StopMovingOrSizing() savePos() self.moving = false end
      self:Hide()
    end
  end)
  win:SetScript("OnMouseUp", function(self)
    if self.moving then self:StopMovingOrSizing() savePos() self.moving = false end
  end)

  -- white flash when the window opens
  local flash = win:CreateTexture(nil, "BACKGROUND", nil, -8)
  flash:SetColorTexture(1, 1, 1)
  flash:SetPoint("TOPLEFT", -2, 2)
  flash:SetPoint("BOTTOMRIGHT", 2, -2)
  flash:SetAlpha(0)
  local anim = flash:CreateAnimationGroup()
  local a1 = anim:CreateAnimation("Alpha")
  a1:SetFromAlpha(0) a1:SetToAlpha(0.9) a1:SetDuration(0.4) a1:SetOrder(1)
  local a2 = anim:CreateAnimation("Alpha")
  a2:SetFromAlpha(0.9) a2:SetToAlpha(0) a2:SetDuration(0.4) a2:SetOrder(2)
  win.flash = anim

  -- title
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
  title:SetPoint("TOP", win, "TOP", 0, -7)
  title:SetText("Link MySpells!")
  title:SetTextColor(0.8, 0.8, 0.8, 1)

  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -3)
  if close:GetNormalTexture() then close:GetNormalTexture():SetDesaturated(true) end
  close:SetScript("OnClick", function() win:Hide() end)

  -- channel dropdown
  local dd = CreateFrame("Button", nil, win, "BackdropTemplate")
  dd:SetSize(155, 20)
  dd:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -30)
  darkBox(dd, 0.1)
  local ddHl = dd:CreateTexture(nil, "HIGHLIGHT")
  ddHl:SetPoint("TOPLEFT", 1, -1) ddHl:SetPoint("BOTTOMRIGHT", -1, 1)
  ddHl:SetColorTexture(1, 1, 1, 0.08)
  dd.icon = dd:CreateTexture(nil, "ARTWORK")
  dd.icon:SetSize(16, 16)
  dd.icon:SetPoint("LEFT", 3, 0)
  dd.arrow = dd:CreateTexture(nil, "ARTWORK")
  dd.arrow:SetSize(18, 18)
  dd.arrow:SetPoint("RIGHT", -1, 0)
  dd.arrow:SetTexture([[Interface\Buttons\UI-ScrollBar-ScrollDownButton-Up]])
  dd.text = smallText(dd, 10)
  dd.text:SetPoint("LEFT", dd.icon, "RIGHT", 3, 0)
  dd.text:SetPoint("RIGHT", dd.arrow, "LEFT", -2, 0)
  dd.text:SetJustifyH("LEFT")
  dd.text:SetWordWrap(false)
  dd:SetScript("OnClick", function()
    if ddList and ddList:IsShown() then ddList:Hide() else openList() end
  end)
  win.dropdown = dd

  -- whisper name
  local wLabel = smallText(win, 10)
  wLabel:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -10)
  wLabel:SetText("Whisper:")
  local edit = CreateFrame("EditBox", nil, win, "BackdropTemplate")
  edit:SetSize(155, 20)
  edit:SetPoint("TOPLEFT", wLabel, "BOTTOMLEFT", 0, -3)
  darkBox(edit, 0.3)
  edit:SetAutoFocus(false)
  edit:SetFontObject("GameFontHighlightSmall")
  edit:SetJustifyH("CENTER")
  edit:SetTextInsets(4, 4, 0, 0)
  edit:SetText(R.toWho or "")
  local function saveName()
    local text = strtrim(edit:GetText() or "")
    if text == INSERT_NAME then text = "" end
    R.toWho = text
    edit:SetText(text)
  end
  edit:SetScript("OnEnterPressed", function(self) saveName() self:ClearFocus() end)
  edit:SetScript("OnEscapePressed", function(self) self:SetText("") R.toWho = "" self:ClearFocus() end)
  edit:SetScript("OnEditFocusLost", saveName)
  edit:SetScript("OnEditFocusGained", function(self)
    if self:GetText() == INSERT_NAME then self:SetText("") end
    self:HighlightText()
  end)
  edit:SetScript("OnEnter", function(self)
    if self:GetText() == "" and not self:HasFocus() then self:SetText(INSERT_NAME) end
  end)
  edit:SetScript("OnLeave", function(self)
    if not self:HasFocus() and self:GetText() == INSERT_NAME then self:SetText("") end
  end)

  -- lines slider (1-25), the number sits on the thumb
  local lLabel = smallText(win, 10)
  lLabel:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -10)
  lLabel:SetText("Lines")
  lLabel:SetTextColor(0.9, 0.9, 0.9, 1)
  local slider = CreateFrame("Slider", nil, win, "BackdropTemplate")
  slider:SetSize(155, 20)
  slider:SetPoint("TOPLEFT", lLabel, "BOTTOMLEFT", 0, -3)
  darkBox(slider, 0.3)
  slider:SetOrientation("HORIZONTAL")
  slider.thumb = slider:CreateTexture(nil, "ARTWORK")
  local hasIcons = slider.thumb:SetTexture(DETAILS .. "images\\icons2") ~= false
  if hasIcons then
    slider.thumb:SetTexCoord(482 / 512, 492 / 512, 104 / 512, 120 / 512)
  else
    slider.thumb:SetColorTexture(0.6, 0.6, 0.6, 0.95)
  end
  slider.thumb:SetSize(16, 16)
  slider.thumb:SetVertexColor(0.6, 0.6, 0.6, 0.95)
  slider:SetThumbTexture(slider.thumb)
  slider:SetMinMaxValues(1, 25)
  slider:SetValueStep(1)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  slider.amt = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  slider.amt:SetTextColor(0.8, 0.8, 0.8, 1)
  slider.amt:SetPoint("CENTER", slider.thumb, "CENTER")
  slider:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v + 0.5)
    R.lines = v
    self.amt:SetText(v < 10 and ("0" .. v) or v)
  end)
  slider:EnableMouseWheel(true)
  slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta) end)
  slider:SetValue(R.lines)
  slider.amt:SetText(R.lines < 10 and ("0" .. R.lines) or R.lines)

  -- reverse
  local rev = CreateFrame("CheckButton", nil, win, "BackdropTemplate")
  rev:SetSize(14, 14)
  rev:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -8)
  darkBox(rev, 0.3)
  rev:SetCheckedTexture([[Interface\Buttons\UI-CheckBox-Check]])
  rev:SetHitRectInsets(0, -45, 0, 0)
  local revText = smallText(win, 10)
  revText:SetPoint("LEFT", rev, "RIGHT", 2, 0)
  revText:SetText("Reverse")
  rev:SetChecked(R.reverse)
  rev:SetScript("OnClick", function(self) R.reverse = self:GetChecked() and true or false end)
  rev:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("send in ascending order.")
    GameTooltip:Show()
  end)
  rev:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- send (nudges down a pixel while pressed, like Details)
  local sendBtn = CreateFrame("Button", nil, win, "BackdropTemplate")
  sendBtn:SetSize(342 / 2 - 15, 20)
  sendBtn:SetPoint("BOTTOM", win, "BOTTOM", 0, 10)
  darkBox(sendBtn, 0.3)
  local sHl = sendBtn:CreateTexture(nil, "HIGHLIGHT")
  sHl:SetPoint("TOPLEFT", 1, -1) sHl:SetPoint("BOTTOMRIGHT", -1, 1)
  sHl:SetColorTexture(1, 1, 1, 0.08)
  local sText = sendBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  sText:SetPoint("CENTER")
  sText:SetText("Send")
  sendBtn:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then sText:SetPoint("CENTER", 1, -1) end
  end)
  sendBtn:SetScript("OnMouseUp", function() sText:SetPoint("CENTER", 0, 0) end)
  sendBtn:SetScript("OnClick", function()
    saveName()
    send()
  end)

  win:SetScript("OnShow", function()
    R.where = validChannel(R.where)
    updateDropdown()
    win.flash:Stop()
    win.flash:Play()
  end)
  win:SetScript("OnHide", function()
    if ddList then ddList:Hide() end
  end)
  win:Hide()
end

-- the report button on the title bar opens and closes the window
function ns.reportShown()
  return win and win:IsShown()
end

function ns.toggleReport()
  R = ns.db.report
  if not win then build() end
  win:SetShown(not win:IsShown())
end
