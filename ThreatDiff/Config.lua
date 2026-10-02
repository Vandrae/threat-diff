--[[ ThreatDiff - position editor, Blizzard settings entry and chat commands.
     (The settings window itself lives in Options.lua; widgets in UI.lua.) ]]

local ADDON, ns = ...
local TD = ns.TD
local UI = ns.UI
local Print = TD.Print
local format, floor, tonumber, ipairs, type = string.format, math.floor, tonumber, ipairs, type
local issecret = _G.issecretvalue or function() return false end

local POINT_SET = {}
for _, p in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
  POINT_SET[p] = true
end

local function PosText()
  local db = TD.db
  return format("x %s, y %s", TD.Fmt2(db.x), TD.Fmt2(db.y))
end
TD.PosText = PosText

-------------------------------------------------------------------------------
-- Position editor: a zoomable mock nameplate you drag the text around on.
-- Offsets are in nameplate units, exactly what the live plates use.
-------------------------------------------------------------------------------
local ed
local edState = { zoom = 2, step = 1, sample = 1 }
TD.editorState = edState

local function num(v) return type(v) == "number" and not issecret(v) end

-- Borrow real geometry from a visible nameplate so the mock matches your UI.
local function SampleGeometry()
  local g = { pw = 110, ph = 45, bw = 110, bh = 10, bx = 0, by = -4 }
  local plates = C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
  local p = plates and plates[1]
  if not p then
    local gs = C_NamePlate.GetNamePlateSize
    if gs then
      local ok, w, h = pcall(gs)
      if ok and num(w) and num(h) and w > 0 and h > 0 then g.pw, g.ph, g.bw = w, h, w end
    end
    return g
  end
  local ok = pcall(function()
    local w, h = p:GetSize()
    if num(w) and num(h) and w > 0 and h > 0 then g.pw, g.ph = w, h end
    local uf = p.UnitFrame or p.unitFrame
    local hb = uf and (uf.healthBar or uf.HealthBar)
    if hb and hb.GetSize then
      local ps, hs = p:GetEffectiveScale(), hb:GetEffectiveScale()
      local bw, bh = hb:GetSize()
      local cx, cy = hb:GetCenter()
      local px, py = p:GetCenter()
      if num(bw) and num(bh) and num(cx) and num(cy) and num(px) and num(py) and bw > 0 then
        g.bw, g.bh = bw * hs / ps, bh * hs / ps
        g.bx, g.by = (cx * hs - px * ps) / ps, (cy * hs - py * ps) / ps
      end
    end
  end)
  if not ok then g = { pw = 110, ph = 45, bw = 110, bh = 10, bx = 0, by = -4 } end
  return g
end

local function EdLine(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetColorTexture(r, g, b, a)
  return t
end

local function BuildEditor()
  ed = UI.Window("ThreatDiffEditor", 470, 400, "Position editor")
  ed:ClearAllPoints()
  ed:SetPoint("CENTER", 0, 40)

  local readout = UI.Text(ed, 18, UI.C.accent)
  readout:SetPoint("TOP", 0, -38)
  readout:SetJustifyH("CENTER")
  local sub = UI.Text(ed, 10, UI.C.dim)
  sub:SetPoint("TOP", readout, "BOTTOM", 0, -4)
  sub:SetJustifyH("CENTER")

  -- clipping viewport
  local area = CreateFrame("Frame", nil, ed)
  area:SetSize(438, 190)
  area:SetPoint("TOP", 0, -80)
  UI.Fill(area, { 0.09, 0.105, 0.13, 1 })
  UI.Border(area, UI.C.cardEdge)
  area:SetClipsChildren(true)
  area:EnableMouse(true)
  area:EnableMouseWheel(true)

  local zoomBox = CreateFrame("Frame", nil, area)
  zoomBox:SetSize(1, 1)
  zoomBox:SetPoint("CENTER")

  -- mock nameplate (outline = the nameplate frame, red bar = health bar)
  local plate = CreateFrame("Frame", nil, zoomBox)
  plate:SetPoint("CENTER")
  local plateBg = EdLine(plate, "BACKGROUND", 1, 1, 1, 0.05)
  plateBg:SetAllPoints()
  local e1, e2, e3, e4 = EdLine(plate, "BORDER", 1, 1, 1, 0.25), EdLine(plate, "BORDER", 1, 1, 1, 0.25),
                         EdLine(plate, "BORDER", 1, 1, 1, 0.25), EdLine(plate, "BORDER", 1, 1, 1, 0.25)
  e1:SetPoint("TOPLEFT"); e1:SetPoint("TOPRIGHT"); e1:SetHeight(0.5)
  e2:SetPoint("BOTTOMLEFT"); e2:SetPoint("BOTTOMRIGHT"); e2:SetHeight(0.5)
  e3:SetPoint("TOPLEFT"); e3:SetPoint("BOTTOMLEFT"); e3:SetWidth(0.5)
  e4:SetPoint("TOPRIGHT"); e4:SetPoint("BOTTOMRIGHT"); e4:SetWidth(0.5)

  local bar = CreateFrame("Frame", nil, plate)
  local barTex = EdLine(bar, "ARTWORK", 0.75, 0.12, 0.12, 1)
  barTex:SetAllPoints()
  local barBg = EdLine(bar, "BACKGROUND", 0, 0, 0, 0.8)
  barBg:SetPoint("TOPLEFT", -1, 1); barBg:SetPoint("BOTTOMRIGHT", 1, -1)
  local mobName = UI.Text(bar, 10, { 1, 0.82, 0 })
  mobName:SetPoint("BOTTOM", bar, "TOP", 0, 3)
  mobName:SetText("Enemy")

  -- crosshair on the anchor point, faint box around the text
  local crossH = EdLine(plate, "OVERLAY", 0.31, 0.76, 0.97, 0.9)
  local crossV = EdLine(plate, "OVERLAY", 0.31, 0.76, 0.97, 0.9)
  crossH:SetSize(9, 0.6); crossV:SetSize(0.6, 9)
  local sample = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local box = EdLine(plate, "ARTWORK", 1, 1, 1, 0.08)

  local hint = UI.Text(ed, 10, UI.C.dim)
  hint:SetPoint("TOP", area, "BOTTOM", 0, -5)
  hint:SetJustifyH("CENTER")
  hint:SetText("Drag = move  |  Shift+drag = fine  |  Wheel = Y, Alt+Wheel = X  |  Right-click = sample")

  -- nudge pad (Shift = 1/10 step, Ctrl = 1/100 step)
  local function Nudge(dx, dy)
    local st = UI.StepMod(edState.step)
    TD:SetPosition(TD.db.x + dx * st, TD.db.y + dy * st)
  end
  local function Arrow(text, dx, dy)
    local b = UI.Button(ed, text, 26, function() Nudge(dx, dy) end)
    UI.Tooltip(b, "Nudge by the step.  Shift = step/10,  Ctrl = step/100")
    return b
  end
  local up, down = Arrow("^", 0, 1), Arrow("v", 0, -1)
  local left, right = Arrow("<", -1, 0), Arrow(">", 1, 0)
  up:SetPoint("BOTTOMLEFT", 46, 42)
  down:SetPoint("TOP", up, "BOTTOM", 0, -2)
  left:SetPoint("RIGHT", down, "LEFT", -2, 12)
  right:SetPoint("LEFT", down, "RIGHT", 2, 12)

  local stepBtn, zoomBtn, testBtn -- set below; Paint refreshes their text
  local SAMPLES = {
    { "SECURE", 4210.4, 64 }, { "TANKING", 812, 91 }, { "INSECURE", 0.2, 101 },
    { "OTHERTANK", -2360, 55 }, { "DANGER", -212, 96 }, { "SAFE", -3120, 35 },
  }

  local function Layout()
    local g = ed.geo
    plate:SetSize(g.pw, g.ph)
    bar:ClearAllPoints()
    bar:SetSize(g.bw, g.bh)
    bar:SetPoint("CENTER", plate, "CENTER", g.bx, g.by)
    zoomBox:SetScale(edState.zoom)
  end

  local function Paint()
    local db = TD.db
    local anchor = (db.anchorTo == "HEALTH") and bar or plate
    TD.StyleFontString(sample, anchor)
    local s = SAMPLES[edState.sample]
    sample:SetText(TD.BuildText(s[2], floor(s[2] + 0.5)))
    local c = db.colors[s[1]]
    sample:SetTextColor(c[1], c[2], c[3])
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", sample, "TOPLEFT", -1, 1)
    box:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", 1, -1)
    crossH:ClearAllPoints(); crossV:ClearAllPoints()
    crossH:SetPoint("CENTER", anchor, db.relPoint, 0, 0)
    crossV:SetPoint("CENTER", anchor, db.relPoint, 0, 0)
    readout:SetText(PosText())
    sub:SetText(format("text %s  ->  %s %s", db.point,
      db.anchorTo == "HEALTH" and "health bar" or "nameplate", db.relPoint))
    stepBtn:SetText("Step " .. edState.step)
    zoomBtn:SetText("Zoom " .. edState.zoom .. "x")
    testBtn:SetText(TD.testMode and "Stop test" or "Test on plates")
  end
  ed.Paint = Paint

  stepBtn = UI.Button(ed, "", 86, function()
    edState.step = (edState.step == 1 and 0.1) or (edState.step == 0.1 and 0.01) or 1
    Paint()
  end)
  stepBtn:SetPoint("BOTTOMLEFT", 128, 46)
  zoomBtn = UI.Button(ed, "", 86, function()
    edState.zoom = edState.zoom % 4 + 1
    Layout(); Paint()
  end)
  zoomBtn:SetPoint("LEFT", stepBtn, "RIGHT", 6, 0)
  local zero = UI.Button(ed, "Zero (0, 0)", 86, function() TD:SetPosition(0, 0) end)
  zero:SetPoint("LEFT", zoomBtn, "RIGHT", 6, 0)
  local geo = UI.Button(ed, "Re-measure plate", 132, function() ed.geo = SampleGeometry(); Layout(); Paint() end)
  geo:SetPoint("BOTTOMLEFT", 128, 18)
  UI.Tooltip(geo, "Copies the size of a nameplate that's on screen right now, so the mock matches your UI.")
  testBtn = UI.Button(ed, "", 132, function() TD:SetTestMode(not TD.testMode) end)
  testBtn:SetPoint("LEFT", geo, "RIGHT", 6, 0)

  -- drag: 1:1 with the cursor, Shift = 10x finer. Always lands on 0.01.
  local lastX, lastY, accX, accY, ox, oy
  local function DragUpdate()
    local cx, cy = GetCursorPosition()
    local s = zoomBox:GetEffectiveScale()
    local f = IsShiftKeyDown() and 0.1 or 1
    accX = accX + (cx - lastX) / s * f
    accY = accY + (cy - lastY) / s * f
    lastX, lastY = cx, cy
    local nx, ny = TD.Round2(ox + accX), TD.Round2(oy + accY)
    if nx ~= TD.db.x or ny ~= TD.db.y then TD:SetPosition(nx, ny) end
  end
  area:SetScript("OnMouseDown", function(self, button)
    if button == "RightButton" then
      edState.sample = edState.sample % #SAMPLES + 1
      return Paint()
    end
    lastX, lastY = GetCursorPosition()
    accX, accY, ox, oy = 0, 0, TD.db.x, TD.db.y
    self:SetScript("OnUpdate", DragUpdate)
  end)
  area:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  area:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
  area:SetScript("OnMouseWheel", function(_, d)
    local st = UI.StepMod(edState.step)
    if IsAltKeyDown() then TD:SetPosition(TD.db.x + d * st, TD.db.y)
    else TD:SetPosition(TD.db.x, TD.db.y + d * st) end
  end)

  ed:SetScript("OnShow", function()
    ed.geo = SampleGeometry()
    Layout(); Paint()
  end)
end

function TD:ToggleEditor(show)
  if not ed then BuildEditor() end
  if show == nil then show = not ed:IsShown() end
  ed:SetShown(show)
end

-------------------------------------------------------------------------------
-- Change notifications from Core
-------------------------------------------------------------------------------
TD.positionHooks = TD.positionHooks or {}

TD.OnPositionChanged = function()
  local win = _G.ThreatDiffConfig
  if win and win:IsShown() then
    for i = 1, #TD.positionHooks do TD.positionHooks[i]() end
  end
  if ed and ed:IsShown() then ed.Paint() end
end

TD.OnConfigChanged = function()
  if TD.OptionsRefresh then TD.OptionsRefresh() end
  TD.OnPositionChanged()
end
TD.OnProfileChanged = TD.OnConfigChanged

-------------------------------------------------------------------------------
-- Blizzard Settings entry (opens our window)
-------------------------------------------------------------------------------
local function RegisterSettings()
  local panel = CreateFrame("Frame")
  panel.name = "ThreatDiff"
  local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  t:SetPoint("TOPLEFT", 16, -16)
  t:SetText("ThreatDiff |cff4fc3f7Forever|r")
  local d = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
  d:SetText("Exact threat differential on every enemy nameplate.")
  local b = UI.Button(panel, "Open ThreatDiff settings", 200, function()
    if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
    TD:ToggleConfig(true)
  end)
  b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -12)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(panel, "ThreatDiff")
    Settings.RegisterAddOnCategory(cat)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

TD.OnLoaded = function() pcall(RegisterSettings) end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local NUM = "([-+]?%d*%.?%d+)"

-- Accepts "2.34 10.25", "2.34, 10.25", "x 2.34 y 10.25", "x, 2.34 y, 10.25", "y=4".
local function ParseXY(s)
  local x = s:match("x[%s,:=]*" .. NUM)
  local y = s:match("y[%s,:=]*" .. NUM)
  if not x and not y then
    x, y = s:match(NUM .. "[%s,;]+" .. NUM)
    if not x then x = s:match(NUM) end
  end
  return tonumber(x), tonumber(y)
end
TD.ParseXY = ParseXY

local function PrintPos()
  local db = TD.db
  Print(format("%s   (text %s -> %s %s)", PosText(), db.point,
    db.anchorTo == "HEALTH" and "health bar" or "nameplate", db.relPoint))
end

local HELP = {
  "|cff4fc3f7/tdiff|r - open settings",
  "|cff4fc3f7/tdiff pos|r - print the exact text position",
  "|cff4fc3f7/tdiff pos 2.34 10.25|r  or  |cff4fc3f7/tdiff pos x, 2.34 y, 10.25|r - set it",
  "|cff4fc3f7/tdiff x 2.34|r  |  |cff4fc3f7/tdiff y 10.25|r - set one axis",
  "|cff4fc3f7/tdiff point RIGHT LEFT|r - text point, plate point",
  "|cff4fc3f7/tdiff edit|r - drag-to-place position editor",
  "|cff4fc3f7/tdiff test|r - sample numbers on all visible plates",
  "|cff4fc3f7/tdiff role auto|tank|dps|r   |cff4fc3f7/tdiff on|off|r",
  "|cff4fc3f7/tdiff meter|r - show/hide the threat meter  (|cff4fc3f7lock|r, |cff4fc3f7unlock|r, |cff4fc3f7collapse|r, |cff4fc3f7reset|r)",
  "|cff4fc3f7/tdiff profile|r - list profiles  (|cff4fc3f7use|r, |cff4fc3f7new|r, |cff4fc3f7copy|r, |cff4fc3f7delete|r <name>, |cff4fc3f7reset|r)",
  "|cff4fc3f7/tdiff minimap|r - show/hide the minimap button",
  "|cff4fc3f7/tdiff stats|r - live cost    |cff4fc3f7/tdiff reset|r - reset this profile",
  "|cff4fc3f7/tdiff probe|r - report what threat data the game lets addons read (for bug reports)",
}

SLASH_THREATDIFF1 = "/tdiff"
SLASH_THREATDIFF2 = "/threatdiff"
local function ProfileCmd(args)
  local sub, name = args:match("^(%S*)%s*(.-)$")
  sub = sub:lower()
  if sub == "" or sub == "list" then
    Print("profiles (active: |cffffffff" .. TD.profileName .. "|r): " .. table.concat(TD:GetProfiles(), ", "))
  elseif sub == "use" or sub == "switch" or sub == "load" then
    if TD.Report(TD:SetProfile(name)) then Print("now using profile |cffffffff" .. TD.profileName .. "|r.") end
  elseif sub == "new" or sub == "create" then
    if TD.Report(TD:NewProfile(name)) then Print("created and switched to |cffffffff" .. TD.profileName .. "|r.") end
  elseif sub == "copy" then
    if TD.Report(TD:CopyProfile(name)) then Print("copied |cffffffff" .. name .. "|r into " .. TD.profileName .. ".") end
  elseif sub == "delete" or sub == "remove" then
    if TD.Report(TD:DeleteProfile(name)) then Print("deleted profile " .. name .. ".") end
  elseif sub == "reset" then
    TD:ResetProfile(); Print("profile " .. TD.profileName .. " reset to defaults.")
  else
    Print("usage: /tdiff profile [list | use <name> | new <name> | copy <name> | delete <name> | reset]")
  end
end

local function MeterCmd(sub)
  local m = TD.db.meter
  if sub == "" or sub == "toggle" or sub == "show" or sub == "hide" then
    if sub == "" or sub == "toggle" then m.enabled = not m.enabled else m.enabled = (sub == "show") end
    if m.enabled then
      Print("threat meter shown - drag its title bar to move it (|cff4fc3f7/tdiff meter reset|r puts it back near the middle of the screen).")
    else
      Print("threat meter hidden - |cff4fc3f7/tdiff meter|r shows it again.")
    end
  elseif sub == "lock" or sub == "unlock" then
    m.locked = (sub == "lock")
  elseif sub == "collapse" or sub == "expand" then
    if sub == "expand" then m.collapsed = false else m.collapsed = not m.collapsed end
  elseif sub == "reset" then
    return TD.MeterResetPosition()
  else
    return Print("usage: /tdiff meter [show | hide | lock | unlock | collapse | reset]")
  end
  TD:ApplySettings()
end

SlashCmdList.THREATDIFF = function(msg)
  local cmd, rawRest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local rest = rawRest:lower()
  local db = TD.db
  if cmd == "" or cmd == "config" or cmd == "options" then
    TD:ToggleConfig()
  elseif cmd == "pos" or cmd == "xy" or cmd == "position" then
    if rest ~= "" then
      local x, y = ParseXY(rest)
      if not x and not y then return Print("couldn't read that. Try: /tdiff pos 2.34 10.25") end
      TD:SetPosition(x or db.x, y or db.y)
    end
    PrintPos()
  elseif cmd == "x" or cmd == "y" then
    local v = tonumber(rest:match(NUM) or "")
    if not v then return Print("usage: /tdiff " .. cmd .. " 2.34") end
    if cmd == "x" then TD:SetPosition(v, db.y) else TD:SetPosition(db.x, v) end
    PrintPos()
  elseif cmd == "point" or cmd == "anchor" then
    local a, b = rest:upper():match("^(%a+)%s*(%a*)$")
    if not a or not POINT_SET[a] or (b ~= "" and not POINT_SET[b]) then
      return Print("points: TOPLEFT TOP TOPRIGHT LEFT CENTER RIGHT BOTTOMLEFT BOTTOM BOTTOMRIGHT")
    end
    db.point = a
    if b ~= "" then db.relPoint = b end
    TD:ApplySettings(); PrintPos()
  elseif cmd == "edit" or cmd == "editor" or cmd == "move" or cmd == "unlock" then
    TD:ToggleEditor()
  elseif cmd == "test" then
    TD:SetTestMode(not TD.testMode)
    Print(TD.testMode and "test mode ON - sample numbers on every visible plate." or "test mode off.")
  elseif cmd == "role" then
    local r = ({ auto = "AUTO", tank = "TANK", dps = "DPS", heal = "DPS", healer = "DPS" })[rest]
    if not r then return Print("usage: /tdiff role auto|tank|dps") end
    db.role = r; TD:ApplySettings(); Print("role: " .. TD:RoleText())
  elseif cmd == "on" or cmd == "off" or cmd == "toggle" then
    if cmd == "toggle" then db.enabled = not db.enabled else db.enabled = (cmd == "on") end
    TD:ApplySettings(); Print(db.enabled and "enabled." or "disabled.")
  elseif cmd == "stats" then
    local s = TD:GetStats()
    local kb = 0
    local upd = _G.UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
    local get = _G.GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    if upd and get then pcall(upd); local ok, v = pcall(get, ADDON); if ok and v then kb = v end end
    Print(format("%d plates showing (%d dimmed), %d group units tracked, %.1f updates/s, "
      .. "%.0f threat calls/s, %.1f KB (since last /tdiff stats)",
      s.shown, s.dimmed, s.units, s.evalsPerSec, s.apiPerSec, kb))
  elseif cmd == "probe" or cmd == "debug" then
    if InCombatLockdown() then
      TD:ProbeReport()
    else
      TD.probeArmed = true
      Print("probe armed - start a fight and keep an enemy targeted; the report prints 3 seconds in.")
    end
  elseif cmd == "minimap" then
    local show = not TD.MinimapShown()
    TD.SetMinimapShown(show)
    TD:ApplySettings()
    Print(show and "minimap button shown." or "minimap button hidden - |cff4fc3f7/tdiff minimap|r brings it back.")
  elseif cmd == "meter" then
    MeterCmd(rest)
  elseif cmd == "profile" or cmd == "profiles" then
    ProfileCmd(rawRest)
  elseif cmd == "reset" then
    TD:ResetProfile(); Print("profile " .. TD.profileName .. " reset to defaults."); PrintPos()
  else
    for _, line in ipairs(HELP) do print(line) end
  end
end
