--[[ ThreatDiff - exact threat differential on every enemy nameplate.

  How it stays light:
    * No OnUpdate scripts. Threat events only mark a nameplate "dirty"; one
      throttled C_Timer flush evaluates dirty plates (default max 10x/sec).
    * One text frame per *nameplate frame*, created once and reused forever
      (the game recycles nameplate frames, so do we). Zero churn in combat.
    * The group roster is cached as a flat array of unit tokens and rebuilt
      only when the roster/pets change. No tables are created while updating.
    * Text/colour are only touched when the rounded number or state changes.
    * In big raids a per-mob "smart scan" re-checks only the top threat unit
      and the aggro holder, with a full roster scan at most every 0.5s.
]]

local ADDON, ns = ...
local TD = {}
ns.TD = TD
_G.ThreatDiff = TD

-------------------------------------------------------------------------------
-- Upvalues
-------------------------------------------------------------------------------
local UDTS = UnitDetailedThreatSituation
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local GetNamePlates = C_NamePlate.GetNamePlates
local UnitExists, UnitIsUnit, UnitCanAttack = UnitExists, UnitIsUnit, UnitCanAttack
local UnitAffectingCombat, UnitGUID = UnitAffectingCombat, UnitGUID
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local GetTime, C_Timer_After = GetTime, C_Timer.After
local floor, format, pairs, type = math.floor, string.format, pairs, type
local tonumber, select, wipe, pcall = tonumber, select, wipe, pcall

-- Secret values (modern client). A secret must never be compared or used in
-- arithmetic, so every threat value is checked with this before it is touched.
local issecret = _G.issecretvalue or function() return false end

-------------------------------------------------------------------------------
-- States
-------------------------------------------------------------------------------
local S_SECURE, S_TANKING, S_INSECURE, S_OTHERTANK, S_PET, S_LOOSE,
      S_SAFE, S_WARN, S_DANGER, S_AGGRO = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10

TD.STATES = {
  { key = "SECURE",    label = "Tanking - secure lead" },
  { key = "TANKING",   label = "Tanking - thin lead" },
  { key = "INSECURE",  label = "Tanking - being overtaken" },
  { key = "OTHERTANK", label = "Another tank has it" },
  { key = "PET",       label = "Your pet has it" },
  { key = "LOOSE",     label = "Loose - a non-tank has it" },
  { key = "SAFE",      label = "DPS - safe" },
  { key = "WARN",      label = "DPS - getting close" },
  { key = "DANGER",    label = "DPS - about to pull" },
  { key = "AGGRO",     label = "DPS - you pulled it" },
}

local DEFAULTS = {
  enabled = true,
  showSolo = true, showPet = true, showParty = true, showRaid = true,
  role = "AUTO",          -- AUTO | TANK | DPS
  dpsRef = "TOP",         -- TOP (gap to highest threat) | PULL (threat left before you pull)
  hideSafe = false,       -- hide the number while a DPS is in the SAFE band

  abbreviate = true, decimals = 1,
  showPlus = true, showMinus = true, bangOnTie = true,
  font = "Fonts\\FRIZQT__.TTF", fontSize = 12, outline = "OUTLINE", shadow = false,

  x = -6, y = 0,          -- exact offsets, stored to 0.01
  point = "RIGHT",        -- point on the text...
  relPoint = "LEFT",      -- ...attached to this point on the plate
  anchorTo = "PLATE",     -- PLATE | HEALTH

  secureMode = "PCT", secureValue = 25,   -- lead needed to count as "secure"
  warnPct = 70, dangerPct = 90,           -- DPS bands (% of the way to pulling)

  interval = 0.1,         -- seconds between flushes (max update rate)
  keepLast = 10,          -- seconds to keep a mob's last real number (dimmed) when the game hides it
  divisor = 0,            -- 0 = auto (Forever reports display units; Classic x100)

  meter = {
    enabled = true, locked = false, collapsed = false, hideOOC = false,
    point = "TOPLEFT", relPoint = "CENTER", x = 260, y = 120,
    width = 260, height = 214, barHeight = 18, spacing = 1, interval = 0.2, -- 214 = title + 10 rows
    barStyle = "BLIZZARD", font = "Fonts\\FRIZQT__.TTF", fontSize = 11, outline = "OUTLINE",
    bgAlpha = 0.7, barAlpha = 0.9, barBgAlpha = 0.3, border = true,
    classColors = true, classIcons = true, rankNumbers = true, highlightYou = true,
    valueFormat = "PCT",    -- PCT: threat (% of tank) | THREAT | GAP: threat (difference to you)
    pullRows = "BOTH",      -- BOTH | MELEE | RANGED | MINE (your exact pull point) | OFF
  },

  colors = {
    SECURE    = { 0.25, 1.00, 0.25 },
    TANKING   = { 1.00, 0.90, 0.10 },
    INSECURE  = { 1.00, 0.50, 0.00 },
    OTHERTANK = { 0.30, 0.60, 1.00 },
    PET       = { 0.00, 0.80, 0.80 },
    LOOSE     = { 1.00, 0.15, 0.15 },
    SAFE      = { 0.75, 1.00, 0.75 },
    WARN      = { 1.00, 0.90, 0.10 },
    DANGER    = { 1.00, 0.50, 0.00 },
    AGGRO     = { 1.00, 0.15, 0.15 },
  },
}
TD.DEFAULTS = DEFAULTS

local DB                         -- ThreatDiffDB after load
local COL = {}                   -- [state] = {r,g,b} (points into DB.colors)
local divisor = 1
local tankMode = false
local allowed = false
local testMode = false
local fmtK, fmtM = "%.1fk", "%.2fm"

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function Print(...)
  print("|cff4fc3f7ThreatDiff|r:", ...)
end
TD.Print = Print

-- Lua errors are hidden by default in game, so a broken part could fail
-- silently. Report the first error from each part in chat instead.
local reported = {}
function TD.ReportError(where, err)
  if reported[where] then return end
  reported[where] = true
  Print("|cffff5555" .. where .. " error:|r " .. tostring(err) .. "  - please send this line to the author.")
end

function TD.SafeMeterApply()
  if not TD.MeterApply then return end
  local ok, err = pcall(TD.MeterApply)
  if not ok then TD.ReportError("meter", err) end
end

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

-- Round to hundredths, half away from zero, immune to 1.005*100 = 100.4999...
function TD.Round2(v)
  local neg = v < 0
  if neg then v = -v end
  v = floor(v * 100 + 0.5 + 1e-7) / 100
  if v == 0 then return 0 end
  return neg and -v or v
end

function TD.Fmt2(v)
  return format("%.2f", TD.Round2(v))
end

-------------------------------------------------------------------------------
-- Roster (flat token array, rebuilt only on roster/pet changes)
-------------------------------------------------------------------------------
local RAID, RAIDPET, PARTY, PARTYPET = {}, {}, {}, {}
local TARGET_OF = { pet = "pettarget" } -- [group token] = "<token>target"
for i = 1, 40 do RAID[i] = "raid" .. i; RAIDPET[i] = "raidpet" .. i end
for i = 1, 4 do PARTY[i] = "party" .. i; PARTYPET[i] = "partypet" .. i end
for _, list in ipairs({ RAID, RAIDPET, PARTY, PARTYPET }) do
  for i = 1, #list do TARGET_OF[list[i]] = list[i] .. "target" end
end

-- Other tokens that can point at the same mob as a nameplate. Forever hides
-- threat for "nameplateN" tokens, but not (so far) for these. Your own ones
-- come first, then whatever each group member / pet is targeting.
local BASE_ROUTES = { "target", "focus", "mouseover", "softenemy",
  "boss1", "boss2", "boss3", "boss4", "boss5", "pettarget" }
local LAST_ROUTES = { "targettarget", "focustarget" } -- healers: a friendly's enemy
local routes, nRoutes = {}, 0
local targetOf = {}              -- [group token] = its "...target" token, current roster only

local units, nUnits = {}, 0      -- everyone except the player
local isTank = {}                -- [token] = true for tanks / main tanks
local SMALL_GROUP = 10           -- at or below this, always full-scan
local FULL_SCAN_EVERY = 0.5

local function AddUnit(u)
  nUnits = nUnits + 1
  units[nUnits] = u
end

local function FlagTank(u)
  local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
  if role == "TANK" or (GetPartyAssignment and GetPartyAssignment("MAINTANK", u)) then
    isTank[u] = true
  end
end

local MarkAllDirty, ComputeRole -- forward

local function RebuildRoster()
  TD.rosterPending = false
  for i = nUnits, 1, -1 do units[i] = nil end
  nUnits = 0
  wipe(isTank)

  local inRaid, inGroup = IsInRaid(), IsInGroup()
  local hasPet = UnitExists("pet") and true or false

  if inRaid then
    for i = 1, GetNumGroupMembers() do
      local u = RAID[i]
      if UnitIsUnit(u, "player") then
        if hasPet then AddUnit("pet") end
      else
        AddUnit(u); FlagTank(u)
        if UnitExists(RAIDPET[i]) then AddUnit(RAIDPET[i]) end
      end
    end
  else
    if inGroup then
      for i = 1, 4 do
        local u = PARTY[i]
        if UnitExists(u) then
          AddUnit(u); FlagTank(u)
          if UnitExists(PARTYPET[i]) then AddUnit(PARTYPET[i]) end
        end
      end
    end
    if hasPet then AddUnit("pet") end
  end

  -- readable routes: yours, then each group member's / pet's target
  wipe(targetOf)
  nRoutes = 0
  for i = 1, #BASE_ROUTES do nRoutes = nRoutes + 1; routes[nRoutes] = BASE_ROUTES[i] end
  for i = 1, nUnits do
    local tt = TARGET_OF[units[i]]
    targetOf[units[i]] = tt
    if tt ~= "pettarget" then nRoutes = nRoutes + 1; routes[nRoutes] = tt end
  end
  for i = 1, #LAST_ROUTES do nRoutes = nRoutes + 1; routes[nRoutes] = LAST_ROUTES[i] end
  for i = #routes, nRoutes + 1, -1 do routes[i] = nil end

  local was = allowed
  allowed = DB.enabled and (
       (inRaid and DB.showRaid)
    or (inGroup and not inRaid and DB.showParty)
    or (hasPet and DB.showPet)
    or (not inGroup and DB.showSolo)) and true or false

  TD.inRaid, TD.inGroup, TD.hasPet = inRaid, inGroup, hasPet
  for _, h in pairs(TD.active) do h.topU, h.holdU, h.nextFull = nil, nil, nil end -- tokens may have shifted
  ComputeRole()
  if was ~= allowed or allowed then MarkAllDirty() end
  if TD.MeterDirty then TD.MeterDirty() end
end

local function QueueRoster()
  if not TD.rosterPending then
    TD.rosterPending = true
    C_Timer_After(0.2, RebuildRoster)
  end
end

-------------------------------------------------------------------------------
-- Role detection
-------------------------------------------------------------------------------
local TANK_FORMS = { [5] = true, [8] = true, [18] = true } -- bear, dire bear, defensive stance
local RIGHTEOUS_FURY = 25780
local hasRF = false
local playerClass

local function CheckRF()
  if playerClass ~= "PALADIN" or InCombatLockdown() then return end
  local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
  if not get then return end
  local ok, aura = pcall(get, RIGHTEOUS_FURY)
  if ok and not issecret(aura) then hasRF = aura and true or false end
end

function ComputeRole()
  local r = DB.role
  if r == "TANK" then
    tankMode = true
  elseif r == "DPS" then
    tankMode = false
  else
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    local form = GetShapeshiftFormID and GetShapeshiftFormID()
    tankMode = (role == "TANK")
      or (GetPartyAssignment and GetPartyAssignment("MAINTANK", "player") and true)
      or (form and not issecret(form) and TANK_FORMS[form])
      or hasRF
      or (not IsInGroup() and not UnitExists("pet")) -- solo: you are the tank
    tankMode = tankMode and true or false
  end
  TD.tankMode = tankMode
end

-------------------------------------------------------------------------------
-- Text holders (one per nameplate frame, reused)
-------------------------------------------------------------------------------
local holders = {}   -- [plateFrame] = holder
local active = {}    -- [nameplate unit token] = holder (attackable plates only)
local dirty = {}     -- [nameplate unit token] = true
TD.holders, TD.active = holders, active

local OUTLINES = { NONE = "", OUTLINE = "OUTLINE", THICK = "THICKOUTLINE" }
local JUSTIFY = { LEFT = "LEFT", TOPLEFT = "LEFT", BOTTOMLEFT = "LEFT",
                  RIGHT = "RIGHT", TOPRIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT" }

local function AnchorFrameFor(plate)
  if DB.anchorTo == "HEALTH" then
    local uf = plate.UnitFrame or plate.unitFrame
    local hb = uf and (uf.healthBar or uf.HealthBar or uf.healthbar)
    if type(hb) == "table" and hb.GetObjectType then return hb end
  end
  return plate
end

-- Set a font, falling back to the game font if the file can't be used.
-- (Checks with GetFont, so it works whether or not SetFont reports success.)
function TD.ApplyFont(fs, path, size, flags)
  local ok = fs:SetFont(path, size, flags)
  if ok == false or not fs:GetFont() then
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags)
  end
end

-- Apply font + exact position. Used by live plates and the editor preview.
function TD.StyleFontString(fs, anchor)
  TD.ApplyFont(fs, DB.font, DB.fontSize, OUTLINES[DB.outline] or "")
  if DB.shadow then
    fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
  else
    fs:SetShadowOffset(0, 0)
  end
  fs:SetJustifyH(JUSTIFY[DB.point] or "CENTER")
  fs:ClearAllPoints()
  fs:SetPoint(DB.point, anchor, DB.relPoint, DB.x, DB.y)
end

local function PlaceHolder(h)
  TD.StyleFontString(h.fs, AnchorFrameFor(h.plate))
  h.st, h.txt = nil, nil -- force a repaint
end

local function GetHolder(plate)
  local h = holders[plate]
  if not h then
    h = CreateFrame("Frame", nil, plate)
    h:SetAllPoints(plate)
    h:EnableMouse(false)
    h.plate = plate
    h.fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:Hide()
    holders[plate] = h
    PlaceHolder(h)
  end
  h:SetFrameLevel(plate:GetFrameLevel() + 30)
  return h
end

local function HideHolder(h)
  if h.vis then h:Hide(); h.vis = false end
  h.st, h.txt, h.fresh, h.via = nil, nil, nil, nil
  if h.dim then h:SetAlpha(1); h.dim = false end
end

-- The game hid this mob's numbers right now: keep the last real number, dimmed,
-- for a few seconds (you'll get fresh ones when you target/mouseover it).
local function Stale(h, now)
  local keep = DB.keepLast or 0
  if h.vis and h.fresh and keep > 0 and now - h.fresh <= keep then
    if not h.dim then h:SetAlpha(0.5); h.dim = true end
    return
  end
  HideHolder(h)
end

-------------------------------------------------------------------------------
-- Formatting
-------------------------------------------------------------------------------
local function RebuildFormats()
  local d = DB.decimals
  fmtK = "%." .. d .. "fk"
  fmtM = "%." .. (d < 2 and d + 1 or 2) .. "fm"
end

local function FormatAbs(v) -- v >= 0
  if DB.abbreviate then
    if v >= 999500 then return format(fmtM, v / 1e6) end
    if v >= 999.5 then return format(fmtK, v / 1000) end
  end
  return format("%d", floor(v + 0.5))
end
TD.FormatAbs = FormatAbs

-- Always a raw threat number (never a percentage).
local function BuildText(diff, dk)
  local s
  if dk == 0 then
    s = DB.bangOnTie and "!!!" or "0"
  elseif diff < 0 then
    s = FormatAbs(-diff)
    if DB.showMinus then s = "-" .. s end
  else
    s = FormatAbs(diff)
    if DB.showPlus then s = "+" .. s end
  end
  return s
end
TD.BuildText = BuildText

local function Paint(h, st, diff, now)
  h.fresh = now
  if h.dim then h:SetAlpha(1); h.dim = false end
  local dk = floor(diff + 0.5)
  if h.vis and h.st == st and h.dk == dk then return end
  local txt = BuildText(diff, dk)
  if txt ~= h.txt then h.fs:SetText(txt); h.txt = txt end
  if h.st ~= st then
    local c = COL[st]
    h.fs:SetTextColor(c[1], c[2], c[3])
  end
  h.st, h.dk = st, dk
  if not h.vis then h:Show(); h.vis = true end
end
TD.Paint = Paint

-------------------------------------------------------------------------------
-- Threat engine
-------------------------------------------------------------------------------
local stats = { api = 0, evals = 0, flushes = 0 }     -- cumulative counters
local last = { api = 0, evals = 0, flushes = 0, t = 0 } -- snapshot for GetStats
TD.stats = stats

-- Scans the cached roster against one mob.
-- Returns highest raw threat among others, its unit, and the aggro holder.
local function FullScan(mob)
  local top, topU, holdU = 0, nil, nil
  for i = 1, nUnits do
    local u = units[i]
    local t, _, _, _, v = UDTS(u, mob)
    if not issecret(v) and v then
      if v > top then top, topU = v, u end
      if not issecret(t) and t then holdU = u end
    end
  end
  stats.api = stats.api + nUnits
  return top, topU, holdU
end

local function Probe(u, mob, top, topU, holdU)
  local t, _, _, _, v = UDTS(u, mob)
  stats.api = stats.api + 1
  if not issecret(v) and v then
    if v > top then top, topU = v, u end
    if not issecret(t) and t then holdU = u end
  end
  return top, topU, holdU
end

-- Readable routes (see BASE_ROUTES). When the game hides a nameplate's threat,
-- find another token that points at the same mob and whose threat it doesn't
-- hide. Each route's plate is looked up lazily, at most once per flush, and a
-- plate remembers the route that worked last time so it is tried first.
local routePlate, routeStamp, routeGUID = {}, {}, {}
local flushId = 0

local function RoutePlate(i)
  if routeStamp[i] ~= flushId then
    routeStamp[i] = flushId
    local ok, p = pcall(GetNamePlateForUnit, routes[i])
    routePlate[i] = (ok and not issecret(p) and p) or false
    routeGUID[i] = nil
  end
  return routePlate[i]
end

-- Fallback when the plate lookup doesn't accept a token (e.g. "party1target"):
-- compare GUIDs instead, if the game lets us read them.
local function SafeGUID(tok)
  local ok, g = pcall(UnitGUID, tok)
  if ok and not issecret(g) and type(g) == "string" then return g end
  return false
end

local function RouteGUID(i) -- call RoutePlate(i) first (it resets this per flush)
  local g = routeGUID[i]
  if g == nil then
    g = SafeGUID(routes[i])
    routeGUID[i] = g
  end
  return g
end

local function ReadableRoute(h)
  local plate, first = h.plate, h.route
  local guid -- this plate's GUID, looked up only if needed
  if first and first > nRoutes then first = nil end
  for n = first and 0 or 1, nRoutes do
    local i = (n == 0) and first or n
    if n == 0 or i ~= first then
      local p = RoutePlate(i)
      local hit = (p == plate)
      if not p then
        if guid == nil then guid = h.unit and SafeGUID(h.unit) or false end
        hit = guid and RouteGUID(i) == guid
      end
      if hit then
        local tok = routes[i]
        stats.api = stats.api + 1
        local t, s, sp, rp, v = UDTS("player", tok)
        if not issecret(v) then
          h.route = i
          return tok, t, s, sp, rp, v
        end
      end
    end
  end
  h.route = nil
end

local function Evaluate(h, mob, now)
  stats.evals = stats.evals + 1
  stats.api = stats.api + 1
  local t, s, sp, rp, v = UDTS("player", mob)

  -- Only the raw threat number has to be readable. If the game hides it for the
  -- nameplate unit, read the same mob through another token.
  if issecret(v) then
    mob, t, s, sp, rp, v = ReadableRoute(h)
    if not mob then return Stale(h, now) end
  end
  h.via = mob

  -- Aggro flag / status / percentages may be hidden separately: work around them.
  local tKnown, sKnown = not issecret(t), not issecret(s)
  if not tKnown then t = nil end
  if not sKnown then s = nil end
  if issecret(sp) then sp = nil end
  if issecret(rp) then rp = nil end

  -- Only mobs you're actually fighting: on its threat table with real threat.
  if not v or (sKnown and not s) or (v <= 0 and not t) then return HideHolder(h) end
  local me = v / divisor
  local top, holdU = 0, nil

  if nUnits > 0 then
    local topU
    if nUnits <= SMALL_GROUP or not h.topU or now >= (h.nextFull or 0) then
      top, topU, holdU = FullScan(mob)
      h.nextFull = now + FULL_SCAN_EVERY
    else
      top, topU, holdU = Probe(h.topU, mob, 0, nil, nil)
      local ch = h.holdU
      if ch and ch ~= h.topU then top, topU, holdU = Probe(ch, mob, top, topU, holdU) end
      if not t and not holdU then -- holder moved; find it now
        top, topU, holdU = FullScan(mob)
        h.nextFull = now + FULL_SCAN_EVERY
      end
    end
    h.topU, h.holdU = topU, holdU
    top = top / divisor
  end

  -- Aggro flag hidden? Whoever has the most threat (and isn't a known holder) has it.
  if not tKnown then t = (holdU == nil) and me > 0 and me >= top end

  -- Aggro holder outside the scanned group: derive its threat from rawPct.
  if not t and not holdU and rp and rp > 0 then
    local est = me * 100 / rp
    if est > top then top = est end
  end

  local diff
  if not t and not tankMode and DB.dpsRef == "PULL" and sp and sp > 0 then
    diff = me - me * 100 / sp
  else
    diff = me - top
  end

  local st
  if t then
    if tankMode then
      if s == 2 or diff <= 0 then
        st = S_INSECURE
      elseif (DB.secureMode == "ABS" and diff >= DB.secureValue)
          or (DB.secureMode ~= "ABS" and diff >= me * DB.secureValue / 100) then
        st = S_SECURE
      else
        st = S_TANKING
      end
    else
      st = S_AGGRO
    end
  elseif holdU == "pet" then
    st = S_PET
  elseif tankMode then
    st = (holdU and isTank[holdU]) and S_OTHERTANK or S_LOOSE
  else
    local band = sp
    if not band then -- % hidden: estimate progress to the (melee) pull point
      band = top > 0 and (me / (top * 1.1) * 100) or 0
      if band > 100 then band = 100 end
    end
    if s == 1 or band >= DB.dangerPct then st = S_DANGER
    elseif band >= DB.warnPct then st = S_WARN
    else st = S_SAFE end
    if st == S_SAFE and DB.hideSafe then return HideHolder(h) end
  end

  Paint(h, st, diff, now)
end
TD.Evaluate = Evaluate

-------------------------------------------------------------------------------
-- Dirty queue + throttled flush
-------------------------------------------------------------------------------
local pending = false

local function Flush()
  pending = false
  if testMode then wipe(dirty); return end
  stats.flushes = stats.flushes + 1
  flushId = flushId + 1
  local now = GetTime()
  local fighting = InCombatLockdown()
  if not fighting then
    local c = UnitAffectingCombat("player")
    fighting = issecret(c) or (c and true or false)
  end
  local show = allowed and fighting
  for unit in pairs(dirty) do
    dirty[unit] = nil
    local h = active[unit]
    if h then
      if show then Evaluate(h, unit, now) else HideHolder(h) end
    end
  end
end
TD.Flush = Flush

local function MarkDirty(unit)
  dirty[unit] = true
  if not pending then
    pending = true
    C_Timer_After(DB.interval, Flush)
  end
end

function MarkAllDirty()
  if not DB then return end
  for unit in pairs(active) do MarkDirty(unit) end
end
TD.MarkAllDirty = MarkAllDirty

-------------------------------------------------------------------------------
-- Nameplates
-------------------------------------------------------------------------------
local function PlateRemoved(unit)
  local h = active[unit]
  if h then
    HideHolder(h)
    h.unit = nil
    active[unit] = nil
  end
  dirty[unit] = nil
end

local function PlateAdded(unit)
  local plate = GetNamePlateForUnit(unit)
  if not plate then return end -- forbidden (e.g. friendly plate in an instance)
  local attackable = UnitCanAttack("player", unit)
  if issecret(attackable) then attackable = true end
  if not attackable then
    if active[unit] then PlateRemoved(unit) end
    return
  end
  local h = GetHolder(plate)
  h.unit = unit
  h.topU, h.holdU, h.nextFull, h.route = nil, nil, nil, nil
  if DB.anchorTo == "HEALTH" then PlaceHolder(h) end -- plate addons may rebuild bars
  HideHolder(h)
  active[unit] = h
  MarkDirty(unit)
end

-------------------------------------------------------------------------------
-- Test mode: fake numbers on every visible plate, for positioning
-------------------------------------------------------------------------------
local testTicker
local TEST_VALUES = {
  { S_SECURE, 4210 }, { S_TANKING, 812 }, { S_INSECURE, -154 }, { S_OTHERTANK, -2360 },
  { S_PET, -540 }, { S_LOOSE, -1875 }, { S_SAFE, -3120 }, { S_WARN, -960 },
  { S_DANGER, -212 }, { S_AGGRO, 305 }, { S_SECURE, 0.3 },
}
local testStep = 0

local function TestTick()
  testStep = testStep + 1
  TD.testStep = testStep
  if TD.MeterDirty then TD.MeterDirty() end
  local i = 0
  for _, plate in pairs(GetNamePlates() or {}) do
    i = i + 1
    local h = GetHolder(plate)
    local tv = TEST_VALUES[(testStep + i) % #TEST_VALUES + 1]
    Paint(h, tv[1], tv[2])
  end
end

function TD:SetTestMode(on)
  testMode = on and true or false
  TD.testMode = testMode
  if testTicker then testTicker:Cancel(); testTicker = nil end
  for _, h in pairs(holders) do HideHolder(h) end
  if testMode then
    TestTick()
    testTicker = C_Timer.NewTicker(1.5, TestTick)
  else
    MarkAllDirty()
  end
  TD.SafeMeterApply()
  if TD.OnConfigChanged then TD.OnConfigChanged() end
end

-------------------------------------------------------------------------------
-- Settings application
-------------------------------------------------------------------------------
function TD:ApplySettings()
  for i, s in ipairs(TD.STATES) do COL[i] = DB.colors[s.key] end
  RebuildFormats()
  local d = tonumber(DB.divisor) or 0
  if d <= 0 then
    local build = select(4, GetBuildInfo())
    d = (build and build >= 16000 and build < 20000) and 1 or 100
  end
  divisor = d
  TD.divisor = d
  ComputeRole()
  for _, h in pairs(holders) do PlaceHolder(h) end
  if TD.inRaid ~= nil then RebuildRoster() end
  MarkAllDirty()
  TD.SafeMeterApply()
  if TD.OnConfigChanged then TD.OnConfigChanged() end
end

-- Move only (cheap path used while dragging in the editor).
function TD:SetPosition(x, y)
  DB.x, DB.y = TD.Round2(x), TD.Round2(y)
  for _, h in pairs(holders) do
    local fs = h.fs
    fs:ClearAllPoints()
    fs:SetPoint(DB.point, AnchorFrameFor(h.plate), DB.relPoint, DB.x, DB.y)
  end
  if TD.OnPositionChanged then TD.OnPositionChanged() end
end

-------------------------------------------------------------------------------
-- Profiles
--   ThreatDiffDB = { profiles = { [name] = settings }, chars = { [character] = name } }
--   Each character remembers its own profile; changes save automatically.
-------------------------------------------------------------------------------
local ROOT, charKey

local function DeepCopy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and DeepCopy(v) or v end
  return c
end

-- Damaged or hand-edited saves: reset any value whose type differs from its default,
-- and any anchor that isn't one of the nine valid points, so one bad value can't
-- make every nameplate throw.
local VALID_POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
  RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

local function Sanitize(db, defaults)
  for k, dv in pairs(defaults) do
    local v = db[k]
    if type(dv) == "table" then
      if type(v) == "table" then Sanitize(v, dv) end
    elseif v ~= nil and type(v) ~= type(dv) then
      db[k] = dv
    end
  end
end

local function Activate(name)
  local p = ROOT.profiles[name]
  if type(p) ~= "table" then p = {}; ROOT.profiles[name] = p end
  -- older saves sized the meter by a row count: keep that look as a fixed height
  local m = p.meter
  if type(m) == "table" and m.height == nil and m.maxBars and TD.MeterHeightFor then
    m.height = TD.MeterHeightFor(tonumber(m.maxBars) or 10, tonumber(m.barHeight) or 18, tonumber(m.spacing) or 1)
  end
  DB = CopyDefaults(DEFAULTS, p)
  Sanitize(DB, DEFAULTS)
  if not VALID_POINTS[DB.point] then DB.point = DEFAULTS.point end
  if not VALID_POINTS[DB.relPoint] then DB.relPoint = DEFAULTS.relPoint end
  if not VALID_POINTS[DB.meter.point] then DB.meter.point = DEFAULTS.meter.point end
  if not VALID_POINTS[DB.meter.relPoint] then DB.meter.relPoint = DEFAULTS.meter.relPoint end
  TD.db = DB
  TD.profileName = name
  ROOT.chars[charKey] = name
  TD:ApplySettings()
  if TD.OnProfileChanged then TD.OnProfileChanged() end
end

local function CleanName(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" or #name > 40 then return nil end
  return name
end

-- Case-insensitive lookup so "/tdiff profile use raid" finds "Raid".
function TD:FindProfile(name)
  if type(name) ~= "string" then return nil end
  if ROOT.profiles[name] then return name end
  local l = name:lower()
  for n in pairs(ROOT.profiles) do if n:lower() == l then return n end end
end

function TD:GetProfiles()
  local list = {}
  for n in pairs(ROOT.profiles) do list[#list + 1] = n end
  table.sort(list, function(a, b)
    if a == "Default" or b == "Default" then return a == "Default" and b ~= "Default" end
    return a:lower() < b:lower()
  end)
  return list
end

-- Account-wide settings (not per profile), e.g. the minimap button.
function TD:GetAccountSettings() return ROOT end

function TD:ProfileUsers(name)
  local list = {}
  for c, p in pairs(ROOT.chars) do if p == name then list[#list + 1] = c end end
  table.sort(list)
  return list
end

function TD:SetProfile(name)
  name = TD:FindProfile(name)
  if not name then return false, "there's no profile with that name" end
  Activate(name)
  return true
end

function TD:NewProfile(name, copyFrom)
  name = CleanName(name)
  if not name then return false, "profile names need 1-40 characters" end
  if TD:FindProfile(name) then return false, "a profile with that name already exists" end
  local src = copyFrom and ROOT.profiles[copyFrom]
  ROOT.profiles[name] = src and DeepCopy(src) or {}
  Activate(name)
  return true
end

function TD:CopyProfile(from)
  from = TD:FindProfile(from)
  if not from or from == TD.profileName then return false, "pick a different profile to copy from" end
  local cur = ROOT.profiles[TD.profileName]
  wipe(cur)
  for k, v in pairs(DeepCopy(ROOT.profiles[from])) do cur[k] = v end
  Activate(TD.profileName)
  return true
end

function TD:RenameProfile(old, new)
  old, new = TD:FindProfile(old), CleanName(new)
  if not old then return false, "there's no profile with that name" end
  if old == "Default" then return false, "the Default profile can't be renamed" end
  if not new then return false, "profile names need 1-40 characters" end
  local clash = TD:FindProfile(new)
  if clash and clash ~= old then return false, "a profile with that name already exists" end
  ROOT.profiles[new], ROOT.profiles[old] = ROOT.profiles[old], nil
  for c, p in pairs(ROOT.chars) do if p == old then ROOT.chars[c] = new end end
  Activate(TD.profileName == old and new or TD.profileName)
  return true
end

function TD:DeleteProfile(name)
  name = TD:FindProfile(name)
  if not name then return false, "there's no profile with that name" end
  if name == "Default" then return false, "the Default profile can't be deleted" end
  if name == TD.profileName then return false, "switch to another profile before deleting this one" end
  ROOT.profiles[name] = nil
  for c, p in pairs(ROOT.chars) do if p == name then ROOT.chars[c] = nil end end
  if TD.OnProfileChanged then TD.OnProfileChanged() end
  return true
end

function TD:ResetProfile()
  wipe(ROOT.profiles[TD.profileName])
  Activate(TD.profileName)
end
TD.ResetSettings = TD.ResetProfile

-- Loads ThreatDiffDB, upgrading a pre-profile (flat) save into "Default".
local function LoadProfiles()
  ROOT = type(ThreatDiffDB) == "table" and ThreatDiffDB or {}
  ThreatDiffDB = ROOT
  if type(ROOT.profiles) ~= "table" then
    local old = {}
    for k, v in pairs(ROOT) do old[k] = v end
    wipe(ROOT)
    old.saved = nil
    ROOT.profiles = { Default = old }
  end
  if type(ROOT.chars) ~= "table" then ROOT.chars = {} end
  if type(ROOT.minimap) ~= "table" then ROOT.minimap = { hide = false, angle = 200 } end
  if type(ROOT.profiles.Default) ~= "table" then ROOT.profiles.Default = {} end
  ROOT.version = 2
  local name = UnitName("player")
  local realm = GetRealmName and GetRealmName()
  charKey = (name or "?") .. " - " .. (realm ~= "" and realm or "?")
  TD.charKey = charKey
  local want = ROOT.chars[charKey]
  if type(want) ~= "string" or type(ROOT.profiles[want]) ~= "table" then want = "Default" end
  Activate(want)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local ef = CreateFrame("Frame")
TD.eventFrame = ef
local heartbeat

local handlers = {}

function handlers.ADDON_LOADED(name)
  if name ~= ADDON then return end
  ef:UnregisterEvent("ADDON_LOADED")
  playerClass = select(2, UnitClass("player"))
  if playerClass == "PALADIN" then ef:RegisterUnitEvent("UNIT_AURA", "player") end
  LoadProfiles()
  if TD.OnLoaded then TD.OnLoaded() end
end

function handlers.PLAYER_ENTERING_WORLD()
  CheckRF()
  ComputeRole()
  RebuildRoster()
  for unit in pairs(active) do PlateRemoved(unit) end
  for _, plate in pairs(GetNamePlates() or {}) do
    local unit = plate.namePlateUnitToken
    if unit then PlateAdded(unit) end
  end
end

handlers.NAME_PLATE_UNIT_ADDED = PlateAdded
handlers.NAME_PLATE_UNIT_REMOVED = PlateRemoved

function handlers.UNIT_FACTION(unit)
  if unit and unit:find("^nameplate%d") then PlateAdded(unit) end
end

local evCount = { nameplate = 0, other = 0 }
TD.evCount = evCount

function handlers.UNIT_THREAT_LIST_UPDATE(unit)
  if not unit or not allowed then return end
  if active[unit] then evCount.nameplate = evCount.nameplate + 1; return MarkDirty(unit) end
  evCount.other = evCount.other + 1
  -- The same mob can be reported as "target", "focus", "boss1"...
  local ok, plate = pcall(GetNamePlateForUnit, unit)
  local h = ok and plate and holders[plate]
  if h and h.unit and active[h.unit] then MarkDirty(h.unit) end
end

-- A new target / focus / mouseover / soft target may be the readable way to a
-- mob's threat, so refresh that mob's plate right away.
local function DirtyPlateOf(alias)
  if not allowed or not InCombatLockdown() then return end
  local ok, plate = pcall(GetNamePlateForUnit, alias)
  local h = ok and plate and holders[plate]
  if h and h.unit and active[h.unit] then MarkDirty(h.unit) end
end
function handlers.PLAYER_TARGET_CHANGED() DirtyPlateOf("target") end
function handlers.PLAYER_FOCUS_CHANGED() DirtyPlateOf("focus") end
function handlers.UPDATE_MOUSEOVER_UNIT() DirtyPlateOf("mouseover") end
function handlers.PLAYER_SOFT_ENEMY_CHANGED() DirtyPlateOf("softenemy") end
-- A group member or pet switched targets: that mob may now be readable.
function handlers.UNIT_TARGET(unit)
  local tt = targetOf[unit]
  if tt then DirtyPlateOf(tt) end
end

function handlers.UNIT_THREAT_SITUATION_UPDATE(unit)
  if unit == "player" or unit == "pet" then MarkAllDirty() end
end

handlers.GROUP_ROSTER_UPDATE = QueueRoster
handlers.PLAYER_ROLES_ASSIGNED = function() ComputeRole(); QueueRoster() end
function handlers.UNIT_PET() QueueRoster() end

function handlers.UPDATE_SHAPESHIFT_FORM()
  local was = tankMode
  ComputeRole()
  if was ~= tankMode then MarkAllDirty(); if TD.OnConfigChanged then TD.OnConfigChanged() end end
end

function handlers.UNIT_AURA()
  local was = hasRF
  CheckRF()
  if was ~= hasRF then handlers.UPDATE_SHAPESHIFT_FORM() end
end

local hinted
function handlers.PLAYER_REGEN_DISABLED()
  if not hinted then
    hinted = true
    local get = (C_CVar and C_CVar.GetCVarBool) or _G.GetCVarBool
    if get and get("nameplateShowEnemies") == false then
      Print("enemy nameplates are off, so there's nowhere to draw threat. Press V (or enable them in Options).")
    end
  end
  if heartbeat then heartbeat:Cancel() end
  MarkAllDirty()
  if TD.probeArmed then
    TD.probeArmed = false
    C_Timer.After(3, function() TD:ProbeReport() end)
  end
  -- safety net: re-check every visible enemy once a second while fighting
  heartbeat = C_Timer.NewTicker(1, MarkAllDirty)
end

function handlers.PLAYER_REGEN_ENABLED()
  if heartbeat then heartbeat:Cancel(); heartbeat = nil end
  CheckRF()
  MarkAllDirty()
end

ef:SetScript("OnEvent", function(_, event, ...)
  if DB or event == "ADDON_LOADED" then handlers[event](...) end
end)
for event in pairs(handlers) do
  -- pcall: never let a renamed/missing event on a new client break loading
  if event ~= "UNIT_AURA" then pcall(ef.RegisterEvent, ef, event) end
end

-------------------------------------------------------------------------------
-- Public helpers for the config / slash commands
-------------------------------------------------------------------------------
-- Rates since the previous call (the options window polls this every 2s).
function TD:GetStats()
  local now = GetTime()
  local dt = now - last.t
  if dt <= 0 then dt = 1 end
  local n, dimmed = 0, 0
  for _, h in pairs(active) do
    if h.vis then n = n + 1; if h.dim then dimmed = dimmed + 1 end end
  end
  local out = {
    shown = n,
    dimmed = dimmed,
    evalsPerSec = (stats.evals - last.evals) / dt,
    apiPerSec = (stats.api - last.api) / dt,
    flushesPerSec = (stats.flushes - last.flushes) / dt,
    units = nUnits,
  }
  last.api, last.evals, last.flushes, last.t = stats.api, stats.evals, stats.flushes, now
  return out
end

-- /tdiff probe: exactly what this client lets an addon read, mid-fight.
local function D(x)
  if issecret(x) then return "|cffff5555SECRET|r" end
  if x == nil then return "nil" end
  if type(x) == "number" then return x == floor(x) and format("%d", x) or format("%.1f", x) end
  return tostring(x)
end

local function Try(fn, ...)
  if not fn then return "n/a" end
  local ok, r = pcall(fn, ...)
  if not ok then return "error" end
  return r
end

function TD:ProbeReport()
  local S = C_Secrets or {}
  Print(format("probe - in combat: %s, interface %s, threat divisor %d, role %s",
    D(InCombatLockdown()), tostring((select(4, GetBuildInfo()))), divisor, TD:RoleText()))
  local toks = { "target", "mouseover", "focus", "softenemy" }
  local n = 0
  for unit in pairs(active) do
    n = n + 1
    if n <= 3 then toks[#toks + 1] = unit end
  end
  local shown = 0
  for tok_i = 1, #toks do
    local tok = toks[tok_i]
    local exists = Try(UnitExists, tok)
    if issecret(exists) or exists == true then
      local ok, t, s, sp, rp, v = pcall(UDTS, "player", tok)
      if not ok then t, s, sp, rp, v = "error", "error", "error", "error", "error" end
      local okp, plate = pcall(GetNamePlateForUnit, tok)
      local h = okp and plate and holders[plate]
      print(format("  |cff4fc3f7%s|r threat=%s tanking=%s status=%s scaled=%s raw=%s | hideValues=%s hideState=%s | mobInCombat=%s | plate=%s%s",
        tok, D(v), D(t), D(s), D(sp), D(rp),
        D(Try(S.ShouldUnitThreatValuesBeSecret, "player", tok)),
        D(Try(S.ShouldUnitThreatStateBeSecret, "player", tok)),
        D(Try(UnitAffectingCombat, tok)),
        (okp and plate) and "yes" or "no",
        h and format(" showing=%s via=%s", tostring(h.vis and true or false), tostring(h.via)) or ""))
      shown = shown + 1
    end
  end
  if shown == 0 then print("  no target / mouseover / nameplates to test - target an enemy you're fighting") end

  -- Every other token that could reach a hidden plate's mob, and whether the
  -- game lets us read it and match it to a nameplate.
  flushId = flushId + 1 -- fresh lookups
  local parts, plateGUIDs = {}, 0
  for _, h in pairs(active) do if h.unit and SafeGUID(h.unit) then plateGUIDs = plateGUIDs + 1 end end
  for i = 1, nRoutes do
    local tok = routes[i]
    local exists = Try(UnitExists, tok)
    if issecret(exists) or exists == true then
      local ok, _, _, _, _, v = pcall(UDTS, "player", tok)
      local how = RoutePlate(i) and "plate" or (RouteGUID(i) and "guid" or "no plate")
      parts[#parts + 1] = format("%s %s/%s", tok,
        not ok and "error" or issecret(v) and "|cffff5555hidden|r" or "|cff55ff55readable|r", how)
    end
  end
  print("  routes: " .. (#parts > 0 and table.concat(parts, ", ")
    or "none right now (no target, focus, mouseover or group-member target)"))
  local live, dim = 0, 0
  for _, h in pairs(active) do
    if h.vis then if h.dim then dim = dim + 1 else live = live + 1 end end
  end
  print(format("  enemy plates: %d total, %d live, %d dimmed (last known); plate GUIDs readable: %d",
    n, live, dim, plateGUIDs))
  local u1 = units[1]
  if u1 then
    local _, _, _, _, gv = UDTS(u1, "target")
    print(format("  group check: %s vs target threat=%s", u1, D(gv)))
  end
  print(format("  threat events so far: %d from nameplate units, %d from other units (target/focus/boss...)",
    evCount.nameplate, evCount.other))
end

-- For the meter: everyone in the group except you (tokens), and the count.
function TD.GetGroupUnits() return units, nUnits end

function TD:RoleText()
  if DB.role == "AUTO" then return tankMode and "Auto (tank)" or "Auto (dps/heal)" end
  return DB.role == "TANK" and "Tank" or "DPS / Healer"
end

function _G.ThreatDiff_OnAddonCompartmentClick()
  if TD.ToggleConfig then TD:ToggleConfig() end
end

TD.S = { SECURE = S_SECURE, TANKING = S_TANKING, INSECURE = S_INSECURE,
         OTHERTANK = S_OTHERTANK, PET = S_PET, LOOSE = S_LOOSE, SAFE = S_SAFE,
         WARN = S_WARN, DANGER = S_DANGER, AGGRO = S_AGGRO }
