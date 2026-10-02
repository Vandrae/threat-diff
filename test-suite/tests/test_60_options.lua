local test = T.test

-- helpers ------------------------------------------------------------------------
local function open(t, page)
  local W, TD = t:boot()
  TD:ToggleConfig(true, page)
  return W, TD
end

local function pageFrames(W)
  local out = {}
  for _, f in ipairs(W.frames) do if f._.kind == "ScrollFrame" then out[#out + 1] = f end end
  return out
end
local PAGE = { home = 1, plates = 2, meter = 3, profiles = 4, advanced = 5 }

local function desc(root, pred)
  local out = {}
  local function walk(o)
    for _, c in ipairs(o._.children) do
      if pred(c) then out[#out + 1] = c end
      walk(c)
    end
  end
  walk(root)
  return out
end

local function ctl(W, page, label, nth)
  local f = pageFrames(W)[PAGE[page]]
  local c1, c2, row = W.control(label, nth, f)
  t_ = nil
  return c1, c2, row
end

local function mustCtl(W, page, label, nth)
  local c1, c2, row = ctl(W, page, label, nth)
  if not c1 then error("no row labelled '" .. label .. "' on page " .. page, 2) end
  return c1, c2, row
end

local function pickFromList(W, dropdown, valueOrLabel)
  dropdown:Click("LeftButton")
  local list = _G.ThreatDiffDropdownList
  local catcher = _G.ThreatDiffDropdownCatcher
  if not catcher:IsShown() then error("dropdown list did not open", 2) end
  for _, b in ipairs(list._.children) do
    if b:IsShown() and (b.value == valueOrLabel or b.label._.text == valueOrLabel) then
      b:Click("LeftButton")
      return true
    end
  end
  error("option not in list: " .. tostring(valueOrLabel), 2)
end

-- window ---------------------------------------------------------------------------

test("options: window opens, has five pages, nav buttons switch pages", function(t)
  local W, TD = open(t)
  t.ok(_G.ThreatDiffConfig:IsShown())
  local pages = pageFrames(W)
  t.eq(#pages, 5)
  t.eq(pages[1]:IsShown(), true)
  for name, idx in pairs(PAGE) do
    local label = ({ home = "Home", plates = "Nameplate numbers", meter = "Threat meter",
      profiles = "Profiles", advanced = "Advanced" })[name]
    W.buttonByText(label):Click("LeftButton")
    for i, p in ipairs(pages) do t.eq(p:IsShown(), i == idx, "page " .. i .. " after opening " .. name) end
  end
end)

test("options: registered for the Escape key and the Blizzard settings list", function(t)
  local W, TD = open(t)
  local seen = {}
  for _, n in ipairs(UISpecialFrames) do seen[n] = true end
  t.ok(seen.ThreatDiffConfig)
  t.eq(#W.settingsCategories, 1)
  t.eq(W.settingsCategories[1].name, "ThreatDiff")
end)

test("options: Blizzard settings panel button opens the real window", function(t)
  local W, TD = t:boot()
  local panel = W.settingsCategories[1].panel
  local btn = W.buttonByText("Open ThreatDiff settings", panel)
  t.ok(btn)
  SettingsPanel:Show()
  btn:Click("LeftButton")
  t.eq(SettingsPanel:IsShown(), false)
  t.ok(_G.ThreatDiffConfig:IsShown())
end)

test("options: addon compartment click toggles the window", function(t)
  local W, TD = t:boot()
  t.ok(type(_G.ThreatDiff_OnAddonCompartmentClick) == "function")
  _G.ThreatDiff_OnAddonCompartmentClick()
  t.ok(_G.ThreatDiffConfig:IsShown())
  _G.ThreatDiff_OnAddonCompartmentClick()
  t.eq(_G.ThreatDiffConfig:IsShown(), false)
end)

test("options: opens straight to a page (meter right-click) and remembers it", function(t)
  local W, TD = open(t, "meter")
  t.eq(pageFrames(W)[3]:IsShown(), true)
  t.eq(pageFrames(W)[1]:IsShown(), false)
  TD:ToggleConfig(false)
  t.eq(_G.ThreatDiffConfig:IsShown(), false)
  TD:ToggleConfig(true)
  t.eq(pageFrames(W)[3]:IsShown(), true)
end)

test("options: live stats line updates every 2s and the timer stops when closed", function(t)
  local W, TD = open(t, "advanced")
  local _, _, row = mustCtl(W, "advanced", "Nameplate refresh")
  local statRow = W.row("Right now", 1, pageFrames(W)[5])
  t.eq(statRow.desc._.text, "measuring...")
  W.advance(2.1)
  t.has(statRow.desc._.text, "numbers showing")
  TD:ToggleConfig(false)
  local n = W.pendingTimers()
  W.advance(10)
  t.ok(W.pendingTimers() <= n)
  statRow.desc._.text = "x"
  W.advance(4)
  t.eq(statRow.desc._.text, "x", "no refresh after the window closed")
end)

-- toggles --------------------------------------------------------------------------

local TOGGLES = {
  { "home", "Threat numbers on nameplates", "enabled" },
  { "home", "Threat meter window", "meter.enabled" },
  { "plates", "Show threat numbers", "enabled" },
  { "plates", "Hide it while I'm safe", "hideSafe" },
  { "plates", "Drop shadow", "shadow" },
  { "plates", "Short numbers", "abbreviate" },
  { "plates", "Show + on a lead", "showPlus" },
  { "plates", "Show - on a gap", "showMinus" },
  { "plates", "Show !!! when tied", "bangOnTie" },
  { "meter", "Show the threat meter", "meter.enabled" },
  { "meter", "Lock position and size", "meter.locked" },
  { "meter", "Only show in combat", "meter.hideOOC" },
  { "meter", "Collapsed", "meter.collapsed" },
  { "meter", "Class colours", "meter.classColors" },
  { "meter", "Class icons", "meter.classIcons" },
  { "meter", "Rank numbers", "meter.rankNumbers" },
  { "meter", "Highlight my row", "meter.highlightYou" },
  { "meter", "Border", "meter.border" },
}

for _, spec in ipairs(TOGGLES) do
  test("options/toggle: " .. spec[1] .. " > " .. spec[2] .. " flips " .. spec[3], function(t)
    local W, TD = open(t, spec[1])
    local c = mustCtl(W, spec[1], spec[2])
    local before = TD.GetKey(spec[3]) and true or false
    c:Click("LeftButton")
    t.eq(TD.GetKey(spec[3]) and true or false, not before, "after first click")
    t.eq(c.state._.text, (not before) and "ON" or "OFF", "switch label")
    c:Click("LeftButton")
    t.eq(TD.GetKey(spec[3]) and true or false, before, "after second click")
  end)
end

test("options/toggle: Home 'Minimap button' shows and hides the button", function(t)
  local W, TD = open(t, "home")
  local c = mustCtl(W, "home", "Minimap button")
  t.eq(c.state._.text, "ON")
  c:Click("LeftButton")
  t.eq(_G.ThreatDiffMinimapButton:IsShown(), false)
  t.eq(c.state._.text, "OFF")
  c:Click("LeftButton")
  t.eq(_G.ThreatDiffMinimapButton:IsShown(), true)
end)

test("options/toggle: the meter toggles really hide/show the meter window", function(t)
  local W, TD = open(t, "meter")
  local c = mustCtl(W, "meter", "Show the threat meter")
  c:Click("LeftButton"); t.eq(_G.ThreatDiffMeter:IsShown(), false)
  c:Click("LeftButton"); t.eq(_G.ThreatDiffMeter:IsShown(), true)
  local lock = mustCtl(W, "meter", "Lock position and size")
  lock:Click("LeftButton")
  t.eq(_G.ThreatDiffMeter._.children[3]:IsShown(), false, "grip hidden when locked")
  local coll = mustCtl(W, "meter", "Collapsed")
  coll:Click("LeftButton")
  t.eq(_G.ThreatDiffMeter:GetHeight(), 20)
end)

test("options/toggle: the same setting stays in sync across pages and the /tdiff command", function(t)
  local W, TD = open(t, "home")
  local home = mustCtl(W, "home", "Threat meter window")
  local meterPg = mustCtl(W, "meter", "Show the threat meter")
  home:Click("LeftButton")
  t.eq(meterPg.state._.text, "OFF", "other page's switch follows")
  SlashCmdList.THREATDIFF("meter show")
  t.eq(home.state._.text, "ON")
  t.eq(meterPg.state._.text, "ON")
end)

-- chips & segmented -----------------------------------------------------------------

test("options/chips: Solo / With pet / Party / Raid chips toggle independently", function(t)
  local W, TD = open(t, "plates")
  local chips = mustCtl(W, "plates", "Show them when I'm")
  local keys = { "showSolo", "showPet", "showParty", "showRaid" }
  t.eq(#chips._.children, 4)
  for i, b in ipairs(chips._.children) do
    t.eq(TD.db[keys[i]], true, keys[i] .. " default")
    b:Click("LeftButton")
    t.eq(TD.db[keys[i]], false, keys[i] .. " after click")
    for j, k in ipairs(keys) do if j ~= i and j < i then t.eq(TD.db[k], false) elseif j > i then t.eq(TD.db[k], true) end end
  end
  for i, b in ipairs(chips._.children) do b:Click("LeftButton") end
  for _, k in ipairs(keys) do t.eq(TD.db[k], true) end
end)

local SEGMENTS = {
  { "home", "I usually play as", "role", { "AUTO", "TANK", "DPS" } },
  { "plates", "For damage and healers, show", "dpsRef", { "TOP", "PULL" } },
  { "plates", "Outline", "outline", { "NONE", "OUTLINE", "THICK" } },
  { "plates", "Decimal places", "decimals", { 0, 1, 2 } },
  { "plates", "Line it up with", "anchorTo", { "PLATE", "HEALTH" } },
  { "plates", "Tanks: measure the safe lead as", "secureMode", { "PCT", "ABS" } },
  { "meter", "Outline", "meter.outline", { "NONE", "OUTLINE", "THICK" } },
}
for _, spec in ipairs(SEGMENTS) do
  test("options/segmented: " .. spec[1] .. " > " .. spec[2], function(t)
    local W, TD = open(t, spec[1])
    local seg = mustCtl(W, spec[1], spec[2])
    t.eq(#seg._.children, #spec[4])
    for i, b in ipairs(seg._.children) do
      b:Click("LeftButton")
      t.eq(TD.GetKey(spec[3]), spec[4][i], "option " .. i)
      t.eq(b.locked, true, "selected button is highlighted")
    end
  end)
end

-- sliders ---------------------------------------------------------------------------

local SLIDERS = {
  { "plates", "Size", "fontSize", 6, 40, 18, " pt" },
  { "plates", "Damage and healers: warn at", "warnPct", 10, 100, 55, "%" },
  { "plates", "Damage and healers: danger at", "dangerPct", 10, 100, 95, "%" },
  { "meter", "Width", "meter.width", 140, 800, 300, " px" },
  { "meter", "Height", "meter.height", 40, 1200, 400, " px" },
  { "meter", "Bar height", "meter.barHeight", 6, 40, 22, " px" },
  { "meter", "Space between bars", "meter.spacing", 0, 10, 3, " px" },
  { "meter", "Font size", "meter.fontSize", 6, 30, 14, " pt" },
  { "advanced", "Nameplate refresh", "interval", 0.05, 1, 0.35, " s" },
  { "advanced", "Meter refresh", "meter.interval", 0.05, 1, 0.55, " s" },
  { "advanced", "Keep the last number", "keepLast", 0, 60, 25, " s" },
}
for _, spec in ipairs(SLIDERS) do
  local page, label, key, lo, hi, mid, suffix = unpack(spec)
  test("options/slider: " .. page .. " > " .. label .. " drag, type, clamp", function(t)
    local W, TD = open(t, page)
    local f = mustCtl(W, page, label)
    t.ok(f.slider and f.box)
    f.slider:SetValue(mid)
    t.near(TD.GetKey(key), mid, 1e-6, "slider drag")
    t.has(f.box._.text, suffix:gsub("%p", "%%%0") .. "$", "box shows the unit")
    f.box._.text = tostring(hi + 1000)
    W.fireScript(f.box, "OnEnterPressed")
    t.near(TD.GetKey(key), hi, 1e-6, "typed too big clamps to max")
    f.box._.text = tostring(lo - 5)
    W.fireScript(f.box, "OnEnterPressed")
    t.near(TD.GetKey(key), math.max(lo, key == "meter.height" and TD.MeterHeightFor(1, TD.db.meter.barHeight, TD.db.meter.spacing) or lo), 1e-6, "typed too small clamps to min")
    f.box._.text = tostring(mid) .. suffix
    W.fireScript(f.box, "OnEnterPressed")
    t.near(TD.GetKey(key), mid, 1e-6, "typed with unit suffix")
    f.box._.text = "banana"
    W.fireScript(f.box, "OnEnterPressed")
    t.near(TD.GetKey(key), mid, 1e-6, "garbage ignored")
    W.fireScript(f.slider, "OnMouseWheel", 1)
    t.ok(TD.GetKey(key) ~= mid or mid == hi, "mouse wheel steps the value")
  end)
end

test("options/slider: see-through sliders show percentages but store 0-1", function(t)
  local W, TD = open(t, "meter")
  for _, spec in ipairs({ { "Background", "bgAlpha" }, { "Bars", "barAlpha" }, { "Bar backdrop", "barBgAlpha" } }) do
    local f = mustCtl(W, "meter", spec[1])
    f.slider:SetValue(0.4)
    t.near(TD.db.meter[spec[2]], 0.4, 1e-6)
    t.eq(f.box._.text, "40%")
    f.box._.text = "85%"
    W.fireScript(f.box, "OnEnterPressed")
    t.near(TD.db.meter[spec[2]], 0.85, 1e-6)
    t.eq(f.box._.text, "85%")
    f.box._.text = "150"
    W.fireScript(f.box, "OnEnterPressed")
    t.near(TD.db.meter[spec[2]], 1, 1e-6, "clamped to 100%")
  end
end)

test("options/slider: changing the meter size slider resizes the meter and the 'fits N rows' text", function(t)
  local W, TD = open(t, "meter")
  local hf, _, hrow = mustCtl(W, "meter", "Height")
  hf.slider:SetValue(100)
  t.eq(_G.ThreatDiffMeter:GetHeight(), 100)
  t.has(hrow.desc._.text, "fits 4 rows")
  local wf = mustCtl(W, "meter", "Width")
  wf.slider:SetValue(500)
  t.eq(_G.ThreatDiffMeter:GetWidth(), 500)
  hf.box._.text = "43"; W.fireScript(hf.box, "OnEnterPressed")
  t.has(hrow.desc._.text, "fits 1 row%.")
end)

test("options/slider: font size slider restyles live nameplate numbers", function(t)
  local W, TD = open(t, "plates")
  local mob = W.mob("Boar"); W.addPlate("nameplate1", mob)
  local f = mustCtl(W, "plates", "Size")
  f.slider:SetValue(25)
  local _, size = TD.active.nameplate1.fs:GetFont()
  t.eq(size, 25)
end)

-- dropdowns -------------------------------------------------------------------------

test("options/dropdown: Font lists built-in fonts and applies the pick", function(t)
  local W, TD = open(t, "plates")
  local mob = W.mob("Boar"); W.addPlate("nameplate1", mob)
  local dd = mustCtl(W, "plates", "Font")
  t.eq(dd.label._.text, "Friz Quadrata (game font)")
  pickFromList(W, dd, "Arial Narrow")
  t.eq(TD.db.font, "Fonts\\ARIALN.TTF")
  t.eq((TD.active.nameplate1.fs:GetFont()), "Fonts\\ARIALN.TTF")
  t.eq(dd.label._.text, "Arial Narrow")
  t.eq(_G.ThreatDiffDropdownCatcher:IsShown(), false, "list closes after a pick")
end)

test("options/dropdown: a font from LibSharedMedia is offered; unknown saved font shows by file name", function(t)
  local W, TD = t:boot({ noLogin = true, saved = { profiles = { Default = { font = "Interface\\AddOns\\Odd\\Odd.ttf" } }, chars = {} } })
  _G.LibStub = function() return {
    List = function() return { "Fancy" } end,
    Fetch = function() return "Interface\\AddOns\\SM\\Fancy.ttf" end } end
  t:login()
  TD:ToggleConfig(true, "plates")
  local dd = mustCtl(W, "plates", "Font")
  t.eq(dd.label._.text, "Odd.ttf")
  dd:Click("LeftButton")
  local names = {}
  for _, b in ipairs(_G.ThreatDiffDropdownList._.children) do if b:IsShown() then names[#names + 1] = b.label._.text end end
  t.eq(#names, 6, "4 built-in + Fancy + the custom saved one")
  t.eq(names[5], "Fancy")
end)

test("options/dropdown: placement presets set both anchor points", function(t)
  local W, TD = open(t, "plates")
  local dd = mustCtl(W, "plates", "Place the number")
  t.eq(dd.label._.text, "Left of the nameplate")
  for _, spec in ipairs({
    { "Right of the nameplate", "LEFT", "RIGHT" }, { "Above the nameplate", "BOTTOM", "TOP" },
    { "Below the nameplate", "TOP", "BOTTOM" }, { "On the nameplate", "CENTER", "CENTER" },
    { "Left of the nameplate", "RIGHT", "LEFT" } }) do
    pickFromList(W, dd, spec[1])
    t.eq(TD.db.point, spec[2], spec[1]); t.eq(TD.db.relPoint, spec[3], spec[1])
    t.eq(dd.label._.text, spec[1])
  end
  TD.db.point, TD.db.relPoint = "TOPLEFT", "BOTTOMRIGHT"; TD:ApplySettings()
  t.eq(dd.label._.text, "Custom (see Advanced)")
end)

test("options/dropdown: advanced anchor points and meter dropdowns", function(t)
  local W, TD = open(t, "advanced")
  local dd1 = mustCtl(W, "advanced", "Point on the number")
  local dd2 = mustCtl(W, "advanced", "Point on the nameplate")
  pickFromList(W, dd1, "TOPRIGHT"); t.eq(TD.db.point, "TOPRIGHT")
  pickFromList(W, dd2, "BOTTOMLEFT"); t.eq(TD.db.relPoint, "BOTTOMLEFT")
  TD:ToggleConfig(true, "meter")
  local pull = mustCtl(W, "meter", "Pull warning rows")
  pickFromList(W, pull, "MINE"); t.eq(TD.db.meter.pullRows, "MINE")
  pickFromList(W, pull, "OFF"); t.eq(TD.db.meter.pullRows, "OFF")
  local fmt = mustCtl(W, "meter", "Numbers on each row")
  pickFromList(W, fmt, "GAP"); t.eq(TD.db.meter.valueFormat, "GAP")
  local style = mustCtl(W, "meter", "Bar style")
  for _, k in ipairs({ "FLAT", "GLOSS", "RAID", "THIN", "BLIZZARD" }) do pickFromList(W, style, k); t.eq(TD.db.meter.barStyle, k) end
  local font = mustCtl(W, "meter", "Font")
  pickFromList(W, font, "Fonts\\skurri.ttf"); t.eq(TD.db.meter.font, "Fonts\\skurri.ttf")
end)

test("options/dropdown: clicking an open dropdown again, or elsewhere, closes it", function(t)
  local W, TD = open(t, "plates")
  local dd = mustCtl(W, "plates", "Font")
  dd:Click("LeftButton")
  t.eq(_G.ThreatDiffDropdownCatcher:IsShown(), true)
  dd:Click("LeftButton")
  t.eq(_G.ThreatDiffDropdownCatcher:IsShown(), false)
  dd:Click("LeftButton")
  _G.ThreatDiffDropdownCatcher:Click("LeftButton")
  t.eq(_G.ThreatDiffDropdownCatcher:IsShown(), false)
  dd:Click("LeftButton")
  W.buttonByText("Advanced"):Click("LeftButton")
  t.eq(_G.ThreatDiffDropdownCatcher:IsShown(), false, "changing page closes it")
end)

test("options/dropdown: Bar style list contains the five built-ins", function(t)
  local W, TD = open(t, "meter")
  local dd = mustCtl(W, "meter", "Bar style")
  dd:Click("LeftButton")
  local n = 0
  for _, b in ipairs(_G.ThreatDiffDropdownList._.children) do if b:IsShown() then n = n + 1 end end
  t.eq(n, 5)
end)

-- exact position boxes ---------------------------------------------------------------

local function xy(W)
  local yBox, xBox = mustCtl(W, "plates", "Exact offset")
  local _, _, row = mustCtl(W, "plates", "Exact offset")
  return row._.children[2], row._.children[1]   -- x, y
end

test("options/position: X and Y boxes show 2 decimals and apply on Enter", function(t)
  local W, TD = open(t, "plates")
  local x, y = xy(W)
  t.eq(x.box._.text, "-6.00"); t.eq(y.box._.text, "0.00")
  x.box._.text = "2.34"; W.fireScript(x.box, "OnEnterPressed")
  y.box._.text = "10.25"; W.fireScript(y.box, "OnEnterPressed")
  t.eq(TD.db.x, 2.34); t.eq(TD.db.y, 10.25)
  t.eq(x.box._.text, "2.34"); t.eq(y.box._.text, "10.25")
  x.box._.text = "9999"; W.fireScript(x.box, "OnEnterPressed")
  t.eq(TD.db.x, 500, "clamped")
  x.box._.text = "abc"; W.fireScript(x.box, "OnEnterPressed")
  t.eq(TD.db.x, 500, "garbage ignored")
end)

test("options/position: typing 1.005 gives 1.01 like /tdiff pos does", function(t)
  local W, TD = open(t, "plates")
  local x = xy(W)
  x.box._.text = "1.005"; W.fireScript(x.box, "OnEnterPressed")
  t.eq(TD.db.x, 1.01)
  x.box._.text = "2.345"; W.fireScript(x.box, "OnEnterPressed")
  t.eq(TD.db.x, 2.35)
end)

test("options/position: +/- step 1, Shift 0.1, Ctrl 0.01, and the wheel", function(t)
  local W, TD = open(t, "plates")
  local x = xy(W)
  local minus, plus = x._.children[2], x._.children[3]
  TD:SetPosition(0, 0)
  plus:Click("LeftButton"); t.eq(TD.db.x, 1)
  minus:Click("LeftButton"); minus:Click("LeftButton"); t.eq(TD.db.x, -1)
  W.mods.shift = true
  plus:Click("LeftButton"); t.eq(TD.db.x, -0.9)
  W.mods.shift, W.mods.ctrl = false, true
  plus:Click("LeftButton"); t.eq(TD.db.x, -0.89)
  W.mods.ctrl = false
  W.fireScript(x.box, "OnMouseWheel", 1); t.eq(TD.db.x, 0.11)
  for i = 1, 10 do plus:Click("LeftButton") end
  t.eq(TD.db.x, 10.11, "no float drift")
end)

test("options/position: boxes follow position changes made elsewhere (command, editor)", function(t)
  local W, TD = open(t, "plates")
  local x, y = xy(W)
  SlashCmdList.THREATDIFF("pos 3.5 -2.25")
  t.eq(x.box._.text, "3.50"); t.eq(y.box._.text, "-2.25")
  TD:SetPosition(8, 9)
  t.eq(x.box._.text, "8.00")
end)

-- colours ---------------------------------------------------------------------------

local function swatches(W, pageIdx)
  return desc(pageFrames(W)[pageIdx], function(f) return f._.kind == "Button" and f.tex ~= nil end)
end

test("options/colours: swatches open the colour picker and recolour live numbers", function(t)
  local W, TD = open(t, "home")
  local sw = swatches(W, 1)
  t.eq(#sw, 10, "one swatch per state on the Home page")
  local mob = W.mob("Boar"); W.addPlate("nameplate1", mob)
  W.setThreat(mob, W.player, { v = 5000, tank = true, status = 3 })
  W.enterCombat(); W.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1"); W.advance(0.3)
  sw[1]:Click("LeftButton")                     -- SECURE
  t.ok(W.picker, "picker opened")
  t.eq(W.picker.r, 0.25)
  W.pickerFrame.rgb = { 0, 0, 1 }
  W.picker.swatchFunc()
  t.eq(TD.db.colors.SECURE[3], 1); t.eq(TD.db.colors.SECURE[1], 0)
  W.advance(0.3)
  local r, g, b = TD.active.nameplate1.fs:GetTextColor()
  t.eq(b, 1, "live number repainted in the new colour")
  W.picker.cancelFunc()
  t.eq(TD.db.colors.SECURE[1], 0.25, "cancel restores the old colour")
end)

test("options/colours: Reset colours restores the defaults", function(t)
  local W, TD = open(t, "plates")
  TD.db.colors.LOOSE = { 0, 0, 0 }; TD:ApplySettings()
  W.buttonByText("Reset colours"):Click("LeftButton")
  t.eq(TD.db.colors.LOOSE[1], 1)
  t.eq(TD.db.colors.LOOSE[2], 0.15)
  TD.db.colors.LOOSE[1] = 0.5
  t.eq(TD.DEFAULTS.colors.LOOSE[1], 1, "defaults must not be shared with the profile")
end)

test("options/colours: nameplate page has a swatch for every state", function(t)
  local W, TD = open(t, "plates")
  t.eq(#swatches(W, 2), 10)
end)

-- home page --------------------------------------------------------------------------

test("options/home: Preview button toggles preview and relabels", function(t)
  local W, TD = open(t, "home")
  local mob = W.mob("Boar"); W.addPlate("nameplate1", mob)
  local b = W.buttonByText("Preview", pageFrames(W)[1])
  b:Click("LeftButton")
  t.eq(TD.testMode, true); t.eq(b.label._.text, "Stop preview")
  t.eq(TD.active.nameplate1.vis, true)
  b:Click("LeftButton")
  t.eq(TD.testMode, false); t.eq(b.label._.text, "Preview")
end)

test("options/home: 'Move the number' opens the editor", function(t)
  local W, TD = open(t, "home")
  W.buttonByText("Move the number"):Click("LeftButton")
  t.ok(_G.ThreatDiffEditor:IsShown())
end)

test("options/meter: preview button and reset position", function(t)
  local W, TD = open(t, "meter")
  local pv = W.buttonByText("Preview", pageFrames(W)[3])
  pv:Click("LeftButton"); t.eq(TD.testMode, true); t.eq(pv.label._.text, "Stop preview")
  TD.db.meter.x = 1
  W.buttonByText("Reset position"):Click("LeftButton")
  t.eq(TD.db.meter.x, 260)
  pv:Click("LeftButton"); t.eq(TD.testMode, false)
end)

-- tank safe-lead settings -------------------------------------------------------------

test("options/warning levels: percent vs fixed amount switches control and value sanity", function(t)
  local W, TD = open(t, "plates")
  local pctSlider, absBox = mustCtl(W, "plates", "Tanks: safe lead")
  local seg = mustCtl(W, "plates", "Tanks: measure the safe lead as")
  t.eq(pctSlider:IsShown(), true); t.eq(absBox:IsShown(), false)
  seg._.children[2]:Click("LeftButton")     -- fixed amount
  t.eq(pctSlider:IsShown(), false); t.eq(absBox:IsShown(), true)
  absBox.box._.text = "5000"; W.fireScript(absBox.box, "OnEnterPressed")
  t.eq(TD.db.secureValue, 5000)
  seg._.children[1]:Click("LeftButton")     -- back to percent: 5000 is nonsense for a percent
  t.eq(TD.db.secureValue, 25, "reset to a sane percentage")
  t.eq(pctSlider:IsShown(), true)
end)

test("options/warning levels: fixed amount actually drives the green/yellow threshold", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "Stabby", class = "ROGUE" } }
  W.player.role = "TANK"; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  TD.db.secureMode, TD.db.secureValue = "ABS", 500; TD:ApplySettings()
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 2000, { tank = true }); t:set(mob, g[1], 1600)
  W.enterCombat(); t:tick()
  t.eq(t:plate().state, "TANKING", "lead 400 < 500")
  t:set(mob, g[1], 1400); t:tick()
  t.eq(t:plate().state, "SECURE", "lead 600 >= 500")
end)

-- advanced page ----------------------------------------------------------------------

test("options/advanced: probe, commands and reset buttons", function(t)
  local W, TD = open(t, "advanced")
  W.clearChat()
  W.buttonByText("Run probe"):Click("LeftButton")
  t.has(W.chatText(), "probe armed")
  W.clearChat()
  W.buttonByText("Show commands"):Click("LeftButton")
  t.has(W.chatText(), "/tdiff pos")
  TD.db.x = 40
  W.buttonByText("Reset profile", pageFrames(W)[5]):Click("LeftButton")
  t.ok(_G.ThreatDiffPrompt:IsShown(), "asks first")
  t.eq(TD.db.x, 40, "nothing happens until confirmed")
  W.buttonByText("OK", _G.ThreatDiffPrompt):Click("LeftButton")
  t.eq(TD.db.x, -6)
  t.eq(_G.ThreatDiffPrompt:IsShown(), false)
end)

-- profiles page -----------------------------------------------------------------------

local function prompt(W) return _G.ThreatDiffPrompt end
local function promptEB(W) return _G.ThreatDiffPrompt._.children and (function()
  for _, c in ipairs(_G.ThreatDiffPrompt._.children) do if c._.kind == "EditBox" then return c end end end)() end
local function okPrompt(W) W.buttonByText("OK", _G.ThreatDiffPrompt):Click("LeftButton") end

test("options/profiles: Active profile dropdown lists and switches", function(t)
  local W, TD = open(t, "profiles")
  TD:NewProfile("Raid"); TD.db.x = 77
  local dd, _, row = mustCtl(W, "profiles", "Active profile")
  t.eq(dd.label._.text, "Raid")
  t.has(row.desc._.text, "Used by Tester %- Testrealm")
  pickFromList(W, dd, "Default")
  t.eq(TD.profileName, "Default"); t.eq(TD.db.x, -6)
  t.eq(dd.label._.text, "Default")
  pickFromList(W, dd, "Raid")
  t.eq(TD.db.x, 77)
end)

test("options/profiles: New creates a profile through the prompt; duplicates are refused with a message", function(t)
  local W, TD = open(t, "profiles")
  W.buttonByText("New"):Click("LeftButton")
  local p, eb = prompt(W), promptEB(W)
  t.ok(p:IsShown() and eb:IsShown())
  eb:SetText("Tank")
  okPrompt(W)
  t.eq(TD.profileName, "Tank"); t.eq(p:IsShown(), false)
  W.buttonByText("New"):Click("LeftButton")
  promptEB(W):SetText("tank")
  okPrompt(W)
  t.eq(p:IsShown(), true, "stays open on error")
  local msg = W.findText("already exists", p)
  t.ok(#msg == 1, "error message shown in the prompt")
  W.buttonByText("Cancel", p):Click("LeftButton")
  t.eq(p:IsShown(), false)
  W.buttonByText("New"):Click("LeftButton")
  promptEB(W):SetText("Enter")
  W.fireScript(promptEB(W), "OnEnterPressed")
  t.eq(TD.profileName, "Enter", "Enter key accepts")
end)

test("options/profiles: Duplicate prefills '<name> copy' and copies settings", function(t)
  local W, TD = open(t, "profiles")
  TD.db.x = 31
  W.buttonByText("Duplicate"):Click("LeftButton")
  t.eq(promptEB(W):GetText(), "Default copy")
  okPrompt(W)
  t.eq(TD.profileName, "Default copy"); t.eq(TD.db.x, 31)
end)

test("options/profiles: Rename works for other profiles and is refused for Default", function(t)
  local W, TD = open(t, "profiles")
  W.clearChat()
  W.buttonByText("Rename"):Click("LeftButton")
  t.has(W.chatText(), "Default profile can't be renamed")
  t.eq(_G.ThreatDiffPrompt and _G.ThreatDiffPrompt:IsShown() or false, false)
  TD:NewProfile("Raid")
  W.buttonByText("Rename"):Click("LeftButton")
  t.eq(promptEB(W):GetText(), "Raid")
  promptEB(W):SetText("Raids")
  okPrompt(W)
  t.eq(TD.profileName, "Raids")
end)

test("options/profiles: pressing OK in Rename without changing the name keeps the profile", function(t)
  local W, TD = open(t, "profiles")
  TD:NewProfile("Raid"); TD.db.x = 12
  W.buttonByText("Rename"):Click("LeftButton")
  okPrompt(W)
  t.ok(_G.ThreatDiffDB.profiles.Raid, "profile still exists")
  t.eq(TD.db.x, 12)
end)

test("options/profiles: Reset asks for confirmation", function(t)
  local W, TD = open(t, "profiles")
  TD.db.x = 55
  W.buttonByText("Reset", pageFrames(W)[4]):Click("LeftButton")
  t.eq(_G.ThreatDiffPrompt:IsShown(), true)
  t.eq(promptEB(W):IsShown(), false, "no text box for a yes/no prompt")
  W.buttonByText("Cancel", _G.ThreatDiffPrompt):Click("LeftButton")
  t.eq(TD.db.x, 55)
  W.buttonByText("Reset", pageFrames(W)[4]):Click("LeftButton")
  okPrompt(W)
  t.eq(TD.db.x, -6)
end)

test("options/profiles: Copy and Delete use the dropdowns and ask first", function(t)
  local W, TD = open(t, "profiles")
  TD.db.x = 90                     -- Default
  TD:NewProfile("Raid")
  TD.db.x = 5
  TD:NewProfile("Spare")
  -- Copy: dropdown defaults to the first other profile (Default)
  local _, copyDD = mustCtl(W, "profiles", "Copy settings from")
  local copyBtn2 = W.buttonByText("Copy", pageFrames(W)[4])
  pickFromList(W, copyDD, "Default")
  copyBtn2:Click("LeftButton")
  t.has(W.findText("Replace everything", _G.ThreatDiffPrompt)[1]._.text, "Spare")
  okPrompt(W)
  t.eq(TD.profileName, "Spare"); t.eq(TD.db.x, 90)
  -- Delete
  TD:SetProfile("Default")
  local _, delDD = mustCtl(W, "profiles", "Delete a profile")
  pickFromList(W, delDD, "Spare")
  W.buttonByText("Delete", pageFrames(W)[4]):Click("LeftButton")
  t.has(W.findText("can't be undone", _G.ThreatDiffPrompt)[1]._.text, "Spare")
  okPrompt(W)
  t.eq(_G.ThreatDiffDB.profiles.Spare, nil)
end)

test("options/profiles: Copy/Delete are harmless when there is nothing to pick", function(t)
  local W, TD = open(t, "profiles")
  local _, copyDD = mustCtl(W, "profiles", "Copy settings from")
  t.eq(copyDD.label._.text, "(no other profiles)")
  W.buttonByText("Copy", pageFrames(W)[4]):Click("LeftButton")
  W.buttonByText("Delete", pageFrames(W)[4]):Click("LeftButton")
  t.ok(not (_G.ThreatDiffPrompt and _G.ThreatDiffPrompt:IsShown()), "no prompt")
  t.eq(#W.errors, 0)
end)

test("options/profiles: header badge shows the active profile", function(t)
  local W, TD = open(t, "home")
  local badge = W.findText("^Profile ", _G.ThreatDiffConfig)[1]
  t.has(badge._.text, "Default")
  TD:NewProfile("Raid")
  t.has(badge._.text, "Raid")
end)

-- robustness of the settings window -----------------------------------------------------

test("options: window survives odd saved values", function(t)
  local W, TD = t:boot({ saved = { profiles = { Default = { point = "TOPLEFT", relPoint = "BOTTOM",
    font = "Fonts\\Weird.ttf", secureMode = "ABS", secureValue = 123456, decimals = 2, role = "TANK",
    meter = { barStyle = "LSM:Gone", pullRows = "MINE", valueFormat = "GAP" } } }, chars = {} } })
  TD:ToggleConfig(true)
  for _, label in ipairs({ "Nameplate numbers", "Threat meter", "Profiles", "Advanced", "Home" }) do
    W.buttonByText(label):Click("LeftButton")
  end
  t.eq(#W.errors, 0)
end)
