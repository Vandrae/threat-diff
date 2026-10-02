--[[ ThreatDiff - UI kit.

  One flat, dark theme for every ThreatDiff window, plus the widgets the
  settings are built from: switches, sliders, dropdowns, segmented buttons,
  number boxes and colour swatches, laid out as cards of labelled rows.

  Every widget registers a refresh function, so the whole window re-syncs
  from the active profile after any change (or a profile switch).
]]

local _, ns = ...
local TD = ns.TD
local UI = {}
ns.UI = UI

local floor, max, min, format = math.floor, math.max, math.min, string.format
local type, tonumber, ipairs = type, tonumber, ipairs

local WHITE = "Interface\\Buttons\\WHITE8x8"
UI.WHITE = WHITE

local function Font() return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end

UI.C = {
  bg       = { 0.047, 0.055, 0.071, 0.97 },
  side     = { 0.031, 0.035, 0.047, 1 },
  card     = { 0.078, 0.090, 0.114, 1 },
  cardEdge = { 0.150, 0.170, 0.210, 1 },
  edge     = { 0.215, 0.245, 0.300, 1 },
  control  = { 0.120, 0.137, 0.172, 1 },
  hover    = { 0.170, 0.195, 0.245, 1 },
  text     = { 0.930, 0.940, 0.960 },
  dim      = { 0.580, 0.620, 0.690 },
  accent   = { 0.310, 0.760, 0.970, 1 },
  accentBg = { 0.110, 0.330, 0.450, 1 },
  danger   = { 0.900, 0.330, 0.330, 1 },
  dangerBg = { 0.380, 0.110, 0.110, 1 },
}
local C = UI.C

-------------------------------------------------------------------------------
-- Refresh registry
-------------------------------------------------------------------------------
local refreshers = {}
function UI.OnRefresh(fn) refreshers[#refreshers + 1] = fn; return fn end
function UI.RefreshAll() for i = 1, #refreshers do refreshers[i]() end end

-- After a setting changes: apply it everywhere (ApplySettings re-syncs the UI).
function UI.Changed() TD:ApplySettings() end

-------------------------------------------------------------------------------
-- Primitives
-------------------------------------------------------------------------------
function UI.Fill(parent, c, layer)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetAllPoints()
  t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  return t
end

function UI.SetFill(t, c) t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end

function UI.Border(f, c)
  local e = {}
  for i = 1, 4 do
    e[i] = f:CreateTexture(nil, "BORDER")
    e[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  end
  e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(1)
  e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(1)
  e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(1)
  e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(1)
  f.edges = e
  return e
end

function UI.SetBorder(f, c)
  for _, t in ipairs(f.edges) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

-- Text with a font set up front (the client errors on text without a font).
function UI.Text(parent, size, color, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontNormal")
  TD.ApplyFont(fs, Font(), size or 12, "")
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetShadowOffset(1, -1)
  local c = color or C.text
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetJustifyH("LEFT")
  return fs
end

function UI.Line(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetColorTexture(r, g, b, a)
  return t
end

function UI.Tooltip(frame, text, title)
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if title then
      GameTooltip:SetText(title, 1, 1, 1)
      GameTooltip:AddLine(text, 0.8, 0.84, 0.9, true)
    else
      GameTooltip:SetText(text, 1, 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Hover(f, normal, over, edgeN, edgeO)
  f:HookScript("OnEnter", function(self)
    if self.bg and not self.locked then UI.SetFill(self.bg, over) end
    if self.edges and edgeO then UI.SetBorder(self, edgeO) end
  end)
  f:HookScript("OnLeave", function(self)
    if self.bg and not self.locked then UI.SetFill(self.bg, normal) end
    if self.edges and edgeN then UI.SetBorder(self, edgeN) end
  end)
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------
-- style: nil (normal), "primary", "danger"
function UI.Button(parent, text, w, onClick, style)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 24)
  local base = (style == "primary" and C.accentBg) or (style == "danger" and C.dangerBg) or C.control
  local over = (style == "primary" and { 0.14, 0.42, 0.57, 1 }) or (style == "danger" and { 0.5, 0.15, 0.15, 1 }) or C.hover
  local edge = (style == "primary" and C.accent) or (style == "danger" and C.danger) or C.edge
  b.bg = UI.Fill(b, base)
  UI.Border(b, edge)
  b.label = UI.Text(b, 12)
  b.label:SetPoint("CENTER", 0, 0)
  b.label:SetJustifyH("CENTER")
  b.label:SetText(text)
  Hover(b, base, over)
  b:SetScript("OnClick", onClick)
  b.SetText = function(self, t) self.label:SetText(t) end
  b.GetText = function(self) return self.label:GetText() end
  return b
end

-- A clean "X" close button drawn with two thin lines.
function UI.CloseButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(22, 22)
  b.bg = UI.Fill(b, { 0, 0, 0, 0 })
  local l1 = UI.Line(b, "ARTWORK", 0.75, 0.78, 0.84, 1)
  local l2 = UI.Line(b, "ARTWORK", 0.75, 0.78, 0.84, 1)
  for _, l in ipairs({ l1, l2 }) do l:SetSize(12, 1.5); l:SetPoint("CENTER") end
  l1:SetRotation(math.pi / 4); l2:SetRotation(-math.pi / 4)
  Hover(b, { 0, 0, 0, 0 }, { 0.6, 0.15, 0.15, 0.9 })
  b:SetScript("OnClick", onClick or function() parent:Hide() end)
  return b
end

-------------------------------------------------------------------------------
-- Switch (on/off)
-------------------------------------------------------------------------------
function UI.Toggle(parent, get, set)
  local t = CreateFrame("Button", nil, parent)
  t:SetSize(40, 20)
  t.bg = UI.Fill(t, C.control)
  UI.Border(t, C.edge)
  t.knob = t:CreateTexture(nil, "ARTWORK")
  t.knob:SetSize(14, 14)
  t.state = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  TD.ApplyFont(t.state, Font(), 9, "")
  local function Refresh()
    local on = get() and true or false
    t.knob:ClearAllPoints()
    t.state:ClearAllPoints()
    if on then
      UI.SetFill(t.bg, C.accentBg); UI.SetBorder(t, C.accent)
      t.knob:SetPoint("RIGHT", -3, 0); t.knob:SetColorTexture(1, 1, 1, 1)
      t.state:SetPoint("LEFT", 6, 0); t.state:SetText("ON"); t.state:SetTextColor(0.85, 0.95, 1)
    else
      UI.SetFill(t.bg, C.control); UI.SetBorder(t, C.edge)
      t.knob:SetPoint("LEFT", 3, 0); t.knob:SetColorTexture(0.5, 0.54, 0.6, 1)
      t.state:SetPoint("RIGHT", -5, 0); t.state:SetText("OFF"); t.state:SetTextColor(0.55, 0.58, 0.64)
    end
  end
  t.locked = true -- colour comes from state, not hover
  t:SetScript("OnClick", function() set(not get()); UI.Changed(); Refresh() end)
  UI.OnRefresh(Refresh)
  return t
end

-------------------------------------------------------------------------------
-- Themed text box
-------------------------------------------------------------------------------
function UI.EditBox(parent, w)
  local eb = CreateFrame("EditBox", nil, parent)
  eb:SetSize(w, 22)
  eb:SetAutoFocus(false)
  TD.ApplyFont(eb, Font(), 12, "")
  eb:SetTextColor(C.text[1], C.text[2], C.text[3])
  if eb.SetTextInsets then eb:SetTextInsets(6, 6, 0, 0) end
  eb.bg = UI.Fill(eb, C.control)
  UI.Border(eb, C.edge)
  eb:SetScript("OnEditFocusGained", function(self) UI.SetBorder(self, C.accent); self:HighlightText() end)
  eb:SetScript("OnEditFocusLost", function(self) UI.SetBorder(self, C.edge); self:HighlightText(0, 0) end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return eb
end

local function StepMod(step)
  if IsControlKeyDown() then return step / 100 end
  if IsShiftKeyDown() then return step / 10 end
  return step
end
UI.StepMod = StepMod

-------------------------------------------------------------------------------
-- Slider with a value box you can also type into
-- opts: min, max, step, dec, suffix, scale (display multiplier), width
-------------------------------------------------------------------------------
function UI.Slider(parent, opts, get, set)
  local w = opts.width or 230
  local scale = opts.scale or 1
  local dec = opts.dec or 0
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 22)

  local s = CreateFrame("Slider", nil, f)
  s:SetOrientation("HORIZONTAL")
  s:SetPoint("LEFT", 0, 0)
  s:SetSize(w - 70, 18)
  s:SetMinMaxValues(opts.min, opts.max)
  s:SetValueStep(opts.step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:SetHitRectInsets(0, 0, -4, -4)
  local track = UI.Line(s, "BACKGROUND", C.control[1], C.control[2], C.control[3], 1)
  track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
  s:SetThumbTexture(WHITE)
  local thumb = s:GetThumbTexture()
  thumb:SetSize(10, 16)
  thumb:SetVertexColor(0.92, 0.95, 1, 1)
  local fill = UI.Line(s, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
  fill:SetPoint("LEFT", track, "LEFT")
  fill:SetPoint("RIGHT", thumb, "CENTER")
  fill:SetHeight(4)

  local box = UI.EditBox(f, 62)
  box:SetPoint("RIGHT", 0, 0)
  box:SetJustifyH("CENTER")

  local updating = false
  local function Show(v)
    local shown = v * scale
    box:SetText(format("%." .. dec .. "f", shown) .. (opts.suffix or ""))
  end
  local function Commit(v)
    if not v then return end
    v = max(opts.min, min(opts.max, v))
    local m = 10 ^ (dec + (scale ~= 1 and 2 or 0))
    v = floor(v * m + 0.5 + 1e-7) / m
    set(v)
    UI.Changed()
  end
  s:SetScript("OnValueChanged", function(_, v)
    if updating then return end
    Commit(v)
    Show(get())
  end)
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(_, d) Commit(get() + d * StepMod(opts.step)); f.Refresh() end)
  box:SetScript("OnEnterPressed", function(self)
    local n = tonumber((self:GetText() or ""):match("[-]?%d*%.?%d+"))
    if n then Commit(n / scale) end
    self:ClearFocus()
    f.Refresh()
  end)
  box:HookScript("OnEditFocusLost", function() f.Refresh() end)

  function f.Refresh()
    updating = true
    s:SetValue(get())
    updating = false
    if not box:HasFocus() then Show(get()) end
  end
  UI.OnRefresh(f.Refresh)
  f.slider, f.box = s, box
  return f
end

-------------------------------------------------------------------------------
-- Number box with - / + (Shift = x0.1, Ctrl = x0.01) for exact values
-------------------------------------------------------------------------------
function UI.NumberBox(parent, opts, get, set, hooks)
  local dec, step = opts.dec or 0, opts.step or 1
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize((opts.width or 70) + 44, 22)
  local eb = UI.EditBox(f, opts.width or 70)
  eb:SetPoint("LEFT")
  eb:SetJustifyH("CENTER")
  local fmt = "%." .. dec .. "f"
  local function Show() if not eb:HasFocus() then eb:SetText(format(fmt, get())) end end
  local function Commit(v)
    if v then
      if opts.min and v < opts.min then v = opts.min end
      if opts.max and v > opts.max then v = opts.max end
      local m = 10 ^ dec
      v = floor(v * m + 0.5 + 1e-7) / m
      set(v)
    end
    eb:ClearFocus()
    Show()
  end
  eb:SetScript("OnEnterPressed", function(self) Commit(tonumber(self:GetText())) end)
  eb:HookScript("OnEditFocusLost", Show)
  eb:EnableMouseWheel(true)
  eb:SetScript("OnMouseWheel", function(_, d) Commit(get() + d * StepMod(step)) end)
  local minus = UI.Button(f, "-", 20, function() Commit(get() - StepMod(step)) end)
  minus:SetHeight(22)
  minus:SetPoint("LEFT", eb, "RIGHT", 2, 0)
  local plus = UI.Button(f, "+", 20, function() Commit(get() + StepMod(step)) end)
  plus:SetHeight(22)
  plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
  if hooks then hooks[#hooks + 1] = Show else UI.OnRefresh(Show) end
  f.box = eb
  return f
end

-------------------------------------------------------------------------------
-- Segmented control (one of a few choices, all visible)
-- options: { {value, label}, ... }
-------------------------------------------------------------------------------
function UI.Segmented(parent, options, w, get, set)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 24)
  local n = #options
  local bw = floor((w - (n - 1) * 2) / n)
  local btns = {}
  for i, o in ipairs(options) do
    local b = UI.Button(f, o[2], bw, function() set(o[1]); UI.Changed(); f.Refresh() end)
    b:SetPoint("LEFT", (i - 1) * (bw + 2), 0)
    b.value = o[1]
    btns[i] = b
  end
  function f.Refresh()
    local v = get()
    for _, b in ipairs(btns) do
      local on = b.value == v
      b.locked = on
      UI.SetFill(b.bg, on and C.accentBg or C.control)
      UI.SetBorder(b, on and C.accent or C.edge)
      b.label:SetTextColor(on and 1 or C.dim[1], on and 1 or C.dim[2], on and 1 or C.dim[3])
    end
  end
  UI.OnRefresh(f.Refresh)
  return f
end

-- Several independent on/off chips in a row (e.g. Solo / Pet / Party / Raid).
-- items: { {label, get, set}, ... }
function UI.Chips(parent, items, w)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 24)
  local n = #items
  local bw = floor((w - (n - 1) * 3) / n)
  local btns = {}
  for i, it in ipairs(items) do
    local b = UI.Button(f, it[1], bw, function() it[3](not it[2]()); UI.Changed(); f.Refresh() end)
    b:SetPoint("LEFT", (i - 1) * (bw + 3), 0)
    b.item = it
    btns[i] = b
  end
  function f.Refresh()
    for _, b in ipairs(btns) do
      local on = b.item[2]() and true or false
      b.locked = on
      UI.SetFill(b.bg, on and C.accentBg or C.control)
      UI.SetBorder(b, on and C.accent or C.edge)
      b.label:SetTextColor(on and 1 or C.dim[1], on and 1 or C.dim[2], on and 1 or C.dim[3])
    end
  end
  UI.OnRefresh(f.Refresh)
  return f
end

-------------------------------------------------------------------------------
-- Dropdown with its own themed list (long lists scroll with the wheel)
-------------------------------------------------------------------------------
local list, catcher, listItems = nil, nil, {}
local LIST_ROWS, ITEM_H = 12, 20

local function CloseList() if catcher then catcher:Hide() end end
UI.CloseList = CloseList

local function BuildList()
  catcher = CreateFrame("Button", "ThreatDiffDropdownCatcher", UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:SetScript("OnClick", CloseList)
  catcher:Hide()
  list = CreateFrame("Frame", "ThreatDiffDropdownList", catcher)
  list:SetFrameStrata("TOOLTIP")
  list:EnableMouse(true)
  list.bg = UI.Fill(list, { 0.06, 0.07, 0.09, 0.98 })
  UI.Border(list, C.accent)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(self, d)
    local maxOff = max(0, #self.opts - LIST_ROWS)
    self.offset = max(0, min(maxOff, self.offset - d))
    self.Fill()
  end)
  for i = 1, LIST_ROWS do
    local b = CreateFrame("Button", nil, list)
    b:SetHeight(ITEM_H)
    b:SetPoint("TOPLEFT", 1, -1 - (i - 1) * ITEM_H)
    b:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * ITEM_H)
    b.bg = UI.Fill(b, { 0, 0, 0, 0 })
    b.label = UI.Text(b, 12)
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetPoint("RIGHT", -8, 0)
    b.label:SetWordWrap(false)
    Hover(b, { 0, 0, 0, 0 }, C.hover)
    b:SetScript("OnClick", function(self)
      list.onPick(self.value)
      CloseList()
    end)
    listItems[i] = b
  end
  function list.Fill()
    local cur = list.get()
    for i = 1, LIST_ROWS do
      local o = list.opts[i + list.offset]
      local b = listItems[i]
      if o then
        b.value = o[1]
        b.label:SetText(o[2])
        local sel = (o[1] == cur)
        b.label:SetTextColor(sel and C.accent[1] or C.text[1], sel and C.accent[2] or C.text[2], sel and C.accent[3] or C.text[3])
        b:Show()
      else
        b:Hide()
      end
    end
  end
end

function UI.OpenList(owner, opts, get, onPick)
  if not list then BuildList() end
  if catcher:IsShown() and list.owner == owner then return CloseList() end
  list.owner, list.opts, list.get, list.onPick = owner, opts, get, onPick
  list.offset = 0
  local cur = get()
  for i, o in ipairs(opts) do -- open scrolled to the current value
    if o[1] == cur and i > LIST_ROWS then list.offset = min(i - 1, #opts - LIST_ROWS) end
  end
  list:ClearAllPoints()
  list:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  list:SetWidth(max(owner:GetWidth(), 160))
  list:SetHeight(min(#opts, LIST_ROWS) * ITEM_H + 2)
  list.Fill()
  catcher:Show()
end

-- options: table { {value, label}, ... } or a function returning one
function UI.Dropdown(parent, w, options, get, set)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 24)
  b.bg = UI.Fill(b, C.control)
  UI.Border(b, C.edge)
  Hover(b, C.control, C.hover, C.edge, C.accent)
  b.label = UI.Text(b, 12)
  b.label:SetPoint("LEFT", 9, 0)
  b.label:SetPoint("RIGHT", -24, 0)
  b.label:SetWordWrap(false)
  -- chevron
  local c1 = UI.Line(b, "ARTWORK", C.dim[1], C.dim[2], C.dim[3], 1)
  local c2 = UI.Line(b, "ARTWORK", C.dim[1], C.dim[2], C.dim[3], 1)
  c1:SetSize(7, 1.5); c2:SetSize(7, 1.5)
  c1:SetPoint("CENTER", b, "RIGHT", -14, 0); c2:SetPoint("CENTER", b, "RIGHT", -10, 0)
  c1:SetRotation(-math.pi / 4); c2:SetRotation(math.pi / 4)
  local function Opts() return type(options) == "function" and options() or options end
  b:SetScript("OnClick", function(self)
    UI.OpenList(self, Opts(), get, function(v) set(v); UI.Changed() end)
  end)
  function b.Refresh()
    local v = get()
    local text = "Custom"
    for _, o in ipairs(Opts()) do if o[1] == v then text = o[2] break end end
    b.label:SetText(text)
  end
  UI.OnRefresh(b.Refresh)
  return b
end

-------------------------------------------------------------------------------
-- Colour swatch (click to open the colour picker)
-------------------------------------------------------------------------------
function UI.OpenColor(c, onChange)
  local r0, g0, b0 = c[1], c[2], c[3]
  local function apply(r, g, b) c[1], c[2], c[3] = r, g, b; onChange() end
  local function changed() apply(ColorPickerFrame:GetColorRGB()) end
  local function cancel() apply(r0, g0, b0) end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({ r = r0, g = g0, b = b0, hasOpacity = false,
      swatchFunc = changed, cancelFunc = cancel })
  else
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.func, ColorPickerFrame.cancelFunc = changed, cancel
    ColorPickerFrame.previousValues = { r0, g0, b0 }
    ColorPickerFrame:SetColorRGB(r0, g0, b0)
    ColorPickerFrame:Hide(); ColorPickerFrame:Show()
  end
end

function UI.Swatch(parent, getColor, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 18, size or 18)
  UI.Fill(b, { 0, 0, 0, 1 })
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetPoint("TOPLEFT", 2, -2); b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
  UI.Border(b, C.edge)
  b:HookScript("OnEnter", function(self) UI.SetBorder(self, C.accent) end)
  b:HookScript("OnLeave", function(self) UI.SetBorder(self, C.edge) end)
  b:SetScript("OnClick", function() UI.OpenColor(getColor(), function() TD:ApplySettings() end) end)
  UI.OnRefresh(function() local c = getColor(); b.tex:SetColorTexture(c[1], c[2], c[3], 1) end)
  return b
end

-------------------------------------------------------------------------------
-- Windows
-------------------------------------------------------------------------------
function UI.Window(name, w, h, title)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f.bg = UI.Fill(f, C.bg)
  UI.Border(f, { 0, 0, 0, 1 })
  local top = UI.Line(f, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
  top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  f.titleText = UI.Text(f, 14)
  f.titleText:SetPoint("TOPLEFT", 14, -12)
  f.titleText:SetText(title or "")
  f.close = UI.CloseButton(f)
  f.close:SetPoint("TOPRIGHT", -6, -6)
  tinsert(UISpecialFrames, name)
  return f
end

-------------------------------------------------------------------------------
-- Scrolling pages made of cards and labelled rows
-------------------------------------------------------------------------------
UI.CARD_W = 560

function UI.Page(parent, title, subtitle)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf:SetPoint("TOPLEFT", 0, 0)
  sf:SetPoint("BOTTOMRIGHT", -8, 0)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(UI.CARD_W + 40, 100)
  sf:SetScrollChild(child)
  local bar = UI.Line(parent, "OVERLAY", C.accent[1], C.accent[2], C.accent[3], 0.5)
  bar:SetWidth(3)
  bar:Hide()
  local page = { frame = sf, child = child, y = -20, bar = bar, parent = parent }
  local function Scroll(to)
    local maxS = max(0, child:GetHeight() - sf:GetHeight())
    to = max(0, min(maxS, to))
    sf:SetVerticalScroll(to)
    local ph = parent:GetHeight()
    if maxS > 0 and ph > 0 then
      local bh = max(30, ph * ph / child:GetHeight())
      bar:SetHeight(bh)
      bar:ClearAllPoints()
      bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -((ph - bh) * to / maxS))
      bar:Show()
    else
      bar:Hide()
    end
  end
  page.Scroll = Scroll
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, d) Scroll(self:GetVerticalScroll() - d * 48) end)
  sf:SetScript("OnShow", function() Scroll(sf:GetVerticalScroll()); bar:SetShown(bar:IsShown()) end)
  sf:SetScript("OnHide", function() bar:Hide() end)

  local t = UI.Text(child, 18)
  t:SetPoint("TOPLEFT", 20, page.y)
  t:SetText(title)
  page.y = page.y - 26
  if subtitle then
    local s = UI.Text(child, 11, C.dim)
    s:SetPoint("TOPLEFT", 20, page.y)
    s:SetWidth(UI.CARD_W)
    s:SetText(subtitle)
    page.y = page.y - 28
  end
  page.y = page.y - 4
  return page
end

function UI.Card(page, title, desc)
  local card = CreateFrame("Frame", nil, page.child)
  card:SetPoint("TOPLEFT", 20, page.y)
  card:SetWidth(UI.CARD_W)
  card.bg = UI.Fill(card, C.card)
  UI.Border(card, C.cardEdge)
  card.page = page
  local t = UI.Text(card, 13)
  t:SetPoint("TOPLEFT", 16, -14)
  t:SetText(title)
  card.y = -36
  if desc then
    local d = UI.Text(card, 10, C.dim)
    d:SetPoint("TOPLEFT", 16, -32)
    d:SetWidth(UI.CARD_W - 32)
    d:SetText(desc)
    card.y = (#desc > 100) and -62 or -50
  end
  return card
end

-- A labelled row; put the control on it with row:Control(frame).
function UI.Row(card, label, desc, height)
  local h = height or (desc and ((#desc > 56) and 50 or 42) or 32)
  local row = CreateFrame("Frame", nil, card)
  row:SetPoint("TOPLEFT", 0, card.y)
  row:SetSize(UI.CARD_W, h)
  local sep = UI.Line(row, "BORDER", 1, 1, 1, 0.04)
  sep:SetPoint("TOPLEFT", 14, 0); sep:SetPoint("TOPRIGHT", -14, 0); sep:SetHeight(1)
  row.label = UI.Text(row, 12)
  row.label:SetPoint("TOPLEFT", 16, desc and -7 or -9)
  row.label:SetWidth(290)
  row.label:SetText(label)
  if desc then
    row.desc = UI.Text(row, 10, C.dim)
    row.desc:SetPoint("TOPLEFT", 16, -23)
    row.desc:SetWidth(290)
    row.desc:SetText(desc)
  end
  -- Put a control on the right. `total` = width of everything on the right
  -- when more controls are chained to its left. The text column shrinks to
  -- fit, and the row grows if the description needs extra lines.
  function row.Control(ctrl, dx, total)
    ctrl:SetPoint("RIGHT", row, "RIGHT", dx or -16, 0)
    local used = total or ctrl:GetWidth()
    local lw = UI.CARD_W - 32 - used - 14
    if lw < 290 then
      row.label:SetWidth(lw)
      if row.desc then
        row.desc:SetWidth(lw)
        local text = row.desc:GetText() or ""
        local lines = math.ceil(#text * 5.2 / lw)
        local need = 23 + lines * 13 + 7
        if need > row:GetHeight() then
          local extra = need - row:GetHeight()
          row:SetHeight(need)
          card.y = card.y - extra
        end
      end
    end
    return ctrl
  end
  card.y = card.y - h
  return row
end

function UI.EndCard(card)
  card.y = card.y - 10
  card:SetHeight(-card.y)
  local page = card.page
  page.y = page.y + card.y - 14
  page.child:SetHeight(-page.y + 10)
end
