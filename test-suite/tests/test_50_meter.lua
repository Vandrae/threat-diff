local test = T.test

-- helpers ------------------------------------------------------------------------
local function parts(W)
  local m = _G.ThreatDiffMeter
  local header, body, grip = m._.children[1], m._.children[2], m._.children[3]
  local fs = {}
  for _, r in ipairs(header._.regions) do if r._.kind == "FontString" then fs[#fs + 1] = r end end
  return { meter = m, header = header, body = body, grip = grip,
    title = fs[1], diff = fs[2], name = fs[3], empty = body._.regions[1], rows = body._.children }
end

local function shownRows(p)
  local out = {}
  for _, r in ipairs(p.rows) do if r:IsShown() then out[#out + 1] = r end end
  return out
end

local function refresh(W) W.fire("UNIT_THREAT_LIST_UPDATE", "target"); W.advance(0.3) end

-- group of 4 fighting a mob you target. Returns mob and members.
local function fight(t)
  local W, TD = t:boot()
  local g = t:party{
    { name = "Thorgrim", class = "WARRIOR", role = "TANK" },
    { name = "Sylvie", class = "ROGUE" },
    { name = "Oona", class = "DRUID" },
  }
  local mob = W.mob("Defias Thug")
  W.bind("target", mob)
  t:set(mob, g[1], 12500, { tank = true })
  t:set(mob, W.player, 8900, { sp = 65, rp = 40 })
  t:set(mob, g[2], 9100)
  t:set(mob, g[3], 1800)
  refresh(W)
  return W, TD, mob, g
end

-- frame & basic content -----------------------------------------------------------

test("meter: window exists at login with the saved size and position", function(t)
  local W, TD = t:boot()
  local p = parts(W)
  t.ok(p.meter:IsShown(), "meter should be visible by default")
  t.eq(p.meter:GetWidth(), 260)
  local pt = p.meter._.points[1]
  t.eq(pt.point, "TOPLEFT"); t.eq(pt.relPoint, "CENTER"); t.eq(pt.x, 260); t.eq(pt.y, 120)
  t.eq(p.title._.text, "Threat")
end)

test("meter: no target says 'Target an enemy'", function(t)
  local W, TD = t:boot()
  local p = parts(W)
  W.advance(0.3)
  t.eq(#shownRows(p), 0)
  t.eq(p.empty._.text, "Target an enemy")
  t.eq(p.empty:IsShown(), true)
end)

test("meter: hostile target with no threat says 'No threat yet'", function(t)
  local W, TD = t:boot()
  W.bind("target", W.mob("Idle"))
  refresh(W)
  t.eq(parts(W).empty._.text, "No threat yet")
end)

test("meter: ranks everyone highest first and sorts the pull rows in", function(t)
  local W, TD, mob, g = fight(t)
  local p = parts(W)
  local rows = shownRows(p)
  t.eq(#rows, 6, "ranged, melee, 4 players")
  t.has(rows[1].name._.text, "Ranged pull at")
  t.has(rows[2].name._.text, "Melee pull at")
  t.has(rows[3].name._.text, "^1%. Thorgrim")
  t.has(rows[4].name._.text, "^2%. Sylvie")
  t.has(rows[5].name._.text, "^3%. Tester")
  t.has(rows[6].name._.text, "^4%. Oona")
  t.has(rows[1].value._.text, "16%.2k")   -- 12500 * 1.3 = 16250
  t.has(rows[2].value._.text, "13%.8k")   -- 12500 * 1.1
end)

test("meter: percentages are of the aggro holder; your row is highlighted; aggro marker on the holder", function(t)
  local W, TD, mob, g = fight(t)
  local rows = shownRows(parts(W))
  t.has(rows[3].value._.text, "12%.5k.*100%.0%%")
  t.has(rows[5].value._.text, "8%.9k.*71%.2%%")
  t.eq(rows[5].hl:IsShown(), true, "own row highlighted")
  t.eq(rows[3].hl:IsShown(), false)
  t.eq(rows[3].aggro:IsShown(), true, "red edge on the aggro holder")
  t.eq(rows[4].aggro:IsShown(), false)
end)

test("meter: class colours and icons, pet row styling", function(t)
  local W, TD, mob, g = fight(t)
  local pet = W.bind("pet", W.friend("Wolfie", "HUNTER"))
  W.fire("UNIT_PET", "player"); W.advance(0.3)
  t:set(mob, pet, 4000)
  refresh(W)
  local rows = shownRows(parts(W))
  local war = rows[3]
  t.eq(war.bar._.sbColor[1], RAID_CLASS_COLORS.WARRIOR.r)
  t.eq(war.icon._.texture, "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
  local petRow
  for _, r in ipairs(rows) do if r.name._.text:find("Wolfie") then petRow = r end end
  t.ok(petRow, "pet row exists")
  t.eq(petRow.icon._.texture, "Interface\\Icons\\Ability_Hunter_BeastTaming")
  t.near(petRow.bar._.sbColor[2], 0.8, 0.01)
  t.eq(rows[1].icon._.texture, "Interface\\Icons\\INV_Weapon_Bow_07")
  t.near(rows[1].bar._.sbColor[1], 0.75, 0.01, "pull rows are red")
end)

test("meter: class colours / icons / rank numbers / highlight can be switched off", function(t)
  local W, TD, mob, g = fight(t)
  local m = TD.db.meter
  m.classColors, m.classIcons, m.rankNumbers, m.highlightYou = false, false, false, false
  TD:ApplySettings(); W.advance(0.3)
  local rows = shownRows(parts(W))
  t.eq(rows[3].name._.text, "Thorgrim")
  t.eq(rows[3].icon:IsShown(), false)
  t.near(rows[3].bar._.sbColor[1], 0.7, 0.01, "grey when class colours are off")
  t.eq(rows[5].hl:IsShown(), false)
end)

test("meter: value formats THREAT and GAP", function(t)
  local W, TD, mob, g = fight(t)
  TD.db.meter.valueFormat = "THREAT"; TD:ApplySettings(); W.advance(0.3)
  local rows = shownRows(parts(W))
  t.eq(rows[3].value._.text, "12.5k")
  TD.db.meter.valueFormat = "GAP"; TD:ApplySettings(); W.advance(0.3)
  rows = shownRows(parts(W))
  t.has(rows[3].value._.text, "12%.5k.*%+3%.6k", "tank row shows difference to you")
  t.has(rows[5].value._.text, "8%.9k.*%-3%.6k", "your row shows your lead/gap to the next person")
end)

test("meter: pull-row modes BOTH / MELEE / RANGED / MINE / OFF", function(t)
  local W, TD, mob, g = fight(t)
  local function labels()
    local out = {}
    for _, r in ipairs(shownRows(parts(W))) do
      local n = r.name._.text
      if n:find("pull") then out[#out + 1] = n end
    end
    return table.concat(out, "|")
  end
  local m = TD.db.meter
  m.pullRows = "MELEE"; TD:ApplySettings(); W.advance(0.3);  t.eq(labels(), "Melee pull at")
  m.pullRows = "RANGED"; TD:ApplySettings(); W.advance(0.3); t.eq(labels(), "Ranged pull at")
  m.pullRows = "OFF"; TD:ApplySettings(); W.advance(0.3);    t.eq(labels(), "")
  m.pullRows = "MINE"; TD:ApplySettings(); W.advance(0.3)
  t.eq(labels(), "Your pull at")
  local rows = shownRows(parts(W))
  local mine
  for _, r in ipairs(rows) do if r.name._.text == "Your pull at" then mine = r end end
  t.has(mine.value._.text, "13%.7k", "8900 at 65% => pull at 13692")
  m.pullRows = "BOTH"; TD:ApplySettings(); W.advance(0.3);   t.eq(labels(), "Ranged pull at|Melee pull at")
end)

test("meter: holder outside the group is estimated from your raw percentage", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "Friend", class = "MAGE" } }
  local mob = W.mob("Boss")
  W.bind("target", mob)
  t:set(mob, W.player, 1000, { rp = 20 })        -- holder (outside the group) has 5000
  refresh(W)
  local rows = shownRows(parts(W))
  t.has(rows[1].value._.text, "6%.5k", "ranged = 5000 * 1.3")
  t.has(rows[2].value._.text, "5%.5k", "melee = 5000 * 1.1")
end)

test("meter: header shows the mob name and your number (colour of your nameplate)", function(t)
  local W, TD, mob, g = fight(t)
  local plate = W.addPlate("nameplate1", mob)
  W.enterCombat(); W.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1"); W.advance(0.3)
  refresh(W)
  local p = parts(W)
  t.eq(p.name._.text, "Defias Thug")
  local h = TD.active.nameplate1
  t.eq(p.diff._.text, h.txt)
  t.ok(p.diff._.text ~= "", "difference should show")
end)

test("meter: without a nameplate the header number is your gap to the next person", function(t)
  local W, TD, mob, g = fight(t)
  local p = parts(W)
  t.eq(p.diff._.text, "-3.6k")
end)

test("meter: healer view follows the friendly target's target", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "Tank", class = "WARRIOR", role = "TANK" } }
  local mob = W.mob("Thug")
  W.bind("target", g[1])                -- targeting a friend
  W.bind("targettarget", mob)
  t:set(mob, g[1], 7000, { tank = true }); t:set(mob, W.player, 900)
  W.fire("PLAYER_TARGET_CHANGED"); W.advance(0.3)
  local rows = shownRows(parts(W))
  t.ok(#rows >= 3, "expected rows from the tank's target")
  t.eq(parts(W).name._.text, "Thug")
end)

test("meter: window keeps its size and shows only the top rows that fit", function(t)
  local W, TD = t:boot()
  local g = t:party{}
  local mob = W.mob("Thug")
  W.bind("target", mob)
  -- 15 raiders
  local r = t:raid(15)
  for i, f in ipairs(r) do t:set(mob, f, 1000 + i * 10) end
  t:set(mob, W.player, 500)
  TD.db.meter.pullRows = "OFF"
  TD:ApplySettings(); refresh(W)
  local p = parts(W)
  t.eq(p.meter:GetHeight(), 214)
  t.eq(#shownRows(p), 10, "default height fits 10 rows")
  t.has(shownRows(p)[1].name._.text, "Raider15")
  TD.db.meter.height = 100; TD:ApplySettings(); W.advance(0.3)
  t.eq(p.meter:GetHeight(), 100)
  t.eq(#shownRows(p), TD.MeterRowsFit())
  t.eq(TD.MeterRowsFit(), 4)
  TD.db.meter.height = 10; TD:ApplySettings()
  t.eq(TD.db.meter.height, TD.MeterHeightFor(1, 18, 1), "never smaller than one row")
end)

test("meter: collapse hides the body, expand brings it back; the - / + button works", function(t)
  local W, TD, mob, g = fight(t)
  local p = parts(W)
  -- header children: close, options, collapse buttons (in that order)
  local collapse = p.header._.children[3]
  collapse:Click("LeftButton")
  t.eq(TD.db.meter.collapsed, true)
  t.eq(p.body:IsShown(), false)
  t.eq(p.meter:GetHeight(), 20)
  t.eq(collapse.text._.text, "+")
  collapse:Click("LeftButton")
  t.eq(p.body:IsShown(), true); t.eq(p.meter:GetHeight(), 214)
  t.eq(collapse.text._.text, "-")
end)

test("meter: close button hides it and says how to bring it back; options button opens the Meter page", function(t)
  local W, TD, mob, g = fight(t)
  local p = parts(W)
  local close, opts = p.header._.children[1], p.header._.children[2]
  W.clearChat()
  close:Click("LeftButton")
  t.eq(TD.db.meter.enabled, false); t.eq(p.meter:IsShown(), false)
  t.has(W.chatText(), "/tdiff meter")
  TD.db.meter.enabled = true; TD:ApplySettings()
  opts:Click("LeftButton")
  t.ok(_G.ThreatDiffConfig:IsShown(), "settings window should open")
  -- right-click on title bar does the same
  _G.ThreatDiffConfig:Hide()
  W.fireScript(p.header, "OnClick", "RightButton")
  t.ok(_G.ThreatDiffConfig:IsShown())
end)

test("meter: header buttons have tooltips", function(t)
  local W, TD = t:boot()
  local p = parts(W)
  local close = p.header._.children[1]
  W.fireScript(close, "OnEnter")
  t.eq(GameTooltip._.lines[1], "Hide the meter (/tdiff meter to show it again)")
  W.fireScript(close, "OnLeave")
end)

test("meter: dragging the title bar moves and saves the position (unless locked)", function(t)
  local W, TD = t:boot()
  local p = parts(W)
  W.fireScript(p.header, "OnDragStart")
  t.eq(p.meter._.moving, true)
  p.meter._.left, p.meter._.top = 100.4, 700.6
  W.fireScript(p.header, "OnDragStop")
  t.eq(p.meter._.moving, false)
  t.eq(TD.db.meter.x, 100); t.eq(TD.db.meter.y, 701)
  t.eq(TD.db.meter.point, "TOPLEFT"); t.eq(TD.db.meter.relPoint, "BOTTOMLEFT")
  local pt = p.meter._.points[1]
  t.eq(pt.point, "TOPLEFT"); t.eq(pt.rel, UIParent); t.eq(pt.x, 100)
  TD.db.meter.locked = true; TD:ApplySettings()
  W.fireScript(p.header, "OnDragStart")
  t.ok(not p.meter._.moving, "locked meter must not move")
  t.eq(p.grip:IsShown(), false, "no resize grip while locked")
end)

test("meter: resize grip changes width AND height, clamps, and saves", function(t)
  local W, TD = t:boot()
  local p = parts(W)
  W.cursor = { x = 500, y = 500 }
  W.fireScript(p.grip, "OnMouseDown")
  W.cursor = { x = 600, y = 440 }
  W.fireScript(p.grip, "OnUpdate", 0.01)
  t.eq(TD.db.meter.width, 360); t.eq(TD.db.meter.height, 274)
  t.eq(p.meter:GetWidth(), 360)
  W.cursor = { x = 9000, y = -9000 }
  W.fireScript(p.grip, "OnUpdate", 0.01)
  t.eq(TD.db.meter.width, 800); t.eq(TD.db.meter.height, 1200)
  W.cursor = { x = -9000, y = 9000 }
  W.fireScript(p.grip, "OnUpdate", 0.01)
  t.eq(TD.db.meter.width, 140); t.eq(TD.db.meter.height, TD.MeterHeightFor(1, 18, 1))
  W.fireScript(p.grip, "OnMouseUp")
  t.eq(p.grip._.scripts.OnUpdate, nil, "stops tracking the mouse on release")
end)

test("meter: 'only show in combat' hides out of combat and shows when a fight starts", function(t)
  local W, TD = t:boot()
  TD.db.meter.hideOOC = true; TD:ApplySettings()
  t.eq(_G.ThreatDiffMeter:IsShown(), false)
  W.enterCombat()
  t.eq(_G.ThreatDiffMeter:IsShown(), true)
  W.leaveCombat()
  t.eq(_G.ThreatDiffMeter:IsShown(), false)
  TD:SetTestMode(true)
  t.eq(_G.ThreatDiffMeter:IsShown(), true, "preview always shows it")
  TD:SetTestMode(false)
end)

test("meter: disabled at login builds no frame; enabling later builds it", function(t)
  local W, TD = t:boot({ saved = { profiles = { Default = { meter = { enabled = false } } }, chars = {} } })
  t.eq(_G.ThreatDiffMeter, nil)
  TD.db.meter.enabled = true; TD:ApplySettings()
  t.ok(_G.ThreatDiffMeter and _G.ThreatDiffMeter:IsShown())
end)

test("meter: events are only registered while it is visible", function(t)
  local W, TD = t:boot()
  local ev
  for _, f in ipairs(W.frames) do if f._.events.UNIT_THREAT_LIST_UPDATE and f._.scripts.OnEvent and f ~= TD.eventFrame then ev = f end end
  t.ok(ev, "meter event frame")
  TD.db.meter.enabled = false; TD:ApplySettings()
  t.eq(ev._.events.UNIT_THREAT_LIST_UPDATE, nil)
  t.eq(ev._.events.PLAYER_TARGET_CHANGED, nil)
  TD.db.meter.enabled = true; TD:ApplySettings()
  t.eq(ev._.events.UNIT_THREAT_LIST_UPDATE, true)
end)

test("meter: preview fills it with sample data and cleans up", function(t)
  local W, TD = t:boot()
  TD:SetTestMode(true)
  W.advance(0.3)
  local p = parts(W)
  t.eq(p.name._.text, "Training Dummy")
  local rows = shownRows(p)
  t.eq(#rows, 10)
  W.advance(1.6)
  TD:SetTestMode(false); W.advance(0.3)
  t.eq(p.empty._.text, "Target an enemy")
end)

test("meter: every bar style (and a missing LibSharedMedia style) renders", function(t)
  local W, TD, mob = fight(t)
  for _, key in ipairs({ "BLIZZARD", "FLAT", "GLOSS", "RAID", "THIN", "LSM:Missing", "bogus" }) do
    TD.db.meter.barStyle = key
    TD:ApplySettings(); W.advance(0.3)
    t.ok(#shownRows(parts(W)) > 0, "rows for " .. key)
  end
  t.eq(#W.errors, 0)
end)

test("meter: LibSharedMedia bars are offered and used when present", function(t)
  local W, TD = t:boot({ noLogin = true })
  local lsm = {
    List = function() return { "Smooth", "Aluminium" } end,
    Fetch = function(_, kind, name) return "Interface\\AddOns\\SharedMedia\\" .. name .. ".tga" end,
  }
  _G.LibStub = function(name) return lsm end
  t:login()
  local opts = TD.MeterStyleOptions()
  t.eq(#opts, 7)
  t.eq(opts[6][1], "LSM:Smooth")
  TD.db.meter.barStyle = "LSM:Smooth"
  TD:ApplySettings()
  local g = t:party{ { name = "A", class = "MAGE" } }
  local mob = W.mob("Thug"); W.bind("target", mob)
  t:set(mob, W.player, 100, { tank = true })
  refresh(W)
  local rows = shownRows(parts(W))
  t.eq(rows[1].bar._.sbTexture:find("Smooth") ~= nil, true)
end)

test("meter: a hidden (secret) threat value for a group member is skipped, not an error", function(t)
  local W, TD, mob, g = fight(t)
  t:set(mob, g[3], { secret = true })
  refresh(W)
  local rows = shownRows(parts(W))
  for _, r in ipairs(rows) do t.hasnt(r.name._.text, "Oona") end
  t.eq(#W.errors, 0)
end)

test("meter: transparency / border / fonts are applied", function(t)
  local W, TD = t:boot()
  local m = TD.db.meter
  m.bgAlpha, m.border, m.fontSize, m.outline = 0.2, false, 15, "THICK"
  TD:ApplySettings()
  local p = parts(W)
  t.near(p.meter._.bdColor[4], 0.2, 1e-6)
  t.eq(p.meter._.bdBorder[4], 0, "no border")
  local _, size, flags = p.title:GetFont()
  t.eq(size, 15); t.eq(flags, "THICKOUTLINE")
end)

test("meter: bad font falls back to the game font instead of erroring", function(t)
  local W, TD = t:boot()
  W.badFonts["Fonts\\Nope.ttf"] = true
  TD.db.meter.font = "Fonts\\Nope.ttf"
  TD:ApplySettings(); W.advance(0.3)
  t.eq((parts(W).title:GetFont()), "Fonts\\FRIZQT__.TTF")
end)

test("meter: ResetPosition restores the default spot", function(t)
  local W, TD = t:boot()
  TD.db.meter.x, TD.db.meter.y, TD.db.meter.point = 5, 6, "BOTTOM"
  TD.MeterResetPosition()
  t.eq(TD.db.meter.x, 260); t.eq(TD.db.meter.y, 120); t.eq(TD.db.meter.point, "TOPLEFT")
  t.eq(_G.ThreatDiffMeter._.points[1].x, 260)
end)

test("meter: rebuilt for a target switch without leaking rows", function(t)
  local W, TD, mob, g = fight(t)
  local p = parts(W)
  local count = #p.rows
  for i = 1, 20 do
    local m2 = W.mob("Other" .. i); W.bind("target", m2)
    t:set(m2, W.player, 100 * i, { tank = true })
    W.fire("PLAYER_TARGET_CHANGED"); W.advance(0.3)
  end
  t.ok(#p.rows <= count + 1, "rows are reused (" .. count .. " -> " .. #p.rows .. ")")
end)
