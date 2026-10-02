--[[ ThreatDiff - threat meter (damage-meter style).

  One ranked row per group member on your target's threat table, highest
  first, with class colours and icons. "Melee pull at" and "Ranged pull at"
  rows (the aggro holder's threat x1.1 / x1.3) are sorted in with everyone
  else, so you can see who is closest to pulling. If you target a friend
  (a healer on the tank), it follows their target instead.

  Light by design: its events only set a flag, and one throttled timer
  redraws (default 5 times a second). Rows are created once and reused, and
  sorting happens in place on reused arrays. When the meter is hidden its
  events are unregistered, so it costs nothing.
]]

local _, ns = ...
local TD = ns.TD

local UDTS = UnitDetailedThreatSituation
local issecret = _G.issecretvalue or function() return false end
local floor, max, min, format = math.floor, math.max, math.min, string.format
local pcall, type, select = pcall, type, select

local WHITE = "Interface\\Buttons\\WHITE8x8"
local HEADER_H, PAD = 20, 2

local STYLES = {
  { "BLIZZARD", "Blizzard",  "Interface\\TargetingFrame\\UI-StatusBar" },
  { "FLAT",     "Flat",      WHITE },
  { "GLOSS",    "Glossy",    WHITE, gloss = true },
  { "RAID",     "Raid",      "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
  { "THIN",     "Thin line", WHITE, thin = true },
}
local STYLE_BY_KEY = {}
for _, st in ipairs(STYLES) do STYLE_BY_KEY[st[1]] = st end

local function LSM() return _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true) end

-- Options list for the "Bar style" picker: built-ins + LibSharedMedia bars.
function TD.MeterStyleOptions()
  local list = {}
  for i, st in ipairs(STYLES) do list[i] = { st[1], st[2] } end
  local lsm = LSM()
  if lsm then
    for _, name in ipairs(lsm:List("statusbar")) do list[#list + 1] = { "LSM:" .. name, name } end
  end
  return list
end

local function StyleFor(key)
  local st = STYLE_BY_KEY[key]
  if st then return st[3], st.gloss, st.thin end
  if type(key) == "string" and key:find("^LSM:") then
    local lsm = LSM()
    local path = lsm and lsm:Fetch("statusbar", key:sub(5), true)
    if path then return path, false, false end
  end
  return STYLES[1][3], false, false
end

local OUTLINES = { NONE = "", OUTLINE = "OUTLINE", THICK = "THICKOUTLINE" }
local PET_COLOR = { r = 0.35, g = 0.8, b = 0.35 }
local PULL_COLOR = { r = 0.75, g = 0.08, b = 0.08 }
local GREY = { r = 0.7, g = 0.7, b = 0.7 }

local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local ICON_PET = "Interface\\Icons\\Ability_Hunter_BeastTaming"
local ICON_MELEE = "Interface\\Icons\\INV_Sword_04"
local ICON_RANGED = "Interface\\Icons\\INV_Weapon_Bow_07"
local ICON_MINE = "Interface\\Icons\\Ability_Warrior_Charge"
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Pseudo-units for the pull rows.
local PULL_MELEE, PULL_RANGED, PULL_MINE = "@melee", "@ranged", "@mine"
local PULL_LABEL = { [PULL_MELEE] = "Melee pull at", [PULL_RANGED] = "Ranged pull at", [PULL_MINE] = "Your pull at" }
local PULL_ICON = { [PULL_MELEE] = ICON_MELEE, [PULL_RANGED] = ICON_RANGED, [PULL_MINE] = ICON_MINE }

local meter, header, body, collapseBtn, optBtn, closeBtn, nameFS, titleFS, diffFS, emptyFS, grip
local rows = {}
-- Parallel arrays, reused on every redraw (no garbage): unit, value, holds aggro, display name, class
local order, vals, tanking, names, classes = {}, {}, {}, {}, {}
local pending = false
local lastH
local MDB -- TD.db.meter

local function SetFont(fs, size)
  TD.ApplyFont(fs, MDB.font, size or MDB.fontSize, OUTLINES[MDB.outline] or "")
end

local function RowY(i) return -(i - 1) * (MDB.barHeight + MDB.spacing) end

-- The window keeps the size you give it; it shows as many top rows as fit.
function TD.MeterHeightFor(count, barHeight, spacing)
  return HEADER_H + PAD * 2 + 1 + count * (barHeight + spacing) - spacing
end

local function MinHeight() return TD.MeterHeightFor(1, MDB.barHeight, MDB.spacing) end

local function RowsThatFit()
  local avail = MDB.height - (HEADER_H + PAD * 2 + 1)
  return max(0, floor((avail + MDB.spacing) / (MDB.barHeight + MDB.spacing)))
end

function TD.MeterRowsFit()
  MDB = TD.db.meter
  return RowsThatFit()
end

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------
local function StyleRow(r)
  local tex, gloss, thin = StyleFor(MDB.barStyle)
  local h = MDB.barHeight
  r:SetHeight(h)
  r.icon:SetSize(h, h)
  r.icon:SetShown(MDB.classIcons)
  local left = MDB.classIcons and (h + 1) or 0
  r.bar:ClearAllPoints()
  if thin then
    r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", left, 0)
    r.bar:SetPoint("BOTTOMRIGHT")
    r.bar:SetHeight(max(2, floor(h * 0.18 + 0.5)))
  else
    r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", left, 0)
    r.bar:SetPoint("BOTTOMRIGHT")
  end
  r.bar:SetStatusBarTexture(tex)
  r.bg:SetTexture(tex)
  r.hl:ClearAllPoints()
  r.hl:SetPoint("TOPLEFT", r, "TOPLEFT", left, 0)
  r.hl:SetPoint("BOTTOMRIGHT")
  if gloss then
    r.gloss:ClearAllPoints()
    r.gloss:SetPoint("TOPLEFT", r.bar, "TOPLEFT"); r.gloss:SetPoint("TOPRIGHT", r.bar, "TOPRIGHT")
    r.gloss:SetHeight(max(1, h * 0.5))
    r.gloss:SetTexture(WHITE)
    if r.gloss.SetGradient and _G.CreateColor then
      pcall(r.gloss.SetGradient, r.gloss, "VERTICAL", _G.CreateColor(1, 1, 1, 0.02), _G.CreateColor(1, 1, 1, 0.28))
    else
      r.gloss:SetVertexColor(1, 1, 1, 0.15)
    end
    r.gloss:Show()
  else
    r.gloss:Hide()
  end
  SetFont(r.name); SetFont(r.value)
  local dy = thin and 2 or 0
  r.value:ClearAllPoints(); r.value:SetPoint("RIGHT", r, "RIGHT", -4, dy)
  r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r, "LEFT", left + 4, dy)
  r.name:SetPoint("RIGHT", r.value, "LEFT", -4, 0)
end

local function PlaceRow(r, i)
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, RowY(i))
  r:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, RowY(i))
end

local function NewRow(i)
  local r = CreateFrame("Frame", nil, body)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetPoint("LEFT")
  r.bar = CreateFrame("StatusBar", nil, r)
  r.bar:SetMinMaxValues(0, 1)
  r.bg = r.bar:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints(r.bar)
  r.gloss = r.bar:CreateTexture(nil, "OVERLAY")
  local text = CreateFrame("Frame", nil, r)
  text:SetAllPoints(r)
  text:SetFrameLevel(r.bar:GetFrameLevel() + 2)
  r.hl = text:CreateTexture(nil, "BACKGROUND")
  r.hl:SetColorTexture(1, 1, 1, 0.14)
  r.hl:Hide()
  r.aggro = text:CreateTexture(nil, "OVERLAY")
  r.aggro:SetColorTexture(1, 0.2, 0.2, 1)
  r.aggro:SetPoint("TOPLEFT", r.bar, "TOPLEFT"); r.aggro:SetPoint("BOTTOMLEFT", r.bar, "BOTTOMLEFT")
  r.aggro:SetWidth(2)
  r.name = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetTextColor(1, 1, 1)
  r.name:SetJustifyH("LEFT")
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  r.value = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.value:SetTextColor(1, 1, 1)
  r.value:SetJustifyH("RIGHT")
  rows[i] = r
  StyleRow(r)
  PlaceRow(r, i)
  return r
end

local CROP = { 0.08, 0.92, 0.08, 0.92 }

local function SetIcon(tex, path, coords)
  tex:SetTexture(path)
  coords = coords or CROP
  tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
end

local function IconFor(r, u, class)
  if PULL_ICON[u] then return SetIcon(r.icon, PULL_ICON[u]) end
  if u == "pet" or class == "PET" or (type(u) == "string" and u:find("pet%d")) then return SetIcon(r.icon, ICON_PET) end
  local tc = class and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[class]
  if tc then
    SetIcon(r.icon, CLASS_TEX, { tc[1] + 0.012, tc[2] - 0.012, tc[3] + 0.012, tc[4] - 0.012 })
  else
    SetIcon(r.icon, ICON_UNKNOWN)
  end
end

local function ColorFor(u, class)
  if PULL_LABEL[u] then return PULL_COLOR end
  if not MDB.classColors then return GREY end
  if u == "pet" or class == "PET" or (type(u) == "string" and u:find("pet%d")) then return PET_COLOR end
  local c = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
  return c or GREY
end

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------
local function Hostile(u)
  local e = UnitExists(u)
  if issecret(e) then return true end
  if not e then return false end
  local a = UnitCanAttack("player", u)
  if issecret(a) then return true end
  return a and true or false
end

local function MeterMob()
  if Hostile("target") then return "target" end
  if Hostile("targettarget") then return "targettarget" end -- healer on the tank
end

local n = 0                        -- rows in the arrays
local myV, myT, mySp, holderV, holderKnown

local function Add(u, v, t, name, class)
  n = n + 1
  order[n], vals[n], tanking[n], names[n], classes[n] = u, v, t, name, class
end

local function ClearTail()
  for i = n + 1, #order do order[i], vals[i], tanking[i], names[i], classes[i] = nil, nil, nil, nil, nil end
end

-- Pull rows: the aggro holder's threat x1.1 / x1.3 (the game's pull rule),
-- or your own exact pull point from the game's scaled percentage.
local function AddPullRows()
  local mode = MDB.pullRows
  if mode == "OFF" or not holderV or holderV <= 0 then return end
  if mode == "BOTH" or mode == "MELEE" then Add(PULL_MELEE, holderV * 1.1, false) end
  if mode == "BOTH" or mode == "RANGED" then Add(PULL_RANGED, holderV * 1.3, false) end
  if mode == "MINE" and myV and not myT and mySp and mySp > 0 then Add(PULL_MINE, myV * 100 / mySp, false) end
end

local function SortRows()
  for i = 2, n do
    local u, v, t, nm, c = order[i], vals[i], tanking[i], names[i], classes[i]
    local j = i - 1
    while j >= 1 and vals[j] < v do
      order[j + 1], vals[j + 1], tanking[j + 1], names[j + 1], classes[j + 1] =
        order[j], vals[j], tanking[j], names[j], classes[j]
      j = j - 1
    end
    order[j + 1], vals[j + 1], tanking[j + 1], names[j + 1], classes[j + 1] = u, v, t, nm, c
  end
end

-- You + your group against the mob.
local function Collect(mob)
  local units, nUnits = TD.GetGroupUnits()
  local div = TD.divisor or 1
  n = 0
  myV, myT, mySp, holderV, holderKnown = nil, nil, nil, nil, false
  local rp
  for i = 0, nUnits do
    local u = (i == 0) and "player" or units[i]
    local t, _, sp, rawp, v = UDTS(u, mob)
    if not issecret(v) and v then -- on the threat table (0 counts, like a fresh pet)
      if issecret(t) then t = false end
      t = t and true or false
      v = v / div
      Add(u, v, t, nil, nil)
      if t then holderV, holderKnown = v, true end
      if i == 0 then
        myV, myT = v, t
        if not issecret(sp) then mySp = sp end
        if not issecret(rawp) then rp = rawp end
      end
    end
  end
  -- aggro holder outside your group: work it out from your share of its threat
  if not holderKnown and myV and rp and rp > 0 then holderV = myV * 100 / rp end
  if not holderV and n > 0 then
    for i = 1, n do if not holderV or vals[i] > holderV then holderV = vals[i] end end
  end
  AddPullRows()
  ClearTail()
  SortRows()
  return n
end

local TEST = {
  { "Thorgrim", "WARRIOR", 12500, true }, { nil, nil, 9800 }, { "Sylvie", "ROGUE", 9100 },
  { "Merra", "MAGE", 7600 }, { "Brakk", "HUNTER", 6900 }, { "Wolf", "PET", 4100 },
  { "Vex", "WARLOCK", 5200 }, { "Aldric", "PRIEST", 2400 }, { "Oona", "DRUID", 1800 },
}

local function FillTest()
  local step = TD.testStep or 0
  n = 0
  myV, myT, mySp, holderV = nil, false, nil, nil
  for i, d in ipairs(TEST) do
    local v = d[3] + ((step * (i * 37)) % 900)
    if i == 1 then v = max(v, 12900) end
    if d[1] then
      Add("test" .. i, v, d[4] or false, d[1], d[2])
    else
      Add("player", v, false, nil, nil)
      myV = v
    end
    if d[4] then holderV = v end
  end
  mySp = myV / (holderV * 1.1) * 100
  AddPullRows()
  ClearTail()
  SortRows()
  return n
end

-------------------------------------------------------------------------------
-- Redraw
-------------------------------------------------------------------------------
local function ValueText(u, v)
  local s = TD.FormatAbs(v)
  local fmt = MDB.valueFormat
  if fmt == "THREAT" then return s end
  if fmt == "GAP" then
    if not myV then return s end
    local d
    if u == "player" then -- your lead over the next person
      d = myV
      for i = 1, n do if order[i] ~= "player" and not PULL_LABEL[order[i]] then d = myV - vals[i]; break end end
    else
      d = v - myV
    end
    return s .. " |cffb0b0b0(" .. TD.BuildText(d, floor(d + 0.5)) .. ")|r"
  end
  -- default: % of the aggro holder's threat
  local p = (holderV and holderV > 0) and (v / holderV * 100) or 0
  return s .. format(" |cffb0b0b0(%.1f%%)|r", p)
end

local function PaintRow(r, i, rank, scaleMax)
  local u, v = order[i], vals[i]
  local class = classes[i]
  local label = PULL_LABEL[u]
  local name = label or names[i]
  if not label and not name then
    name = UnitName(u)
    class = select(2, UnitClass(u))
    if issecret(class) then class = nil end
  end
  r.bar:SetMinMaxValues(0, scaleMax)
  r.bar:SetValue(v)
  local c = ColorFor(u, class)
  r.bar:SetStatusBarColor(c.r, c.g, c.b, MDB.barAlpha)
  r.bg:SetVertexColor(c.r * 0.3, c.g * 0.3, c.b * 0.3, MDB.barBgAlpha)
  if MDB.classIcons then IconFor(r, u, class) end
  if label then
    r.name:SetText(label)
  elseif MDB.rankNumbers then
    if issecret(name) then r.name:SetText(name) else r.name:SetText(rank .. ". " .. (name or "?")) end
  else
    r.name:SetText(name)
  end
  r.value:SetText(ValueText(u, v))
  if tanking[i] then r.aggro:Show() else r.aggro:Hide() end
  if u == "player" and MDB.highlightYou then r.hl:Show() else r.hl:Hide() end
  r:Show()
end

local function SetHeightIfChanged(h)
  if h ~= lastH then meter:SetHeight(h); lastH = h end
end

local function Update()
  pending = false
  if not meter or not meter:IsShown() then return end
  local testing = TD.testMode
  local mob = not testing and MeterMob()
  if testing then FillTest() elseif mob then Collect(mob) else n = 0; myV = nil; ClearTail() end

  -- title: target name (may be a hidden value; FontStrings can still show it)
  if testing then
    nameFS:SetText("Training Dummy")
  elseif mob then
    if not pcall(nameFS.SetText, nameFS, UnitName(mob)) then nameFS:SetText("") end
  else
    nameFS:SetText("")
  end

  -- your differential: reuse the nameplate's number/colour when it has one
  local h
  if mob then
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, mob)
    h = ok and plate and TD.holders[plate]
  end
  if h and h.vis and h.txt then
    diffFS:SetText(h.txt)
    local c = h.st and TD.db.colors[TD.STATES[h.st].key]
    if c then diffFS:SetTextColor(c[1], c[2], c[3]) end
  elseif myV then
    local d = myV
    for i = 1, n do if order[i] ~= "player" and not PULL_LABEL[order[i]] then d = myV - vals[i]; break end end
    diffFS:SetText(TD.BuildText(d, floor(d + 0.5)))
    diffFS:SetTextColor(1, 1, 1)
  else
    diffFS:SetText("")
  end

  if MDB.collapsed then
    body:Hide()
    SetHeightIfChanged(HEADER_H)
    return
  end
  body:Show()
  SetHeightIfChanged(MDB.height) -- fixed size, whatever the number of entries

  local shown = min(n, RowsThatFit()) -- only the top rows that fit
  local scaleMax = vals[1] or 1
  if scaleMax <= 0 then scaleMax = 1 end
  local rank = 0
  for i = 1, shown do
    local r = rows[i] or NewRow(i)
    if not PULL_LABEL[order[i]] then rank = rank + 1 end
    PaintRow(r, i, rank, scaleMax)
  end
  for i = shown + 1, #rows do rows[i]:Hide() end
  if shown == 0 then
    emptyFS:SetText(mob and "No threat yet" or "Target an enemy")
    emptyFS:Show()
  else
    emptyFS:Hide()
  end
end
TD.MeterUpdate = Update

local function SafeUpdate()
  local ok, err = pcall(Update)
  if not ok then pending = false; TD.ReportError("meter", err) end
end

local function Dirty()
  if pending or not meter or not meter:IsShown() then return end
  pending = true
  C_Timer.After(MDB.interval or 0.2, SafeUpdate)
end
TD.MeterDirty = Dirty

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
local ev -- event frame (registered only while the meter is visible)
local EVENTS = { "UNIT_THREAT_LIST_UPDATE", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_PET" }

local function SavePosition()
  local l, t = meter:GetLeft(), meter:GetTop()
  if not l or not t or issecret(l) or issecret(t) then return end
  MDB.point, MDB.relPoint, MDB.x, MDB.y = "TOPLEFT", "BOTTOMLEFT", floor(l + 0.5), floor(t + 0.5)
  meter:ClearAllPoints()
  meter:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", MDB.x, MDB.y)
end

-- Small title-bar button: a texture if the client has it, text otherwise.
local function HeaderButton(texture, text, tip, onClick)
  local b = CreateFrame("Button", nil, header)
  b:SetSize(14, 14)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.text:SetPoint("CENTER", 0, 1)
  if texture then
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    if b.tex:SetTexture(texture) == false then b.tex:Hide(); b.text:SetText(text) end
  else
    b.text:SetText(text)
  end
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(tip, 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function Build()
  meter = CreateFrame("Frame", "ThreatDiffMeter", UIParent, "BackdropTemplate")
  meter:SetClampedToScreen(true)
  meter:SetMovable(true)
  meter:EnableMouse(true)
  meter:SetFrameStrata("MEDIUM")
  meter:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  meter:Hide()

  header = CreateFrame("Button", nil, meter)
  header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1)
  header:SetHeight(HEADER_H - 1)
  header:RegisterForDrag("LeftButton")
  header:RegisterForClicks("RightButtonUp")
  header.bg = header:CreateTexture(nil, "BACKGROUND")
  header.bg:SetAllPoints()
  header:SetScript("OnDragStart", function() if not MDB.locked then meter:StartMoving() end end)
  header:SetScript("OnDragStop", function() meter:StopMovingOrSizing(); SavePosition() end)
  header:SetScript("OnClick", function(_, button)
    if button == "RightButton" and TD.ToggleConfig then TD:ToggleConfig(true, "meter") end
  end)

  closeBtn = HeaderButton("Interface\\Buttons\\UI-StopButton", "x", "Hide the meter (/tdiff meter to show it again)", function()
    MDB.enabled = false
    TD:ApplySettings()
    TD.Print("meter hidden. Type |cff4fc3f7/tdiff meter|r to show it again.")
  end)
  closeBtn:SetPoint("RIGHT", -3, 0)
  optBtn = HeaderButton("Interface\\Buttons\\UI-OptionsButton", "o", "Meter options", function()
    if TD.ToggleConfig then TD:ToggleConfig(true, "meter") end
  end)
  optBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
  collapseBtn = HeaderButton(nil, "-", "Collapse / expand", function()
    MDB.collapsed = not MDB.collapsed
    TD.SafeMeterApply()
    if TD.OnConfigChanged then TD.OnConfigChanged() end
  end)
  collapseBtn:SetPoint("RIGHT", optBtn, "LEFT", -3, 0)

  -- a FontString must have a font before it gets text, or the client errors
  titleFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  SetFont(titleFS)
  titleFS:SetPoint("LEFT", 5, 0)
  titleFS:SetText("Threat")
  titleFS:SetTextColor(0.31, 0.76, 0.97)
  diffFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  SetFont(diffFS)
  diffFS:SetPoint("RIGHT", collapseBtn, "LEFT", -6, 0)
  diffFS:SetJustifyH("RIGHT")
  nameFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  SetFont(nameFS)
  nameFS:SetPoint("LEFT", titleFS, "RIGHT", 6, 0)
  nameFS:SetPoint("RIGHT", diffFS, "LEFT", -6, 0)
  nameFS:SetJustifyH("LEFT")
  nameFS:SetTextColor(0.85, 0.85, 0.85)
  if nameFS.SetWordWrap then nameFS:SetWordWrap(false) end

  body = CreateFrame("Frame", nil, meter)
  body:SetPoint("TOPLEFT", 0, -(HEADER_H + PAD))
  body:SetPoint("BOTTOMRIGHT", 0, PAD)
  emptyFS = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  emptyFS:SetPoint("TOPLEFT", 8, -3)

  -- width grip (bottom-right), only while unlocked
  grip = CreateFrame("Button", nil, meter)
  grip:SetSize(12, 12)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(meter:GetFrameLevel() + 10)
  local gt = grip:CreateTexture(nil, "OVERLAY")
  gt:SetAllPoints()
  gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  -- drag the corner: width AND height (the top-left corner stays put)
  local sx, sy, sw, sh
  local function Resize()
    local cx, cy = GetCursorPosition()
    local s = meter:GetEffectiveScale()
    local w = floor(min(800, max(140, sw + (cx - sx) / s)) + 0.5)
    local h = floor(min(1200, max(MinHeight(), sh + (sy - cy) / s)) + 0.5)
    if w ~= MDB.width or h ~= MDB.height then
      MDB.width, MDB.height = w, h
      meter:SetWidth(w)
      Update()
    end
  end
  grip:SetScript("OnMouseDown", function(self)
    SavePosition() -- anchor by the top-left corner so the window grows right/down
    sx, sy = GetCursorPosition()
    sw, sh = MDB.width, MDB.height
    self:SetScript("OnUpdate", Resize)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    SavePosition()
    if TD.OnConfigChanged then TD.OnConfigChanged() end
  end)

  ev = CreateFrame("Frame")
  ev:SetScript("OnEvent", Dirty)
  meter.built = true
end

-- Combat state for "only show in combat". The game fires PLAYER_REGEN_DISABLED
-- a moment BEFORE InCombatLockdown() turns true, so the events are the source
-- of truth; InCombatLockdown() covers a /reload in the middle of a fight.
local inCombat = false
local function InCombat() return inCombat or InCombatLockdown() end

local function Visible()
  if not MDB.enabled then return false end
  if TD.testMode then return true end
  if MDB.hideOOC and not InCombat() then return false end
  return true
end

local registered = false
local function SetEvents(on)
  if on == registered then return end
  registered = on
  for _, e in ipairs(EVENTS) do
    if on then pcall(ev.RegisterEvent, ev, e) else ev:UnregisterEvent(e) end
  end
  -- your target's target (healer view) changes: only listen for "target"
  if on then pcall(ev.RegisterUnitEvent, ev, "UNIT_TARGET", "target") else ev:UnregisterEvent("UNIT_TARGET") end
end

-- Re-apply every meter setting (called whenever settings/profile change).
function TD.MeterApply()
  MDB = TD.db.meter
  if not meter or not meter.built then
    if not MDB.enabled then return end
    if meter then meter:Hide() end -- a half-built frame from an earlier error
    Build()
  end
  meter:ClearAllPoints()
  meter:SetPoint(MDB.point, UIParent, MDB.relPoint, MDB.x, MDB.y)
  meter:SetWidth(MDB.width)
  meter:SetBackdropColor(0.03, 0.03, 0.04, MDB.bgAlpha)
  meter:SetBackdropBorderColor(0, 0, 0, MDB.border and min(1, MDB.bgAlpha + 0.4) or 0)
  header.bg:SetColorTexture(0.08, 0.08, 0.1, min(1, MDB.bgAlpha + 0.25))
  SetFont(titleFS); SetFont(nameFS); SetFont(diffFS)
  collapseBtn.text:SetText(MDB.collapsed and "+" or "-")
  if MDB.height < MinHeight() then MDB.height = MinHeight() end
  if MDB.locked or MDB.collapsed then grip:Hide() else grip:Show() end
  for i, r in ipairs(rows) do StyleRow(r); PlaceRow(r, i) end
  lastH = nil
  local show = Visible()
  meter:SetShown(show)
  SetEvents(show)
  if show then pending = false; SafeUpdate() end
end

function TD.MeterResetPosition()
  local d = TD.DEFAULTS.meter
  MDB.point, MDB.relPoint, MDB.x, MDB.y = d.point, d.relPoint, d.x, d.y
  TD.SafeMeterApply()
end

-- combat visibility (for "only show in combat")
local cf = CreateFrame("Frame")
cf:RegisterEvent("PLAYER_REGEN_DISABLED")
cf:RegisterEvent("PLAYER_REGEN_ENABLED")
cf:SetScript("OnEvent", function(_, event)
  inCombat = (event == "PLAYER_REGEN_DISABLED")
  if MDB and (MDB.hideOOC or meter) then TD.SafeMeterApply() end
end)
