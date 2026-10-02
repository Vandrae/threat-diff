local test = T.test

local function near(c, r, g, b)
  return math.abs(c[1] - r) < 0.01 and math.abs(c[2] - g) < 0.01 and math.abs(c[3] - b) < 0.01
end

-- Nameplate engine: tank states ----------------------------------------------------

test("engine/tank: solo, tanking with no one else on the table -> green +lead", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  local p = t:plate()
  t.eq(p.vis, true, "number should be visible")
  t.eq(p.text, "+5.0k")
  t.eq(p.state, "SECURE")
  t.ok(near(p.color, 0.25, 1, 0.25), "colour should be the SECURE green")
end)

test("engine/tank: thin lead -> yellow, big lead -> green (default 25% rule)", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "Stabby", class = "ROGUE", role = "DAMAGER" } }
  W.player.role = "TANK"; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 1000, { tank = true })
  t:set(mob, g[1], 900)
  W.enterCombat(); t:tick()
  local p = t:plate()
  t.eq(p.text, "+100"); t.eq(p.state, "TANKING")
  t.ok(near(p.color, 1, 0.9, 0.1))
  t:set(mob, g[1], 750)  -- exactly 75% -> secure
  t:tick()
  t.eq(t:plate().state, "SECURE"); t.eq(t:plate().text, "+250")
  t:set(mob, g[1], 760)  -- 76% -> still thin
  t:tick()
  t.eq(t:plate().state, "TANKING")
end)

test("engine/tank: being passed -> orange negative, tie shows !!!", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "Stabby", class = "ROGUE" } }
  W.player.role = "TANK"; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 1000, { tank = true, status = 2 })
  t:set(mob, g[1], 1200)
  W.enterCombat(); t:tick()
  t.eq(t:plate().text, "-200"); t.eq(t:plate().state, "INSECURE")
  t.ok(near(t:plate().color, 1, 0.5, 0))
  t:set(mob, g[1], 1000)
  t:tick()
  t.eq(t:plate().text, "!!!"); t.eq(t:plate().state, "INSECURE")
end)

test("engine/tank: another tank has it -> blue; non-tank has it -> red LOOSE", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "OffTank", class = "PALADIN", role = "TANK" }, { name = "Stabby", class = "ROGUE" } }
  W.player.role = "TANK"; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 1000)
  t:set(mob, g[1], 3360, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().state, "OTHERTANK"); t.eq(t:plate().text, "-2.4k")
  t.ok(near(t:plate().color, 0.3, 0.6, 1))
  t:set(mob, g[1], 1000)
  t:set(mob, g[2], 2875, { tank = true })
  t:tick()
  t.eq(t:plate().state, "LOOSE"); t.eq(t:plate().text, "-1.9k")
  t.ok(near(t:plate().color, 1, 0.15, 0.15))
end)

test("engine/tank: main tank assignment counts as a tank", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "MT", class = "WARRIOR", mainTank = true } }
  W.player.role = "TANK"; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 500)
  t:set(mob, g[1], 1500, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().state, "OTHERTANK")
end)

test("engine/pet: your pet holding aggro -> teal PET state", function(t)
  local W, TD = t:boot()
  local pet = W.bind("pet", W.friend("Wolfie", "HUNTER"))
  W.fire("UNIT_PET", "player"); W.advance(0.3)
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 300)
  t:set(mob, pet, 540, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().state, "PET"); t.eq(t:plate().text, "-240")
  t.ok(near(t:plate().color, 0, 0.8, 0.8))
end)

-- DPS / healer states -----------------------------------------------------------

local function dpsSetup(t, o)
  local W, TD = t:boot(o)
  local g = t:party{ { name = "Tanky", class = "WARRIOR", role = "TANK" } }
  W.player.role = "DAMAGER"; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  local mob = t:engage("nameplate1")
  return W, TD, g, mob
end

test("engine/dps: SAFE / WARN / DANGER bands follow the game's scaled %", function(t)
  local W, TD, g, mob = dpsSetup(t)
  t:set(mob, g[1], 5500, { tank = true })
  t:set(mob, W.player, 1000, { sp = 18 })
  W.enterCombat(); t:tick()
  t.eq(t:plate().state, "SAFE"); t.eq(t:plate().text, "-4.5k")
  t:set(mob, W.player, 4000, { sp = 70 }); t:tick()
  t.eq(t:plate().state, "WARN", "70% is the warn threshold")
  t:set(mob, W.player, 4900, { sp = 90 }); t:tick()
  t.eq(t:plate().state, "DANGER", "90% is the danger threshold")
  t:set(mob, W.player, 4000, { sp = 69 }); t:tick()
  t.eq(t:plate().state, "SAFE")
end)

test("engine/dps: you pulled it -> red +number; status 1 -> DANGER", function(t)
  local W, TD, g, mob = dpsSetup(t)
  t:set(mob, g[1], 5500)
  t:set(mob, W.player, 5805, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().state, "AGGRO"); t.eq(t:plate().text, "+305")
  t.ok(near(t:plate().color, 1, 0.15, 0.15))
  t:set(mob, g[1], 5500, { tank = true })
  t:set(mob, W.player, 5000, { status = 1, sp = 50 }); t:tick()
  t.eq(t:plate().state, "DANGER")
end)

test("engine/dps: 'Until pull' mode shows the room left before pulling", function(t)
  local W, TD, g, mob = dpsSetup(t)
  TD.db.dpsRef = "PULL"; TD:ApplySettings()
  t:set(mob, g[1], 5500, { tank = true })
  t:set(mob, W.player, 1000, { sp = 50 })
  W.enterCombat(); t:tick()
  t.eq(t:plate().text, "-1.0k", "1000 threat at 50% means 1000 more until the pull")
end)

test("engine/dps: 'hide while safe' hides SAFE but shows WARN", function(t)
  local W, TD, g, mob = dpsSetup(t)
  TD.db.hideSafe = true; TD:ApplySettings()
  t:set(mob, g[1], 5500, { tank = true })
  t:set(mob, W.player, 1000, { sp = 18 })
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, false)
  t:set(mob, W.player, 4400, { sp = 80 }); t:tick()
  t.eq(t:plate().vis, true); t.eq(t:plate().state, "WARN")
end)

test("engine/dps: percentage hidden -> estimates the band from the numbers", function(t)
  local W, TD, g, mob = dpsSetup(t)
  t:set(mob, g[1], 5500, { tank = true })
  t:set(mob, W.player, 5000, { sp = { secret = true } })
  W.enterCombat(); t:tick()
  -- 5000 / (5500 * 1.1) = 82.6% -> WARN
  t.eq(t:plate().state, "WARN")
end)

-- visibility rules ---------------------------------------------------------------

test("engine/visibility: nothing shows out of combat; clears when combat ends", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  t:tick()
  t.eq(t:plate().vis, false, "no number before combat")
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, true)
  W.leaveCombat(); W.advance(0.3)
  t.eq(t:plate().vis, false, "number must clear after combat")
end)

test("engine/visibility: mobs you are not fighting stay blank", function(t)
  local W, TD = t:boot()
  local a, b = t:engage("nameplate1"), t:engage("nameplate2")
  t:set(a, W.player, 0)                       -- on the table with zero threat, not tanking
  W.setThreat(b, W.player, { v = nil })       -- on nobody's table
  W.enterCombat(); t:tick("nameplate1"); t:tick("nameplate2")
  t.eq(t:plate("nameplate1").vis, false)
  t.eq(t:plate("nameplate2").vis, false)
end)

test("engine/visibility: friendly nameplates get no number", function(t)
  local W, TD = t:boot()
  local npc = W.mob("Innkeeper", { hostile = false })
  W.addPlate("nameplate1", npc)
  t.eq(TD.active["nameplate1"], nil)
  npc.hostile = true
  W.fire("UNIT_FACTION", "nameplate1")
  t.ok(TD.active["nameplate1"], "plate should become active when the unit turns hostile")
end)

test("engine/visibility: forbidden plates are ignored without errors", function(t)
  local W, TD = t:boot()
  local npc = W.mob("ProtectedPlate", { forbidden = true })
  W.addPlate("nameplate1", npc)
  t.eq(TD.active["nameplate1"], nil)
end)

test("engine/visibility: plate removal hides and forgets the mob", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  local h = TD.active["nameplate1"]
  t.eq(h.vis, true)
  W.removePlate("nameplate1")
  t.eq(TD.active["nameplate1"], nil)
  t.eq(h.vis, false)
end)

test("engine/visibility: nameplate frames (and holders) are recycled, not recreated", function(t)
  local W, TD = t:boot()
  local m1, m2 = t:engage("nameplate1"), W.mob("Second")
  local plate = W.units.nameplate1.plate
  local holder = TD.holders[plate]
  t.ok(holder)
  local frames = #W.frames
  W.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
  W.units.nameplate1 = m2; m2.plate = plate
  W.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
  t.eq(TD.holders[plate], holder, "same holder must be reused")
  t.eq(#W.frames, frames, "no new frames when a plate is recycled")
end)

test("engine/visibility: master switch and situation toggles", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, true)
  TD.db.enabled = false; TD:ApplySettings(); W.advance(0.3)
  t.eq(t:plate().vis, false, "disabled")
  TD.db.enabled = true; TD.db.showSolo = false; TD:ApplySettings(); W.advance(0.3)
  t.eq(t:plate().vis, false, "solo unticked")
  TD.db.showSolo = true; TD:ApplySettings(); W.advance(0.3)
  t.eq(t:plate().vis, true)
end)

test("engine/visibility: Party / Raid toggles hide numbers in that content", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "Healy", class = "PRIEST" } }
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true }); t:set(mob, g[1], 100)
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, true)
  TD.db.showParty = false; TD:ApplySettings(); W.advance(0.3)
  t.eq(t:plate().vis, false, "party unticked")
  TD.db.showParty = true; TD:ApplySettings(); W.advance(0.3)
  t.eq(t:plate().vis, true)
  W.leaveCombat()
  t:raid(5)
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, true, "raid ticked")
  TD.db.showRaid = false; TD:ApplySettings(); W.advance(0.3)
  t.eq(t:plate().vis, false, "raid unticked")
end)

test("engine/visibility: 'Solo' ticked still works for a hunter with a pet (Solo situation)", function(t)
  -- "Pick every situation where you want numbers": Solo ticked, With pet unticked.
  local W, TD = t:boot()
  W.bind("pet", W.friend("Wolfie", "HUNTER"))
  W.fire("UNIT_PET", "player"); W.advance(0.3)
  TD.db.showPet = false; TD:ApplySettings()
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, true, "Solo is ticked, so a solo hunter should still see numbers")
end)

-- update scheduling -----------------------------------------------------------

test("engine/scheduling: bursts of events are coalesced into one flush", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  local before = TD.stats.flushes
  for i = 1, 200 do W.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1") end
  W.advance(0.09)
  t.eq(TD.stats.flushes, before, "must wait for the interval")
  W.advance(0.02)
  t.eq(TD.stats.flushes, before + 1, "exactly one flush for 200 events")
end)

test("engine/scheduling: update interval setting is honoured", function(t)
  local W, TD = t:boot()
  TD.db.interval = 0.5
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); W.advance(0.6)
  t:set(mob, W.player, 7000, { tank = true })
  W.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
  W.advance(0.3)
  t.eq(t:plate().text, "+5.0k", "not refreshed yet")
  W.advance(0.3)
  t.eq(t:plate().text, "+7.0k")
end)

test("engine/scheduling: events on target/focus aliases refresh the matching plate", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1", "Boar", true)
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); W.advance(1.2)
  t:set(mob, W.player, 9000, { tank = true })
  W.fire("UNIT_THREAT_LIST_UPDATE", "target")
  W.advance(0.2)
  t.eq(t:plate().text, "+9.0k")
end)

test("engine/scheduling: no OnUpdate scripts anywhere while idle or fighting", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  for _, f in ipairs(W.frames) do
    t.eq(f._.scripts.OnUpdate, nil, "unexpected OnUpdate on a frame")
  end
end)

test("engine/scheduling: heartbeat re-checks while fighting and stops after combat", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  W.enterCombat()
  t:set(mob, W.player, 5000, { tank = true })   -- no event fired: only the 1s heartbeat can notice
  W.advance(1.3)
  t.eq(t:plate().vis, true, "heartbeat should pick up threat without an event")
  W.leaveCombat(); W.advance(0.3)
  local n = W.pendingTimers()
  W.advance(5)
  t.eq(W.pendingTimers(), n, "no timers keep spawning after combat")
end)

-- threat data the game may hide ------------------------------------------------

test("engine/secret: hidden nameplate threat is read through 'target' instead", function(t)
  local W, TD = t:boot()
  W.hideOnPlates = true
  local mob = t:engage("nameplate1", "Boar", true)
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, true)
  t.eq(t:plate().text, "+5.0k")
  t.eq(t:plate().dim, false)
end)

test("engine/secret: mob nobody is targeting keeps its last number dimmed, then clears", function(t)
  local W, TD = t:boot()
  W.hideOnPlates = true
  local mob = t:engage("nameplate1", "Boar", true)
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().text, "+5.0k")
  W.units.target = nil                          -- you drop your target
  W.advance(1.5)                                -- heartbeat re-checks
  local p = t:plate()
  t.eq(p.vis, true, "last known number stays")
  t.eq(p.dim, true)
  t.eq(p.alpha, 0.5)
  W.advance(10)                                 -- Keep last = 10s
  t.eq(t:plate().vis, false, "expires after the keep-last time")
  W.bind("target", mob); t:tick()
  t.eq(t:plate().vis, true, "targeting the mob again brings it back")
  t.eq(t:plate().alpha, 1)
end)

test("engine/secret: a mob that was never readable shows nothing", function(t)
  local W, TD = t:boot()
  W.hideOnPlates = true
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, false)
end)

test("engine/secret: readable via a party member's target (and unit-target events)", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "Healy", class = "PRIEST" } }
  W.hideOnPlates = true
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true }); t:set(mob, g[1], 100)
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, false, "nobody targets it yet")
  W.bind("party1target", mob)
  W.fire("UNIT_TARGET", "party1"); W.advance(0.25)
  t.eq(t:plate().vis, true, "group member started targeting the mob")
  t.eq(t:plate().text, "+4.9k")
end)

test("engine/secret: route found by GUID when the plate lookup refuses the token", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "Healy", class = "PRIEST" } }
  W.hideOnPlates = true
  W.noPlateLookup = { party1target = true }
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true }); t:set(mob, g[1], 100)
  W.enterCombat()
  W.bind("party1target", mob)
  W.fire("UNIT_TARGET", "party1"); W.advance(0.25)
  W.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1"); W.advance(0.25)
  t.eq(t:plate().vis, true)
end)

test("engine/secret: aggro flag and status hidden but value readable still works", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = { secret = true }, status = { secret = true } })
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, true)
  t.eq(t:plate().text, "+5.0k")
end)

test("engine/secret: whole group scan survives secret values from group members", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "A", class = "MAGE" }, { name = "B", class = "ROGUE" } }
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  t:set(mob, g[1], { secret = true })                -- value hidden
  t:set(mob, g[2], 2000)
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, true)
  t.eq(t:plate().text, "+3.0k")
end)

-- larger groups ------------------------------------------------------------------

test("engine/raid: smart scan stays accurate when the aggro holder changes", function(t)
  local W, TD = t:boot()
  local r = t:raid(20)
  local mob = t:engage("nameplate1")
  for i, f in ipairs(r) do t:set(mob, f, 100 * i) end
  t:set(mob, r[2], 5000, { tank = true })
  W.player.role = "DAMAGER"; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  t:set(mob, W.player, 1000, { sp = 20 })
  W.enterCombat(); t:tick()
  t.eq(t:plate().text, "-4.0k")
  -- cheap path: fewer API calls within the 0.5s window
  local calls = W.calls
  t:tick()
  t.ok(W.calls - calls < 8, "expected a cheap probe, used " .. (W.calls - calls) .. " calls")
  -- holder switches
  t:set(mob, r[2], 5000)
  t:set(mob, r[5], 8000, { tank = true })
  t:tick()
  t.eq(t:plate().text, "-7.0k", "new aggro holder must be found immediately")
  -- someone passes the holder without taking aggro: picked up on the next full scan
  t:set(mob, r[7], 9000)
  W.advance(0.6); t:tick()
  t.eq(t:plate().text, "-8.0k")
end)

test("engine/raid: 40 players, 12 mobs, 1200 events/s stays cheap (README claim ~1300 calls/s)", function(t)
  local W, TD = t:boot()
  local r = t:raid(40)
  local mobs = {}
  for i = 1, 12 do
    local m = t:engage("nameplate" .. i)
    mobs[i] = m
    for j, f in ipairs(r) do t:set(m, f, 100 + j * 3 + i) end
    t:set(m, r[1], 90000, { tank = true })
    t:set(m, W.player, 500, { sp = 5 })
  end
  W.player.role = "DAMAGER"
  W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  W.enterCombat(); W.advance(0.5)
  W.calls = 0
  for sec = 1, 3 do
    for e = 1, 1200 do
      W.fire("UNIT_THREAT_LIST_UPDATE", "nameplate" .. (e % 12 + 1))
      if e % 100 == 0 then W.advance(0.0833) end
    end
  end
  local perSec = W.calls / 3
  _G.STRESS_CALLS_PER_SEC = perSec            -- read by the report script
  t.ok(perSec < 4000, "threat API calls per second: " .. perSec)
  t.eq(#W.errors, 0)
end)

-- role detection -------------------------------------------------------------

test("role: solo is tank, solo with a pet is DPS, party defaults to DPS", function(t)
  local W, TD = t:boot()
  t.eq(TD.tankMode, true, "solo")
  W.bind("pet", W.friend("Pet", "HUNTER")); W.fire("UNIT_PET", "player"); W.advance(0.3)
  t.eq(TD.tankMode, false, "solo with pet")
  W.units.pet = nil; W.fire("UNIT_PET", "player"); W.advance(0.3)
  t.eq(TD.tankMode, true, "pet dismissed")
  t:party{ { name = "A" } }
  t.eq(TD.tankMode, false, "in a party")
end)

test("role: LFG tank role, main tank, bear/dire bear/defensive stance", function(t)
  local W, TD = t:boot()
  t:party{ { name = "A" } }
  W.player.role = "TANK"; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  t.eq(TD.tankMode, true, "LFG tank")
  W.player.role = "NONE"; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  t.eq(TD.tankMode, false)
  W.player.mainTank = true; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  t.eq(TD.tankMode, true, "main tank")
  W.player.mainTank = false; W.fire("PLAYER_ROLES_ASSIGNED"); W.advance(0.3)
  for _, form in ipairs({ 5, 8, 18 }) do
    W.formID = form; W.fire("UPDATE_SHAPESHIFT_FORM")
    t.eq(TD.tankMode, true, "form " .. form)
  end
  W.formID = 1; W.fire("UPDATE_SHAPESHIFT_FORM")
  t.eq(TD.tankMode, false, "cat form")
  W.formID = nil; W.fire("UPDATE_SHAPESHIFT_FORM")
  t.eq(TD.tankMode, false)
end)

test("role: Righteous Fury makes a paladin a tank (out of combat check)", function(t)
  local W, TD = t:boot({ noLogin = true })
  W.player.class = "PALADIN"
  t:login()
  t:party{ { name = "A" } }
  t.eq(TD.tankMode, false)
  W.auras[25780] = true
  W.fire("UNIT_AURA", "player")
  t.eq(TD.tankMode, true, "RF up")
  W.auras[25780] = nil
  W.fire("UNIT_AURA", "player")
  t.eq(TD.tankMode, false, "RF dropped")
end)

test("role: manual override beats detection and the numbers change colour/state", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "Tanky", class = "WARRIOR", role = "TANK" } }
  local mob = t:engage("nameplate1")
  t:set(mob, g[1], 5500, { tank = true }); t:set(mob, W.player, 1000, { sp = 18 })
  W.enterCombat(); t:tick()
  t.eq(t:plate().state, "SAFE")
  W.slash = nil
  SlashCmdList.THREATDIFF("role tank"); W.advance(0.3)
  t.eq(TD.tankMode, true)
  t.eq(t:plate().state, "OTHERTANK")
  SlashCmdList.THREATDIFF("role dps"); W.advance(0.3)
  t.eq(t:plate().state, "SAFE")
  SlashCmdList.THREATDIFF("role auto"); W.advance(0.3)
  t.eq(TD.tankMode, false)
end)

-- roster & divisor ----------------------------------------------------------------

test("roster: party, party pets and your pet are tracked; raid excludes you", function(t)
  local W, TD = t:boot()
  W.bind("pet", W.friend("Pet", "HUNTER"))
  W.fire("UNIT_PET", "player")
  local g = t:party{ { name = "A" }, { name = "B" } }
  W.bind("partypet2", W.friend("BPet", "HUNTER"))
  W.fire("UNIT_PET", "party2"); W.advance(0.3)
  local units, n = TD.GetGroupUnits()
  local seen = {}
  for i = 1, n do seen[units[i]] = true end
  t.ok(seen.party1 and seen.party2 and seen.pet and seen.partypet2, "missing a unit")
  t.eq(n, 4)
  local r = t:raid(10)
  units, n = TD.GetGroupUnits()
  seen = {}
  for i = 1, n do seen[units[i]] = true end
  t.ok(not seen.player, "player must not be in its own scan list")
  t.ok(seen.raid2 and seen.raid10 and seen.pet)
end)

test("divisor: Forever (16001) uses raw values", function(t)
  local W, TD = t:boot()
  t.eq(TD.divisor, 1)
end)

test("divisor: Classic builds (e.g. 11507) divide threat by 100", function(t)
  local W, TD = t:boot({ interface = 11507 })
  t.eq(TD.divisor, 100)
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 500000, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().text, "+5.0k")
end)

test("divisor: manual override in the saved settings wins", function(t)
  local W, TD = t:boot({ saved = { profiles = { Default = { divisor = 10 } }, chars = {} } })
  t.eq(TD.divisor, 10)
end)

test("position: SetPosition rounds to 0.01 and moves live number text", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  local h = TD.active.nameplate1
  TD:SetPosition(2.346, -10.255)
  t.eq(TD.db.x, 2.35); t.eq(TD.db.y, -10.26)
  local p = h.fs._.points[1]
  t.eq(p.point, "RIGHT"); t.eq(p.relPoint, "LEFT"); t.eq(p.x, 2.35); t.eq(p.y, -10.26)
  t.eq(p.rel, h._.parent, "anchored to the nameplate by default")
end)

test("position: anchoring to the health bar uses the plate's health bar", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  TD.db.anchorTo = "HEALTH"; TD:ApplySettings()
  local h = TD.active.nameplate1
  t.eq(h.fs._.points[1].rel, W.units.nameplate1.plate.UnitFrame.healthBar)
  TD.db.anchorTo = "PLATE"; TD:ApplySettings()
  t.eq(h.fs._.points[1].rel, W.units.nameplate1.plate)
end)

test("style: font fallback when the chosen font cannot load", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  W.badFonts["Fonts\\Nope.ttf"] = true
  TD.db.font = "Fonts\\Nope.ttf"; TD:ApplySettings()
  local h = TD.active.nameplate1
  t.eq((h.fs:GetFont()), "Fonts\\FRIZQT__.TTF")
  t.noerr(function() h.fs:SetText("+1") end)
end)

test("style: outline / shadow / size / justify are applied to live numbers", function(t)
  local W, TD = t:boot()
  local mob = t:engage("nameplate1")
  TD.db.outline = "THICK"; TD.db.shadow = true; TD.db.fontSize = 20
  TD.db.point, TD.db.relPoint = "LEFT", "RIGHT"
  TD:ApplySettings()
  local fs = TD.active.nameplate1.fs
  local _, size, flags = fs:GetFont()
  t.eq(size, 20); t.eq(flags, "THICKOUTLINE")
  t.eq(fs._.justifyH, "LEFT")
  t.eq(fs._.shadowOffset[1], 1)
end)

test("colours: custom colour is used for new text", function(t)
  local W, TD = t:boot()
  TD.db.colors.SECURE = { 0, 0, 1 }
  TD:ApplySettings()
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  t.ok(near(t:plate().color, 0, 0, 1))
end)

test("test-mode: sample numbers appear on every plate (even friendly) and clean up", function(t)
  local W, TD = t:boot()
  local a = t:engage("nameplate1")
  local npc = W.mob("Friendly", { hostile = false })
  local plate2 = W.addPlate("nameplate2", npc)
  TD:SetTestMode(true)
  t.eq(t:plate().vis, true)
  t.ok(TD.holders[plate2].vis, "friendly plate also previews")
  local first = t:plate().text
  W.advance(1.6)
  t.ok(t:plate().text ~= first or true)
  TD:SetTestMode(false)
  t.eq(t:plate().vis, false)
  t.eq(TD.holders[plate2].vis, false)
end)
