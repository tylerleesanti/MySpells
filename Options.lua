-- MySpells options: the menu behind the gear icon in the title bar.
-- Two tabs, modeled on Details' options:
--   Bars      - window background and right-click, bar text (font, size, outline, color, shadow),
--               left/right text, bar height and spacing
--   Title Bar - the same text options for the title, plus show total, background,
--               bar height, icon size/spacing and hover-only icons
-- Every change applies to the window right away.

local ADDON, ns = ...

local PANEL_W, TITLE_H, TAB_H, ROW = 270, 20, 22, 24
local LABEL_X, CTRL_X = 12, 100
local CTRL_W = PANEL_W - CTRL_X - 12
local COL2_X = 140

local panel, list
local pages, tabs = {}, {}
local controls = {}

-- where a setting lives and what to call after changing it
-- the menu's own title bar follows your Title Bar background color
local function recolor()
  if panel and panel.titleBg then panel.titleBg:SetColorTexture(ns.titleBarColor()) end
end

local TEXT = { get = function() return ns.db.text end, apply = function() ns.applyText() recolor() end }
local BARS = { get = function() return ns.db.bars end, apply = function() ns.applyBars() end }
local MINIMAP = { get = function() return ns.db.minimap end, apply = function() ns.applyMinimapButton() end }

---------------------------------------------------------------------------
-- small style helpers
---------------------------------------------------------------------------

local function fill(f, r, g, b, a, layer)
  local t = f:CreateTexture(nil, layer or "BACKGROUND")
  t:SetAllPoints()
  t:SetColorTexture(r, g, b, a)
  return t
end

local function outline(f, r, g, b, a)
  local function line(p1, p2, w, h)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(r or 0.3, g or 0.3, b or 0.3, a or 1)
    t:SetPoint(p1) t:SetPoint(p2)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
  end
  line("TOPLEFT", "TOPRIGHT", nil, 1)
  line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  line("TOPLEFT", "BOTTOMLEFT", 1, nil)
  line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

local function setMenuFont(fs, size)
  if fs:SetFont(ns.fontPath("Accidental Presidency"), size or 14, "") == false then
    fs:SetFontObject("GameFontHighlight")
  end
end

-- menu text uses Details' font when available
local function menuText(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  setMenuFont(fs, size)
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
  fs:SetTextColor(r or 1, g or 1, b or 1)
  return fs
end

local function label(page, y, text, x)
  local fs = menuText(page, 14, 0.85, 0.85, 0.85)
  fs:SetPoint("TOPLEFT", page, "TOPLEFT", x or LABEL_X, y - 2)
  fs:SetText(text)
  return fs
end

local function section(page, y, text)
  local fs = menuText(page, 15, 1, 0.82, 0)
  fs:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_X - 4, y)
  fs:SetText(text)
  local line = page:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 0.82, 0, 0.25)
  line:SetHeight(1)
  line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
  line:SetPoint("RIGHT", page, "RIGHT", -10, 0)
  return y - 20
end

local function button(page, y, text, onClick)
  local b = CreateFrame("Button", nil, page)
  b:SetSize(PANEL_W - 2 * LABEL_X, 20)
  b:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_X, y)
  fill(b, 0, 0, 0, 0.5)
  fill(b, 1, 1, 1, 0.08, "HIGHLIGHT")
  outline(b)
  local fs = menuText(b, 14)
  fs:SetPoint("CENTER")
  fs:SetText(text)
  b:SetScript("OnClick", onClick)
  return y - 20
end

---------------------------------------------------------------------------
-- dropdown list (one shared list for every dropdown)
---------------------------------------------------------------------------

local MAX_VISIBLE, ITEM_H = 12, 18

local function getList()
  if list then return list end
  list = CreateFrame("Frame", nil, panel)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetClampedToScreen(true)
  list:EnableMouse(true)
  list:EnableMouseWheel(true)
  fill(list, 0.06, 0.06, 0.07, 0.97)
  outline(list, 0.35, 0.35, 0.35, 1)
  list.items, list.offset, list.options = {}, 0, {}

  local function maxOffset() return math.max(0, #list.options - MAX_VISIBLE) end

  function list:render()
    for i = 1, MAX_VISIBLE do
      local item = self.items[i]
      if not item then
        item = CreateFrame("Button", nil, self)
        item:SetHeight(ITEM_H)
        item:SetPoint("TOPLEFT", self, "TOPLEFT", 2, -2 - (i - 1) * ITEM_H)
        item:SetPoint("TOPRIGHT", self, "TOPRIGHT", -2, -2 - (i - 1) * ITEM_H)
        fill(item, 1, 1, 1, 0.12, "HIGHLIGHT")
        item.text = menuText(item, 14)
        item.text:SetPoint("LEFT", item, "LEFT", 6, 0)
        item.text:SetPoint("RIGHT", item, "RIGHT", -16, 0)
        item.text:SetJustifyH("LEFT")
        item.text:SetWordWrap(false)
        item.check = menuText(item, 14, 1, 0.82, 0)
        item.check:SetPoint("RIGHT", item, "RIGHT", -4, 0)
        item:SetScript("OnClick", function(btn)
          list:Hide()
          if list.onPick then list.onPick(btn.value) end
        end)
        self.items[i] = item
      end
      local opt = self.options[i + self.offset]
      if opt then
        item.value = opt.value
        item.text:SetText(opt.text)
        -- font list: show each name in its own font
        if not (self.preview and item.text:SetFont(ns.fontPath(opt.value), 14, "") ~= false) then
          setMenuFont(item.text, 14)
        end
        item.check:SetText(opt.value == self.current and "*" or "")
        item:Show()
      else
        item:Hide()
      end
    end
    self:SetHeight(math.min(#self.options, MAX_VISIBLE) * ITEM_H + 4)
  end

  list:SetScript("OnMouseWheel", function(self, delta)
    self.offset = math.max(0, math.min(maxOffset(), self.offset - delta))
    self:render()
  end)

  function list:open(owner, options, current, onPick, preview)
    self.owner, self.options, self.current, self.onPick, self.preview = owner, options, current, onPick, preview
    -- scroll so the current choice is visible
    local index = 1
    for i, o in ipairs(options) do if o.value == current then index = i end end
    self.offset = math.max(0, math.min(maxOffset(), index - math.floor(MAX_VISIBLE / 2)))
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -1)
    self:SetWidth(owner:GetWidth())
    self:render()
    self:Show()
  end

  list:Hide()
  return list
end

---------------------------------------------------------------------------
-- controls: each takes the page, a y position, a label, a store (TEXT/BARS) and a key
---------------------------------------------------------------------------

local function dropdown(page, y, text, getOptions, store, key, preview)
  label(page, y, text)
  local b = CreateFrame("Button", nil, page)
  b:SetSize(CTRL_W, 18)
  b:SetPoint("TOPLEFT", page, "TOPLEFT", CTRL_X, y)
  fill(b, 0, 0, 0, 0.5)
  fill(b, 1, 1, 1, 0.06, "HIGHLIGHT")
  outline(b)
  b.text = menuText(b, 14)
  b.text:SetPoint("LEFT", b, "LEFT", 5, 0)
  b.text:SetPoint("RIGHT", b, "RIGHT", -16, 0)
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(false)
  local arrow = menuText(b, 14, 0.7, 0.7, 0.7)
  arrow:SetPoint("RIGHT", b, "RIGHT", -5, 0)
  arrow:SetText("v")

  function b:update()
    local cur = store.get()[key]
    local shown = cur
    for _, o in ipairs(getOptions()) do if o.value == cur then shown = o.text end end
    self.text:SetText(shown)
    if not (preview and self.text:SetFont(ns.fontPath(cur), 14, "") ~= false) then
      setMenuFont(self.text, 14)
    end
  end

  b:SetScript("OnClick", function(self)
    local l = getList()
    if l:IsShown() and l.owner == self then l:Hide() return end
    l:open(self, getOptions(), store.get()[key], function(value)
      store.get()[key] = value
      store.apply()
      self:update()
    end, preview)
  end)

  controls[#controls + 1] = b
  return y - ROW
end

local function slider(page, y, text, minV, maxV, store, key)
  label(page, y, text)
  local s = CreateFrame("Slider", nil, page)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(CTRL_W - 34, 16)
  s:SetPoint("TOPLEFT", page, "TOPLEFT", CTRL_X, y - 1)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(0, 0, 0, 0.6)
  track:SetHeight(6)
  track:SetPoint("LEFT", s, "LEFT", 0, 0)
  track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(1)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:EnableMouseWheel(true)

  s.valueText = menuText(page, 14)
  s.valueText:SetPoint("LEFT", s, "RIGHT", 8, 0)

  s:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta) end)
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v + 0.5)
    self.valueText:SetText(v)
    if self.updating or v == store.get()[key] then return end
    store.get()[key] = v
    store.apply()
  end)

  function s:update()
    self.updating = true
    self:SetValue(store.get()[key])
    self.valueText:SetText(store.get()[key])
    self.updating = false
  end

  controls[#controls + 1] = s
  return y - ROW
end

local function checkbox(page, y, text, store, key, x)
  local cb = CreateFrame("CheckButton", nil, page)
  cb:SetSize(20, 20)
  cb:SetPoint("TOPLEFT", page, "TOPLEFT", (x or LABEL_X) - 3, y + 1)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  local fs = menuText(page, 14, 0.85, 0.85, 0.85)
  fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  fs:SetText(text)
  cb:SetScript("OnClick", function(self)
    store.get()[key] = self:GetChecked() and true or false
    store.apply()
  end)
  function cb:update() self:SetChecked(store.get()[key]) end
  controls[#controls + 1] = cb
  return cb
end

local function updateAll()
  for _, c in ipairs(controls) do c:update() end
end

-- opacity from the color picker (newer and older game versions differ)
local function pickerAlpha()
  if ColorPickerFrame.GetColorAlpha then return ColorPickerFrame:GetColorAlpha() end
  if OpacitySliderFrame then return 1 - OpacitySliderFrame:GetValue() end
  return 1
end

-- withAlpha: the color also has an opacity (4th value)
local function openColorPicker(store, key, withAlpha)
  local r, g, b, a = unpack(store.get()[key])
  a = a or 1
  local function set(nr, ng, nb, na)
    store.get()[key] = withAlpha and { nr, ng, nb, na } or { nr, ng, nb }
    store.apply()
    updateAll()
  end
  local function apply()
    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
    set(nr, ng, nb, withAlpha and pickerAlpha() or nil)
  end
  local function cancel() set(r, g, b, a) end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({
      r = r, g = g, b = b, opacity = a, hasOpacity = withAlpha and true or false,
      swatchFunc = apply, opacityFunc = apply, cancelFunc = cancel,
    })
  else
    ColorPickerFrame:Hide()
    ColorPickerFrame.hasOpacity = withAlpha and true or false
    ColorPickerFrame.opacity = 1 - a -- older versions store transparency
    ColorPickerFrame.previousValues = { r, g, b, 1 - a }
    ColorPickerFrame.func = apply
    ColorPickerFrame.opacityFunc = apply
    ColorPickerFrame.cancelFunc = cancel
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Show()
  end
end

local function colorSwatch(page, y, text, store, key, withAlpha)
  label(page, y, text)
  local b = CreateFrame("Button", nil, page)
  b:SetSize(18, 18)
  b:SetPoint("TOPLEFT", page, "TOPLEFT", CTRL_X, y)
  outline(b, 0.6, 0.6, 0.6, 1)
  -- light backing so a see-through color is visible as see-through
  local back = b:CreateTexture(nil, "BACKGROUND")
  back:SetPoint("TOPLEFT", 1, -1)
  back:SetPoint("BOTTOMRIGHT", -1, 1)
  back:SetColorTexture(0.8, 0.8, 0.8, 1)
  b.swatch = b:CreateTexture(nil, "ARTWORK")
  b.swatch:SetPoint("TOPLEFT", 1, -1)
  b.swatch:SetPoint("BOTTOMRIGHT", -1, 1)
  b:SetScript("OnClick", function() openColorPicker(store, key, withAlpha) end)
  function b:update()
    local c = store.get()[key]
    self.swatch:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  end
  controls[#controls + 1] = b
  return b
end

---------------------------------------------------------------------------
-- option lists
---------------------------------------------------------------------------

local function fontOptions()
  local o = {}
  for _, name in ipairs(ns.fontList()) do o[#o + 1] = { value = name, text = name } end
  return o
end

local OUTLINES = {
  { value = "NONE", text = "None" },
  { value = "OUTLINE", text = "Outline" },
  { value = "THICKOUTLINE", text = "Thick Outline" },
}
local BRACKETS = {
  { value = "NONE", text = "None" },
  { value = "(", text = "( )" },
  { value = "[", text = "[ ]" },
  { value = "{", text = "{ }" },
  { value = "<", text = "< >" },
}
local SEPARATORS = {
  { value = ",", text = "," },
  { value = "/", text = "/" },
  { value = "-", text = "-" },
  { value = ";", text = ";" },
  { value = " ", text = "Space" },
}

local function fixed(t) return function() return t end end

-- reset one tab's settings back to the defaults (title keys start with "title")
local function resetTab(forTitle)
  local text = ns.db.text
  for k, v in pairs(ns.DEFAULTS.text) do
    if (k:sub(1, 5) == "title") == forTitle then text[k] = ns.copy(v) end
  end
  if not forTitle then
    for k, v in pairs(ns.DEFAULTS.bars) do ns.db.bars[k] = v end
    ns.applyBars()
  end
  ns.applyText()
  recolor()
  updateAll()
end

---------------------------------------------------------------------------
-- the two pages
---------------------------------------------------------------------------

local function newPage()
  local page = CreateFrame("Frame", nil, panel)
  page:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(TITLE_H + TAB_H))
  page:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(TITLE_H + TAB_H))
  page:Hide()
  return page
end

local function buildBarsPage()
  local p = newPage()
  local y = -8

  y = section(p, y, "Window")
  colorSwatch(p, y, "Background", TEXT, "windowBgColor", true)
  local hint = menuText(p, 13, 0.6, 0.6, 0.6)
  hint:SetPoint("TOPLEFT", p, "TOPLEFT", CTRL_X + 26, y - 3)
  hint:SetText("color and opacity")
  y = y - ROW
  checkbox(p, y, "Right-click window to change mode", TEXT, "rightClickModes")
  y = y - ROW
  checkbox(p, y, "Show minimap button", MINIMAP, "show")
  y = y - ROW - 4

  y = section(p, y, "Bar Text")
  y = dropdown(p, y, "Text Font", fontOptions, TEXT, "font", true)
  y = slider(p, y, "Text Size", 8, 32, TEXT, "size")
  y = dropdown(p, y, "Text Outline", fixed(OUTLINES), TEXT, "outline")
  colorSwatch(p, y, "Text Color", TEXT, "color")
  checkbox(p, y, "Class Color", TEXT, "classColor", CTRL_X + 30)
  y = y - ROW
  checkbox(p, y, "Text Shadow", TEXT, "shadow")
  y = y - ROW - 4

  y = section(p, y, "Left Text")
  checkbox(p, y, "Show Number", TEXT, "showNumber")
  y = y - ROW - 4

  y = section(p, y, "Right Text")
  checkbox(p, y, "Show Total", TEXT, "showTotal")
  checkbox(p, y, "Show Per Second", TEXT, "showPerSecond", COL2_X)
  y = y - ROW
  checkbox(p, y, "Show Percent", TEXT, "showPercent")
  y = y - ROW
  y = dropdown(p, y, "Bracket", fixed(BRACKETS), TEXT, "bracket")
  y = dropdown(p, y, "Separator", fixed(SEPARATORS), TEXT, "separator")
  y = slider(p, y, "PS Decimals", 0, 3, TEXT, "psDecimals")
  y = y - 4

  y = section(p, y, "Bars")
  y = slider(p, y, "Bar Height", 12, 40, BARS, "height")
  y = slider(p, y, "Bar Spacing", 0, 10, BARS, "spacing")
  y = y - 6

  y = button(p, y, "Reset Bars Tab", function() resetTab(false) end)
  p.height = -y + 10
  p:SetHeight(p.height) -- a frame with no height draws none of its contents
  return p
end

local function buildTitlePage()
  local p = newPage()
  local y = -8

  y = section(p, y, "Title Text")
  y = dropdown(p, y, "Text Font", fontOptions, TEXT, "titleFont", true)
  y = slider(p, y, "Text Size", 8, 32, TEXT, "titleSize")
  y = dropdown(p, y, "Text Outline", fixed(OUTLINES), TEXT, "titleOutline")
  colorSwatch(p, y, "Text Color", TEXT, "titleColor")
  checkbox(p, y, "Class Color", TEXT, "titleClassColor", CTRL_X + 30)
  y = y - ROW
  checkbox(p, y, "Text Shadow", TEXT, "titleShadow")
  checkbox(p, y, "Show Total", TEXT, "titleShowTotal", COL2_X)
  y = y - ROW - 4

  y = section(p, y, "Title Bar")
  colorSwatch(p, y, "Background", TEXT, "titleBgColor", true)
  local hint = menuText(p, 13, 0.6, 0.6, 0.6)
  hint:SetPoint("TOPLEFT", p, "TOPLEFT", CTRL_X + 26, y - 3)
  hint:SetText("color and opacity")
  y = y - ROW
  y = slider(p, y, "Bar Height", 14, 32, TEXT, "titleHeight")
  y = slider(p, y, "Icon Size", 10, 20, TEXT, "titleIconSize")
  y = slider(p, y, "Icon Spacing", 0, 10, TEXT, "titleIconSpacing")
  checkbox(p, y, "Icons + resize corner only on hover", TEXT, "titleIconsHover")
  y = y - ROW
  y = y - 6

  y = button(p, y, "Reset Title Bar Tab", function() resetTab(true) end)
  p.height = -y + 10
  p:SetHeight(p.height) -- a frame with no height draws none of its contents
  return p
end

---------------------------------------------------------------------------
-- the panel and its tabs
---------------------------------------------------------------------------

local function selectTab(index)
  if list then list:Hide() end
  for i, page in ipairs(pages) do
    page:SetShown(i == index)
    local tab = tabs[i]
    tab.bg:SetColorTexture(1, 1, 1, i == index and 0.1 or 0.03)
    tab.text:SetTextColor(i == index and 1 or 0.6, i == index and 0.82 or 0.6, i == index and 0 or 0.6)
    tab.line:SetShown(i == index)
  end
  panel.tab = index
  panel:SetHeight(TITLE_H + TAB_H + pages[index].height)
end

local function createTab(index, text, count)
  local w = PANEL_W / count
  local tab = CreateFrame("Button", nil, panel)
  tab:SetSize(w, TAB_H)
  tab:SetPoint("TOPLEFT", panel, "TOPLEFT", (index - 1) * w, -TITLE_H)
  tab.bg = fill(tab, 1, 1, 1, 0.03)
  fill(tab, 1, 1, 1, 0.06, "HIGHLIGHT")
  tab.text = menuText(tab, 15)
  tab.text:SetPoint("CENTER", 0, 0)
  tab.text:SetText(text)
  tab.line = tab:CreateTexture(nil, "ARTWORK")
  tab.line:SetColorTexture(1, 0.82, 0, 0.8)
  tab.line:SetHeight(2)
  tab.line:SetPoint("BOTTOMLEFT") tab.line:SetPoint("BOTTOMRIGHT")
  tab:SetScript("OnClick", function() selectTab(index) end)
  tabs[index] = tab
end

local function build()
  panel = CreateFrame("Frame", "MySpellsOptionsFrame", UIParent)
  panel:SetFrameStrata("HIGH")
  panel:SetWidth(PANEL_W)
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:Hide()
  tinsert(UISpecialFrames, "MySpellsOptionsFrame") -- Escape closes it

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 0, -TITLE_H)
  bg:SetPoint("BOTTOMRIGHT")
  bg:SetColorTexture(0.09, 0.09, 0.1, 0.96)
  outline(panel, 0, 0, 0, 1)

  -- title bar, same look as the window's
  local bar = CreateFrame("Frame", nil, panel)
  bar:SetPoint("TOPLEFT") bar:SetPoint("TOPRIGHT")
  bar:SetHeight(TITLE_H)
  panel.titleBg = fill(bar, ns.titleBarColor()) -- your title bar color; kept in step by recolor()
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() panel:StartMoving() end)
  bar:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
  local title = menuText(bar, 14)
  title:SetPoint("LEFT", bar, "LEFT", 6, 0)
  title:SetText("MySpells |cffaaaaaaOptions|r")

  local close = CreateFrame("Button", nil, bar)
  close:SetSize(TITLE_H, TITLE_H)
  close:SetPoint("RIGHT")
  local x = menuText(close, 16, 0.7, 0.7, 0.7)
  x:SetPoint("CENTER", 0, 1)
  x:SetText("x")
  close:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1) end)
  close:SetScript("OnLeave", function() x:SetTextColor(0.7, 0.7, 0.7) end)
  close:SetScript("OnClick", function() panel:Hide() end)

  pages[1] = buildBarsPage()
  pages[2] = buildTitlePage()
  createTab(1, "Bars", 2)
  createTab(2, "Title Bar", 2)

  panel:SetScript("OnHide", function() if list then list:Hide() end end)
  selectTab(1)
end

-- place the menu beside the window, on whichever side has room
local function position()
  local win = ns.frame
  panel:ClearAllPoints()
  if win and win:GetRight() and (win:GetRight() + PANEL_W + 4) < UIParent:GetRight() then
    panel:SetPoint("TOPLEFT", win, "TOPRIGHT", 4, 0)
  elseif win and win:GetLeft() then
    panel:SetPoint("TOPRIGHT", win, "TOPLEFT", -4, 0)
  else
    panel:SetPoint("CENTER")
  end
end

function ns.toggleOptions()
  if not panel then build() end
  if panel:IsShown() then
    panel:Hide()
  else
    position()
    updateAll()
    recolor()
    panel:Show()
  end
end

function ns.hideOptions()
  if panel then panel:Hide() end
end

function ns.optionsShown()
  return panel and panel:IsShown()
end
