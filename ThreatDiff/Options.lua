--[[ ThreatDiff - the settings window.

  Sidebar pages: Home (quick setup + colour guide), Nameplate numbers,
  Threat meter, Profiles and Advanced. Every setting is a labelled row with
  a one-line explanation in plain words.
]]

local _, ns = ...
local TD = ns.TD
local UI = ns.UI
local C = UI.C
local Print = TD.Print
local format, ipairs, pairs = string.format, ipairs, pairs

-------------------------------------------------------------------------------
-- Settings access ("meter.width" -> TD.db.meter.width)
-------------------------------------------------------------------------------
local function GetKey(key)
  local sub = key:match("^meter%.(.+)$")
  if sub then return TD.db.meter[sub] end
  return TD.db[key]
end
local function SetKey(key, v)
  local sub = key:match("^meter%.(.+)$")
  if sub then TD.db.meter[sub] = v else TD.db[key] = v end
end
TD.GetKey, TD.SetKey = GetKey, SetKey

local function Getter(key) return function() return GetKey(key) end end
local function Setter(key) return function(v) SetKey(key, v) end end

local BUILTIN_FONTS = {
  { "Fonts\\FRIZQT__.TTF", "Friz Quadrata (game font)" },
  { "Fonts\\ARIALN.TTF",   "Arial Narrow" },
  { "Fonts\\skurri.ttf",   "Skurri" },
  { "Fonts\\MORPHEUS.ttf", "Morpheus" },
}

-- Built-in fonts plus LibSharedMedia fonts if another addon ships them.
local function FontOptions(key)
  return function()
    local list = {}
    for i, f in ipairs(BUILTIN_FONTS) do list[i] = f end
    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    if LSM then
      local seen = {}
      for _, f in ipairs(list) do seen[f[1]] = true end
      for _, name in ipairs(LSM:List("font")) do
        local path = LSM:Fetch("font", name, true)
        if path and not seen[path] then seen[path] = true; list[#list + 1] = { path, name } end
      end
    end
    local cur = GetKey(key)
    local found = false
    for _, f in ipairs(list) do if f[1] == cur then found = true break end end
    if not found then list[#list + 1] = { cur, (cur:match("([^\\/]+)$") or cur) } end
    return list
  end
end

-- Plain-language meaning of each colour.
TD.PLAIN = {
  SECURE    = "Safe lead - you're holding it",
  TANKING   = "Thin lead - keep building threat",
  INSECURE  = "Losing it - someone passed you!",
  OTHERTANK = "Another tank has it",
  LOOSE     = "A non-tank has it - taunt!",
  PET       = "Your pet has it",
  SAFE      = "Safe",
  WARN      = "Getting close - ease off",
  DANGER    = "About to pull - stop!",
  AGGRO     = "You pulled it!",
}
local SAMPLE = { SECURE = "+4.2k", TANKING = "+812", INSECURE = "!!!", OTHERTANK = "-2.4k", LOOSE = "-1.9k",
                 PET = "-540", SAFE = "-3.1k", WARN = "-960", DANGER = "-212", AGGRO = "+305" }

local POINT_NAMES = {
  { "TOPLEFT", "Top left" }, { "TOP", "Top" }, { "TOPRIGHT", "Top right" },
  { "LEFT", "Left" }, { "CENTER", "Centre" }, { "RIGHT", "Right" },
  { "BOTTOMLEFT", "Bottom left" }, { "BOTTOM", "Bottom" }, { "BOTTOMRIGHT", "Bottom right" },
}
-- Friendly placements = (point on the number, point on the nameplate)
local PLACES = {
  { "LEFT_OF",  "Left of the nameplate",  "RIGHT",  "LEFT" },
  { "RIGHT_OF", "Right of the nameplate", "LEFT",   "RIGHT" },
  { "ABOVE",    "Above the nameplate",    "BOTTOM", "TOP" },
  { "BELOW",    "Below the nameplate",    "TOP",    "BOTTOM" },
  { "CENTRE",   "On the nameplate",       "CENTER", "CENTER" },
}
local function CurrentPlace()
  for _, p in ipairs(PLACES) do
    if TD.db.point == p[3] and TD.db.relPoint == p[4] then return p[1] end
  end
  return "CUSTOM"
end
local function PlaceOptions()
  local l = {}
  for i, p in ipairs(PLACES) do l[i] = { p[1], p[2] } end
  if CurrentPlace() == "CUSTOM" then l[#l + 1] = { "CUSTOM", "Custom (see Advanced)" } end
  return l
end
local function SetPlace(v)
  for _, p in ipairs(PLACES) do
    if p[1] == v then TD.db.point, TD.db.relPoint = p[3], p[4] end
  end
end

-------------------------------------------------------------------------------
-- Prompt (OK / Cancel, optional text box). onOk(text) returns ok, err.
-------------------------------------------------------------------------------
local prompt
function TD:Prompt(title, text, default, onOk)
  if not prompt then
    prompt = UI.Window("ThreatDiffPrompt", 380, 150, "")
    prompt:ClearAllPoints()
    prompt:SetPoint("CENTER", 0, 120)
    prompt:SetFrameStrata("FULLSCREEN_DIALOG")
    prompt.msg = UI.Text(prompt, 12, C.dim)
    prompt.msg:SetPoint("TOPLEFT", 16, -40)
    prompt.msg:SetWidth(348)
    prompt.eb = UI.EditBox(prompt, 348)
    prompt.eb:SetPoint("TOPLEFT", 16, -70)
    prompt.err = UI.Text(prompt, 11, C.danger)
    prompt.err:SetPoint("TOPLEFT", 16, -98)
    local function accept()
      local ok, err = prompt.onOk(prompt.eb:IsShown() and prompt.eb:GetText() or nil)
      if ok == false then prompt.err:SetText(err or "") else prompt:Hide() end
    end
    prompt.ok = UI.Button(prompt, "OK", 100, accept, "primary")
    prompt.ok:SetPoint("BOTTOMRIGHT", -120, 14)
    local cancel = UI.Button(prompt, "Cancel", 100, function() prompt:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", -14, 14)
    prompt.eb:SetScript("OnEnterPressed", accept)
    prompt.eb:SetScript("OnEscapePressed", function() prompt:Hide() end)
  end
  prompt.titleText:SetText(title)
  prompt.msg:SetText(text or "")
  prompt.err:SetText("")
  prompt.onOk = onOk
  if default then
    prompt.eb:SetText(default)
    prompt.eb:Show()
    prompt:Show()
    prompt.eb:SetFocus()
    prompt.eb:HighlightText()
  else
    prompt.eb:Hide()
    prompt:Show()
  end
end

local function Report(ok, err)
  if ok == false and err then Print(err) end
  return ok, err
end
TD.Report = Report

-------------------------------------------------------------------------------
-- Main window
-------------------------------------------------------------------------------
local win, content
local pages, navs = {}, {}
TD.positionHooks = TD.positionHooks or {}

local NAV = {
  { "home",     "Home",              "Interface\\Icons\\INV_Misc_Book_09" },
  { "plates",   "Nameplate numbers", "Interface\\Icons\\Ability_Hunter_SniperShot" },
  { "meter",    "Threat meter",      "Interface\\Icons\\INV_Misc_Spyglass_03" },
  { "profiles", "Profiles",          "Interface\\Icons\\INV_Misc_Note_01" },
  { "advanced", "Advanced",          "Interface\\Icons\\Trade_Engineering" },
}

local function ShowPage(key)
  UI.CloseList()
  for k, p in pairs(pages) do p.frame:SetShown(k == key) end
  for k, b in pairs(navs) do
    local on = (k == key)
    b.locked = on
    UI.SetFill(b.bg, on and { 0.10, 0.12, 0.16, 1 } or { 0, 0, 0, 0 })
    b.marker:SetShown(on)
    b.label:SetTextColor(on and 1 or C.dim[1], on and 1 or C.dim[2], on and 1 or C.dim[3])
  end
  if win then win.page = key end
end

-- HOME -----------------------------------------------------------------------
local function BuildHome()
  local page = UI.Page(content, "Welcome to ThreatDiff",
    "See exactly how much threat you have on every enemy, and how close you are to pulling aggro.")
  pages.home = page

  local card = UI.Card(page, "How to read the numbers")
  -- a little example nameplate
  local demo = CreateFrame("Frame", nil, card)
  demo:SetPoint("TOPLEFT", 16, card.y - 6)
  demo:SetSize(230, 60)
  UI.Fill(demo, { 0.05, 0.06, 0.08, 1 })
  UI.Border(demo, C.cardEdge)
  local bar = UI.Line(demo, "ARTWORK", 0.72, 0.1, 0.1, 1)
  bar:SetSize(110, 10); bar:SetPoint("CENTER", 34, -6)
  local barBg = UI.Line(demo, "BORDER", 0, 0, 0, 1)
  barBg:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1); barBg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
  local mob = UI.Text(demo, 10, { 1, 0.82, 0 })
  mob:SetPoint("BOTTOM", bar, "TOP", 0, 3); mob:SetText("Defias Bandit")
  local num = UI.Text(demo, 14)
  num:SetPoint("RIGHT", bar, "LEFT", -6, 0)
  num:SetText("+1.2k")
  UI.OnRefresh(function() local c = TD.db.colors.SECURE; num:SetTextColor(c[1], c[2], c[3]) end)
  local ex = UI.Text(card, 11)
  ex:SetPoint("TOPLEFT", 262, card.y - 4)
  ex:SetWidth(284)
  ex:SetSpacing(3)
  ex:SetText("|cff66ff66+|r  You're ahead of everyone else by that much threat.\n"
    .. "|cffff6666-|r  Someone has more threat than you.\n"
    .. "|cffb0b0b0Tanks want big + numbers. Damage and healers want to stay in the minus.|r")
  card.y = card.y - 78
  UI.EndCard(card)

  card = UI.Card(page, "Quick setup")
  local row = UI.Row(card, "Threat numbers on nameplates", "The number next to every enemy you're fighting.")
  row.Control(UI.Toggle(row, Getter("enabled"), Setter("enabled")))
  row = UI.Row(card, "Threat meter window", "A list of everyone's threat on your target, with pull warnings.")
  row.Control(UI.Toggle(row, Getter("meter.enabled"), Setter("meter.enabled")))
  row = UI.Row(card, "Minimap button", "Left-click opens these settings. Right-click shows or hides the meter.")
  row.Control(UI.Toggle(row, function() return TD.MinimapShown and TD.MinimapShown() end,
    function(v) if TD.SetMinimapShown then TD.SetMinimapShown(v) end end))
  row = UI.Row(card, "I usually play as", "Changes the colours and what counts as \"safe\". Auto uses your group role or stance.")
  row.Control(UI.Segmented(row, { { "AUTO", "Auto" }, { "TANK", "Tank" }, { "DPS", "Damage / Heal" } }, 290,
    Getter("role"), Setter("role")))
  row = UI.Row(card, "Try it out", "Puts sample numbers on nameplates and in the meter, so you can see and place them.")
  local prev = row.Control(UI.Button(row, "Preview", 110, function() TD:SetTestMode(not TD.testMode) end, "primary"), nil, 246)
  UI.OnRefresh(function() prev:SetText(TD.testMode and "Stop preview" or "Preview") end)
  local mv = UI.Button(row, "Move the number", 130, function() TD:ToggleEditor(true) end)
  mv:SetPoint("RIGHT", prev, "LEFT", -6, 0)
  UI.EndCard(card)

  card = UI.Card(page, "What the colours mean", "Click a colour to change it.")
  local function Legend(key, x, y)
    local sw = UI.Swatch(card, function() return TD.db.colors[key] end, 16)
    sw:SetPoint("TOPLEFT", x, y)
    local s = UI.Text(card, 12)
    s:SetPoint("LEFT", sw, "RIGHT", 8, 0); s:SetWidth(44); s:SetText(SAMPLE[key])
    UI.OnRefresh(function() local c = TD.db.colors[key]; s:SetTextColor(c[1], c[2], c[3]) end)
    local l = UI.Text(card, 11, C.dim)
    l:SetPoint("LEFT", s, "RIGHT", 2, 0); l:SetText(TD.PLAIN[key])
  end
  local h1 = UI.Text(card, 11, C.accent); h1:SetPoint("TOPLEFT", 16, card.y); h1:SetText("When you're tanking")
  local h2 = UI.Text(card, 11, C.accent); h2:SetPoint("TOPLEFT", 290, card.y); h2:SetText("When you're damage or healing")
  local y0 = card.y - 20
  for i, key in ipairs({ "SECURE", "TANKING", "INSECURE", "OTHERTANK", "LOOSE" }) do Legend(key, 16, y0 - (i - 1) * 22) end
  for i, key in ipairs({ "SAFE", "WARN", "DANGER", "AGGRO", "PET" }) do Legend(key, 290, y0 - (i - 1) * 22) end
  card.y = y0 - 5 * 22 - 4
  UI.EndCard(card)
end

-- NAMEPLATES -----------------------------------------------------------------
local function BuildPlates()
  local page = UI.Page(content, "Nameplate numbers",
    "The number next to each enemy's nameplate: your threat compared with the highest threat on that enemy.")
  pages.plates = page

  local card = UI.Card(page, "When to show it")
  local row = UI.Row(card, "Show threat numbers", "Only on enemies you're actually fighting; cleared when combat ends.")
  row.Control(UI.Toggle(row, Getter("enabled"), Setter("enabled")))
  row = UI.Row(card, "Show them when I'm", "Pick every situation where you want numbers.")
  row.Control(UI.Chips(row, {
    { "Solo", Getter("showSolo"), Setter("showSolo") }, { "With pet", Getter("showPet"), Setter("showPet") },
    { "Party", Getter("showParty"), Setter("showParty") }, { "Raid", Getter("showRaid"), Setter("showRaid") },
  }, 250))
  row = UI.Row(card, "Hide it while I'm safe", "Damage and healers: the number only appears once you get close to pulling.")
  row.Control(UI.Toggle(row, Getter("hideSafe"), Setter("hideSafe")))
  UI.EndCard(card)

  card = UI.Card(page, "What the number measures",
    "Tanks always see their lead over the next person. Choose what damage and healers see.")
  row = UI.Row(card, "For damage and healers, show",
    "Gap to top: how far behind the highest threat. Until pull: how much more you can do safely.")
  row.Control(UI.Segmented(row, { { "TOP", "Gap to top" }, { "PULL", "Until pull" } }, 220,
    Getter("dpsRef"), Setter("dpsRef")))
  UI.EndCard(card)

  card = UI.Card(page, "Look")
  row = UI.Row(card, "Font")
  row.Control(UI.Dropdown(row, 220, FontOptions("font"), Getter("font"), Setter("font")))
  row = UI.Row(card, "Size")
  row.Control(UI.Slider(row, { min = 6, max = 40, step = 1, suffix = " pt" }, Getter("fontSize"), Setter("fontSize")))
  row = UI.Row(card, "Outline", "A dark edge around the text so it reads on any background.")
  row.Control(UI.Segmented(row, { { "NONE", "None" }, { "OUTLINE", "Thin" }, { "THICK", "Thick" } }, 220,
    Getter("outline"), Setter("outline")))
  row = UI.Row(card, "Drop shadow")
  row.Control(UI.Toggle(row, Getter("shadow"), Setter("shadow")))
  row = UI.Row(card, "Short numbers", "Shows 1,234 as 1.2k and 1,500,000 as 1.50m.")
  row.Control(UI.Toggle(row, Getter("abbreviate"), Setter("abbreviate")))
  row = UI.Row(card, "Decimal places", "For short numbers: 1k, 1.2k or 1.23k.")
  row.Control(UI.Segmented(row, { { 0, "1k" }, { 1, "1.2k" }, { 2, "1.23k" } }, 180,
    Getter("decimals"), Setter("decimals")))
  row = UI.Row(card, "Show + on a lead")
  row.Control(UI.Toggle(row, Getter("showPlus"), Setter("showPlus")))
  row = UI.Row(card, "Show - on a gap")
  row.Control(UI.Toggle(row, Getter("showMinus"), Setter("showMinus")))
  row = UI.Row(card, "Show !!! when tied", "Instead of 0, when you and the top threat are dead even.")
  row.Control(UI.Toggle(row, Getter("bangOnTie"), Setter("bangOnTie")))
  UI.EndCard(card)

  card = UI.Card(page, "Position",
    "Where the number sits next to the nameplate. Offsets are in nameplate units, accurate to 0.01.")
  row = UI.Row(card, "Place the number")
  row.Control(UI.Dropdown(row, 220, PlaceOptions, CurrentPlace, SetPlace))
  row = UI.Row(card, "Line it up with", "Health bar follows Blizzard's (or Plater's) bar when it can find one.")
  row.Control(UI.Segmented(row, { { "PLATE", "Whole nameplate" }, { "HEALTH", "Health bar" } }, 240,
    Getter("anchorTo"), Setter("anchorTo")))
  row = UI.Row(card, "Exact offset", "Type a value and press Enter. +/- steps 1, Shift 0.1, Ctrl 0.01.", 50)
  local yBox = row.Control(UI.NumberBox(row, { step = 1, dec = 2, width = 64, min = -500, max = 500 },
    function() return TD.db.y end, function(v) TD:SetPosition(TD.db.x, v) end, TD.positionHooks), nil, 258)
  local yl = UI.Text(row, 12, C.dim); yl:SetPoint("RIGHT", yBox, "LEFT", -6, 0); yl:SetText("Y")
  local xBox = UI.NumberBox(row, { step = 1, dec = 2, width = 64, min = -500, max = 500 },
    function() return TD.db.x end, function(v) TD:SetPosition(v, TD.db.y) end, TD.positionHooks)
  xBox:SetPoint("RIGHT", yl, "LEFT", -12, 0)
  local xl = UI.Text(row, 12, C.dim); xl:SetPoint("RIGHT", xBox, "LEFT", -6, 0); xl:SetText("X")
  row = UI.Row(card, "Drag it into place", "A zoomed-in nameplate you can drag the number around on.")
  row.Control(UI.Button(row, "Open position editor", 170, function() TD:ToggleEditor(true) end, "primary"))
  UI.EndCard(card)

  card = UI.Card(page, "Colours", "Click a colour to change it.")
  local h1 = UI.Text(card, 11, C.accent); h1:SetPoint("TOPLEFT", 16, card.y); h1:SetText("When you're tanking")
  local h2 = UI.Text(card, 11, C.accent); h2:SetPoint("TOPLEFT", 290, card.y); h2:SetText("When you're damage or healing")
  local function Colour(key, x, y)
    local sw = UI.Swatch(card, function() return TD.db.colors[key] end, 16)
    sw:SetPoint("TOPLEFT", x, y)
    local l = UI.Text(card, 11)
    l:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    l:SetText(TD.PLAIN[key])
  end
  local y0 = card.y - 20
  for i, key in ipairs({ "SECURE", "TANKING", "INSECURE", "OTHERTANK", "LOOSE" }) do Colour(key, 16, y0 - (i - 1) * 24) end
  for i, key in ipairs({ "SAFE", "WARN", "DANGER", "AGGRO", "PET" }) do Colour(key, 290, y0 - (i - 1) * 24) end
  card.y = y0 - 5 * 24 - 6
  local rc = UI.Button(card, "Reset colours", 130, function()
    for k, c in pairs(TD.DEFAULTS.colors) do TD.db.colors[k] = { c[1], c[2], c[3] } end
    TD:ApplySettings()
  end)
  rc:SetPoint("TOPLEFT", 16, card.y)
  card.y = card.y - 30
  UI.EndCard(card)

  card = UI.Card(page, "Warning levels")
  row = UI.Row(card, "Tanks: measure the safe lead as", "Green once your lead is this big.")
  row.Control(UI.Segmented(row, { { "PCT", "% of my threat" }, { "ABS", "Fixed amount" } }, 220,
    Getter("secureMode"), Setter("secureMode")))
  row = UI.Row(card, "Tanks: safe lead", "25% means the next person has 75% of your threat or less.")
  local pct = row.Control(UI.Slider(row, { min = 5, max = 95, step = 5, suffix = "%" }, Getter("secureValue"), Setter("secureValue")))
  local abs = row.Control(UI.NumberBox(row, { step = 500, dec = 0, width = 90, min = 0, max = 10000000 },
    Getter("secureValue"), function(v) TD.db.secureValue = v; UI.Changed() end))
  UI.OnRefresh(function()
    local isAbs = TD.db.secureMode == "ABS"
    pct:SetShown(not isAbs); abs:SetShown(isAbs)
    if not isAbs and (TD.db.secureValue < 5 or TD.db.secureValue > 95) then TD.db.secureValue = 25 end
  end)
  row = UI.Row(card, "Damage and healers: warn at", "Turns yellow at this share of the way to pulling.")
  row.Control(UI.Slider(row, { min = 10, max = 100, step = 5, suffix = "%" }, Getter("warnPct"), Setter("warnPct")))
  row = UI.Row(card, "Damage and healers: danger at", "Turns orange at this share of the way to pulling.")
  row.Control(UI.Slider(row, { min = 10, max = 100, step = 5, suffix = "%" }, Getter("dangerPct"), Setter("dangerPct")))
  UI.EndCard(card)
end

-- METER ----------------------------------------------------------------------
local function BuildMeter()
  local page = UI.Page(content, "Threat meter",
    "A damage-meter style list of everyone's threat on your target, with rows showing where aggro would be pulled.")
  pages.meter = page

  local card = UI.Card(page, "Window")
  local row = UI.Row(card, "Show the threat meter", "Typing /tdiff meter also brings it back.")
  row.Control(UI.Toggle(row, Getter("meter.enabled"), Setter("meter.enabled")))
  row = UI.Row(card, "Lock position and size", "Stops accidental dragging and resizing.")
  row.Control(UI.Toggle(row, Getter("meter.locked"), Setter("meter.locked")))
  row = UI.Row(card, "Only show in combat")
  row.Control(UI.Toggle(row, Getter("meter.hideOOC"), Setter("meter.hideOOC")))
  row = UI.Row(card, "Collapsed", "Just the title bar. You can also click the - / + on the meter.")
  row.Control(UI.Toggle(row, Getter("meter.collapsed"), Setter("meter.collapsed")))
  row = UI.Row(card, "Preview", "Fills the meter with sample data so you can style it.")
  local pv = row.Control(UI.Button(row, "Preview", 110, function() TD:SetTestMode(not TD.testMode) end, "primary"), nil, 236)
  UI.OnRefresh(function() pv:SetText(TD.testMode and "Stop preview" or "Preview") end)
  local rp = UI.Button(row, "Reset position", 120, function() TD.MeterResetPosition() end)
  rp:SetPoint("RIGHT", pv, "LEFT", -6, 0)
  UI.EndCard(card)

  card = UI.Card(page, "Rows")
  row = UI.Row(card, "Pull warning rows", "Red rows at the threat where someone would pull aggro (the game's 110% / 130% rule).")
  row.Control(UI.Dropdown(row, 230, {
    { "BOTH", "Melee and ranged" }, { "MELEE", "Melee only" }, { "RANGED", "Ranged only" },
    { "MINE", "Just my own pull point" }, { "OFF", "None" } }, Getter("meter.pullRows"), Setter("meter.pullRows")))
  row = UI.Row(card, "Numbers on each row", "Difference from me: how far above or below you each person is.")
  row.Control(UI.Dropdown(row, 230, {
    { "PCT", "Threat and % of tank" }, { "THREAT", "Threat only" }, { "GAP", "Threat and difference from me" } },
    Getter("meter.valueFormat"), Setter("meter.valueFormat")))
  row = UI.Row(card, "Class colours")
  row.Control(UI.Toggle(row, Getter("meter.classColors"), Setter("meter.classColors")))
  row = UI.Row(card, "Class icons")
  row.Control(UI.Toggle(row, Getter("meter.classIcons"), Setter("meter.classIcons")))
  row = UI.Row(card, "Rank numbers", "1., 2., 3. in front of names.")
  row.Control(UI.Toggle(row, Getter("meter.rankNumbers"), Setter("meter.rankNumbers")))
  row = UI.Row(card, "Highlight my row")
  row.Control(UI.Toggle(row, Getter("meter.highlightYou"), Setter("meter.highlightYou")))
  UI.EndCard(card)

  card = UI.Card(page, "Size", "You can also drag the meter's bottom-right corner.")
  row = UI.Row(card, "Width")
  row.Control(UI.Slider(row, { min = 140, max = 800, step = 10, suffix = " px" }, Getter("meter.width"), Setter("meter.width")))
  local hRow = UI.Row(card, "Height", "")
  hRow.Control(UI.Slider(hRow, { min = 40, max = 1200, step = 5, suffix = " px" }, Getter("meter.height"), Setter("meter.height")))
  UI.OnRefresh(function()
    local r = TD.MeterRowsFit and TD.MeterRowsFit() or 0
    hRow.desc:SetText("The window keeps this size - fits " .. r .. (r == 1 and " row" or " rows") .. ".")
  end)
  row = UI.Row(card, "Bar height")
  row.Control(UI.Slider(row, { min = 6, max = 40, step = 1, suffix = " px" }, Getter("meter.barHeight"), Setter("meter.barHeight")))
  row = UI.Row(card, "Space between bars")
  row.Control(UI.Slider(row, { min = 0, max = 10, step = 1, suffix = " px" }, Getter("meter.spacing"), Setter("meter.spacing")))
  UI.EndCard(card)

  card = UI.Card(page, "Look")
  row = UI.Row(card, "Bar style")
  row.Control(UI.Dropdown(row, 220, TD.MeterStyleOptions, Getter("meter.barStyle"), Setter("meter.barStyle")))
  row = UI.Row(card, "Font")
  row.Control(UI.Dropdown(row, 220, FontOptions("meter.font"), Getter("meter.font"), Setter("meter.font")))
  row = UI.Row(card, "Font size")
  row.Control(UI.Slider(row, { min = 6, max = 30, step = 1, suffix = " pt" }, Getter("meter.fontSize"), Setter("meter.fontSize")))
  row = UI.Row(card, "Outline")
  row.Control(UI.Segmented(row, { { "NONE", "None" }, { "OUTLINE", "Thin" }, { "THICK", "Thick" } }, 220,
    Getter("meter.outline"), Setter("meter.outline")))
  UI.EndCard(card)

  card = UI.Card(page, "See-through", "0% is invisible, 100% is solid.")
  row = UI.Row(card, "Background")
  row.Control(UI.Slider(row, { min = 0, max = 1, step = 0.05, scale = 100, suffix = "%" }, Getter("meter.bgAlpha"), Setter("meter.bgAlpha")))
  row = UI.Row(card, "Bars")
  row.Control(UI.Slider(row, { min = 0, max = 1, step = 0.05, scale = 100, suffix = "%" }, Getter("meter.barAlpha"), Setter("meter.barAlpha")))
  row = UI.Row(card, "Bar backdrop", "The dim track behind each bar.")
  row.Control(UI.Slider(row, { min = 0, max = 1, step = 0.05, scale = 100, suffix = "%" }, Getter("meter.barBgAlpha"), Setter("meter.barBgAlpha")))
  row = UI.Row(card, "Border")
  row.Control(UI.Toggle(row, Getter("meter.border"), Setter("meter.border")))
  UI.EndCard(card)
end

-- PROFILES -------------------------------------------------------------------
local function BuildProfiles()
  local page = UI.Page(content, "Profiles",
    "Profiles save automatically. Each character remembers which one it uses.")
  pages.profiles = page

  local card = UI.Card(page, "Current profile")
  local active = UI.Row(card, "Active profile", " ")
  active.Control(UI.Dropdown(active, 220, function()
      local l = {}
      for i, n in ipairs(TD:GetProfiles()) do l[i] = { n, n } end
      return l
    end, function() return TD.profileName end,
    function(v) if v ~= TD.profileName then Report(TD:SetProfile(v)) end end))
  UI.OnRefresh(function()
    local users = TD:ProfileUsers(TD.profileName)
    active.desc:SetText(#users > 0 and ("Used by " .. table.concat(users, ", ")) or "Not used by any character yet")
  end)
  local row = UI.Row(card, "Make a new one", "Start fresh, or copy what you have now.")
  local dup = row.Control(UI.Button(row, "Duplicate", 100, function()
    TD:Prompt("Duplicate profile", "Name for a copy of \"" .. TD.profileName .. "\":", TD.profileName .. " copy",
      function(text) return TD:NewProfile(text, TD.profileName) end)
  end), nil, 186)
  local new = UI.Button(row, "New", 80, function()
    TD:Prompt("New profile", "Name for the new profile (starts from default settings):", "",
      function(text) return TD:NewProfile(text) end)
  end, "primary")
  new:SetPoint("RIGHT", dup, "LEFT", -6, 0)
  row = UI.Row(card, "Rename or reset", "Reset puts every setting in this profile back to default.")
  local rs = row.Control(UI.Button(row, "Reset", 80, function()
    TD:Prompt("Reset profile", "Put every setting in \"" .. TD.profileName .. "\" back to default?", nil,
      function() TD:ResetProfile(); return true end)
  end, "danger"), nil, 186)
  local rn = UI.Button(row, "Rename", 100, function()
    if TD.profileName == "Default" then return Print("the Default profile can't be renamed.") end
    TD:Prompt("Rename profile", "New name for \"" .. TD.profileName .. "\":", TD.profileName,
      function(text) return TD:RenameProfile(TD.profileName, text) end)
  end)
  rn:SetPoint("RIGHT", rs, "LEFT", -6, 0)
  UI.EndCard(card)

  card = UI.Card(page, "Copy and delete")
  local function Others(includeDefault)
    return function()
      local l = {}
      for _, n in ipairs(TD:GetProfiles()) do
        if n ~= TD.profileName and (includeDefault or n ~= "Default") then l[#l + 1] = { n, n } end
      end
      if #l == 0 then l[1] = { false, "(no other profiles)" } end
      return l
    end
  end
  local copyFrom, delName = false, false
  local function Valid(v, fn)
    local l = fn()
    for _, o in ipairs(l) do if o[1] == v then return v end end
    return l[1][1]
  end
  local copyList, delList = Others(true), Others(false)
  row = UI.Row(card, "Copy settings from", "Replaces everything in the current profile.")
  local cb = row.Control(UI.Button(row, "Copy", 70, function()
    if not copyFrom then return end
    TD:Prompt("Copy profile", "Replace everything in \"" .. TD.profileName .. "\" with the settings from \""
      .. copyFrom .. "\"?", nil, function() return TD:CopyProfile(copyFrom) end)
  end), nil, 226)
  local cd = UI.Dropdown(row, 150, copyList, function() copyFrom = Valid(copyFrom, copyList); return copyFrom end,
    function(v) copyFrom = v end)
  cd:SetPoint("RIGHT", cb, "LEFT", -6, 0)
  row = UI.Row(card, "Delete a profile", "This can't be undone. The Default profile always stays.")
  local db = row.Control(UI.Button(row, "Delete", 70, function()
    if not delName then return end
    TD:Prompt("Delete profile", "Delete the profile \"" .. delName .. "\"? This can't be undone.", nil,
      function() return TD:DeleteProfile(delName) end)
  end, "danger"), nil, 226)
  local dd = UI.Dropdown(row, 150, delList, function() delName = Valid(delName, delList); return delName end,
    function(v) delName = v end)
  dd:SetPoint("RIGHT", db, "LEFT", -6, 0)
  -- dim Copy / Delete when there's nothing to act on
  UI.OnRefresh(function()
    cb:SetAlpha(Valid(copyFrom, copyList) and 1 or 0.35)
    db:SetAlpha(Valid(delName, delList) and 1 or 0.35)
  end)
  UI.EndCard(card)

  card = UI.Card(page, "Tip",
    "Make a profile per role (Tank / Damage) or per content (Dungeons / Raids), then switch with "
    .. "/tdiff profile use <name> - handy in a macro.")
  UI.EndCard(card)
end

-- ADVANCED -------------------------------------------------------------------
local statRow
local function BuildAdvanced()
  local page = UI.Page(content, "Advanced", "Fine-tuning and troubleshooting. The defaults are fine for most players.")
  pages.advanced = page

  local card = UI.Card(page, "Speed")
  local row = UI.Row(card, "Nameplate refresh", "Seconds between updates. Lower is snappier but does a little more work.")
  row.Control(UI.Slider(row, { min = 0.05, max = 1, step = 0.05, dec = 2, suffix = " s" }, Getter("interval"), Setter("interval")))
  row = UI.Row(card, "Meter refresh")
  row.Control(UI.Slider(row, { min = 0.05, max = 1, step = 0.05, dec = 2, suffix = " s" }, Getter("meter.interval"), Setter("meter.interval")))
  row = UI.Row(card, "Keep the last number",
    "The game hides threat on mobs no one is targeting. Keep their last number (dimmed) this long.")
  row.Control(UI.Slider(row, { min = 0, max = 60, step = 1, suffix = " s" }, Getter("keepLast"), Setter("keepLast")))
  statRow = UI.Row(card, "Right now", "measuring...")
  UI.EndCard(card)

  card = UI.Card(page, "Custom anchor points",
    "Which point of the number attaches to which point of the nameplate. \"Place the number\" on the Nameplate page sets these for you.")
  row = UI.Row(card, "Point on the number")
  row.Control(UI.Dropdown(row, 200, POINT_NAMES, Getter("point"), Setter("point")))
  row = UI.Row(card, "Point on the nameplate")
  row.Control(UI.Dropdown(row, 200, POINT_NAMES, Getter("relPoint"), Setter("relPoint")))
  UI.EndCard(card)

  card = UI.Card(page, "Troubleshooting")
  row = UI.Row(card, "Threat probe", "Prints what threat data the game lets addons read. Useful for bug reports.")
  row.Control(UI.Button(row, "Run probe", 120, function() SlashCmdList.THREATDIFF("probe") end))
  row = UI.Row(card, "Chat commands", "Lists every /tdiff command in chat.")
  row.Control(UI.Button(row, "Show commands", 120, function() SlashCmdList.THREATDIFF("help") end))
  row = UI.Row(card, "Start over", "Puts every setting in this profile back to default.")
  row.Control(UI.Button(row, "Reset profile", 120, function()
    TD:Prompt("Reset profile", "Put every setting in \"" .. TD.profileName .. "\" back to default?", nil,
      function() TD:ResetProfile(); return true end)
  end, "danger"))
  UI.EndCard(card)
end

local function Build()
  win = UI.Window("ThreatDiffConfig", 800, 560, "")
  win.titleText:Hide()

  -- sidebar
  local side = CreateFrame("Frame", nil, win)
  side:SetPoint("TOPLEFT", 1, -3)
  side:SetPoint("BOTTOMLEFT", 1, 1)
  side:SetWidth(190)
  UI.Fill(side, C.side)
  local logo = side:CreateTexture(nil, "ARTWORK")
  logo:SetSize(34, 34)
  logo:SetPoint("TOPLEFT", 16, -16)
  logo:SetTexture("Interface\\Icons\\Ability_Warrior_DefensiveStance")
  logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local name = UI.Text(side, 16)
  name:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
  name:SetText("ThreatDiff")
  local sub = UI.Text(side, 10, C.accent)
  sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  sub:SetText("FOREVER")

  for i, n in ipairs(NAV) do
    local b = CreateFrame("Button", nil, side)
    b:SetSize(190, 36)
    b:SetPoint("TOPLEFT", 0, -72 - (i - 1) * 38)
    b.bg = UI.Fill(b, { 0, 0, 0, 0 })
    b.marker = UI.Line(b, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
    b.marker:SetPoint("TOPLEFT"); b.marker:SetPoint("BOTTOMLEFT"); b.marker:SetWidth(3)
    b.marker:Hide()
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetSize(20, 20)
    ic:SetPoint("LEFT", 16, 0)
    ic:SetTexture(n[3])
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.label = UI.Text(b, 12, C.dim)
    b.label:SetPoint("LEFT", ic, "RIGHT", 10, 0)
    b.label:SetText(n[2])
    b:HookScript("OnEnter", function(self) if not self.locked then UI.SetFill(self.bg, { 0.08, 0.09, 0.12, 1 }) end end)
    b:HookScript("OnLeave", function(self) if not self.locked then UI.SetFill(self.bg, { 0, 0, 0, 0 }) end end)
    b:SetScript("OnClick", function() ShowPage(n[1]) end)
    navs[n[1]] = b
  end

  local help = UI.Text(side, 10, C.dim)
  help:SetPoint("BOTTOMLEFT", 16, 16)
  help:SetWidth(160)
  help:SetText("Type |cff4fc3f7/tdiff|r to open this window.\n|cff4fc3f7/tdiff help|r lists every command.")

  -- profile badge (top right)
  local badge = UI.Text(win, 11, C.dim)
  badge:SetPoint("TOPRIGHT", -40, -12)
  UI.OnRefresh(function() badge:SetText("Profile  |cffffffff" .. (TD.profileName or "?") .. "|r") end)

  content = CreateFrame("Frame", nil, win)
  content:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, -30)
  content:SetPoint("BOTTOMRIGHT", -1, 1)

  BuildHome(); BuildPlates(); BuildMeter(); BuildProfiles(); BuildAdvanced()

  local ticker
  local function Stats()
    local s = TD:GetStats()
    statRow.desc:SetText(format("%d numbers showing (%d dimmed)  -  %.1f updates/s  -  %.0f threat reads/s",
      s.shown, s.dimmed, s.evalsPerSec, s.apiPerSec))
  end
  win:SetScript("OnShow", function()
    UI.RefreshAll()
    for i = 1, #TD.positionHooks do TD.positionHooks[i]() end
    TD:GetStats()
    ticker = C_Timer.NewTicker(2, Stats)
  end)
  win:SetScript("OnHide", function()
    UI.CloseList()
    if ticker then ticker:Cancel(); ticker = nil end
  end)
  ShowPage("home")
end

function TD:ToggleConfig(show, page)
  if not win then Build() end
  if show == nil then show = not win:IsShown() end
  if page and pages[page] then ShowPage(page) end
  win:SetShown(show)
end
TD.OptionsRefresh = function() if win and win:IsShown() then UI.RefreshAll() end end
