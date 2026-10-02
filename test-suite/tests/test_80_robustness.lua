local test = T.test

-- package / TOC ---------------------------------------------------------------------

test("package: TOC metadata is complete and consistent with the README", function(t)
  local W, TD = t:boot()
  t.eq(W.toc.Interface, "16001")
  t.eq(W.toc.Version, "1.4.1")
  t.eq(W.toc.SavedVariables, "ThreatDiffDB")
  t.eq(W.toc.AddonCompartmentFunc, "ThreatDiff_OnAddonCompartmentClick")
  t.ok(type(_G[W.toc.AddonCompartmentFunc]) == "function", "compartment function must exist as a global")
  t.ok(W.toc.IconTexture and W.toc.Notes and W.toc.Title)
  t.eq(#W.tocFiles, 6)
end)

test("package: every .lua file in the folder is listed in the TOC", function(t)
  local W, TD = t:boot()
  local listed = {}
  for _, f in ipairs(W.tocFiles) do listed[f:lower()] = true end
  local p = io.popen('dir /b "' .. ADDON_DIR:gsub("/", "\\") .. '"')
  t.ok(p, "could not list the folder")
  for name in p:lines() do
    name = name:gsub("\r", "")
    if name:lower():find("%.lua$") then t.ok(listed[name:lower()], name .. " is not in the TOC") end
  end
  p:close()
end)

test("package: loading prints nothing to chat and exports only the documented globals", function(t)
  local before = {}
  for k in pairs(_G) do before[k] = true end
  local W, TD = t:boot()
  t.eq(#W.chat, 0, "silent load: " .. W.chatText())
  local extra = {}
  for k in pairs(_G) do if not before[k] then extra[#extra + 1] = k end end
  table.sort(extra)
  local allowed = { ThreatDiff = true, ThreatDiffDB = true, ThreatDiff_OnAddonCompartmentClick = true,
    SLASH_THREATDIFF1 = true, SLASH_THREATDIFF2 = true, ThreatDiffMeter = true, ThreatDiffMinimapButton = true }
  for _, k in ipairs(extra) do
    -- the harness itself defines W/G style globals before the addon loads; only flag unexpected addon globals
    if k:find("^ThreatDiff") or k:find("^SLASH_") or k == "TD" then
      t.ok(allowed[k], "unexpected global: " .. k)
    end
  end
end)

-- hardening: hand-edited / damaged SavedVariables -----------------------------------------

test("hardening: an invalid saved anchor point must not break the nameplate numbers", function(t)
  local W, TD = t:boot({ saved = { profiles = { Default = { point = "BANANA" } }, chars = {} } })
  t:engage("nameplate1")
  t.eq(#W.errors, 0, "the client throws 'unknown anchor point' on every plate")
end)

test("hardening: a non-number saved offset must not break the nameplate numbers", function(t)
  local W, TD = t:boot({ saved = { profiles = { Default = { x = "wide", fontSize = "big" } }, chars = {} } })
  t:engage("nameplate1")
  t.eq(#W.errors, 0)
end)

-- hostile environments ---------------------------------------------------------------

test("compat: loads when optional events are missing on the client", function(t)
  local W, TD = t:boot({ badEvents = { PLAYER_SOFT_ENEMY_CHANGED = true, UNIT_FACTION = true, PLAYER_ROLES_ASSIGNED = true } })
  local mob = t:engage("nameplate1")
  t:set(mob, W.player, 5000, { tank = true })
  W.enterCombat(); t:tick()
  t.eq(t:plate().text, "+5.0k")
end)

test("compat: loads without the Blizzard Settings API", function(t)
  local W, TD = t:boot({ noSettings = true })
  t.eq(#W.settingsCategories, 0)
  SlashCmdList.THREATDIFF("")
  t.ok(_G.ThreatDiffConfig:IsShown())
end)

test("compat: older client with InterfaceOptions_AddCategory instead of Settings", function(t)
  local W, TD = t:boot({ noLogin = true, noSettings = true })
  local added
  _G.InterfaceOptions_AddCategory = function(panel) added = panel end
  t:login()
  t.ok(added, "legacy options category registered")
  t.eq(added.name, "ThreatDiff")
end)

test("compat: modern client without legacy aura/shapeshift/party-assignment APIs", function(t)
  local W, TD = t:boot({ noLogin = true })
  _G.C_UnitAuras = nil; _G.GetShapeshiftFormID = nil; _G.GetPartyAssignment = nil; _G.UnitGroupRolesAssigned = nil
  _G.C_CVar = nil
  t:login()
  W.player.class = "PALADIN"
  W.enterCombat()
  t.noerr(function() W.fire("UPDATE_SHAPESHIFT_FORM") end)
  t.eq(TD.tankMode, true, "solo")
end)

test("compat: GetMinimapShape / UnitClass returning secrets does not break the meter", function(t)
  local W, TD = t:boot()
  local g = t:party{ { name = "A", class = "MAGE" } }
  local mob = W.mob("Thug"); W.bind("target", mob)
  t:set(mob, W.player, 500, { tank = true }); t:set(mob, g[1], 100)
  local real = _G.UnitClass
  _G.UnitClass = function() return W.secret(), W.secret(), 1 end
  W.fire("PLAYER_TARGET_CHANGED"); W.advance(0.3)
  _G.UnitClass = real
  t.eq(#W.errors, 0)
end)

-- event handling ---------------------------------------------------------------------

test("events: re-entering the world repeatedly does not leak holders or frames", function(t)
  local W, TD = t:boot()
  t:engage("nameplate1"); t:engage("nameplate2")
  local frames, holders = #W.frames, 0
  for _ in pairs(TD.holders) do holders = holders + 1 end
  for i = 1, 5 do W.fire("PLAYER_ENTERING_WORLD"); W.advance(0.3) end
  local after = 0
  for _ in pairs(TD.holders) do after = after + 1 end
  t.eq(after, holders); t.eq(#W.frames, frames)
  t.ok(TD.active.nameplate1 and TD.active.nameplate2)
end)

test("events: roster spam is coalesced into one rebuild", function(t)
  local W, TD = t:boot()
  local before = W.pendingTimers()
  for i = 1, 50 do W.fire("GROUP_ROSTER_UPDATE"); W.fire("UNIT_PET", "player") end
  -- one roster rebuild + one meter redraw, no matter how many events
  t.eq(W.pendingTimers() - before, 2)
end)

test("events: malformed events (nil units, unknown tokens) are ignored", function(t)
  local W, TD = t:boot()
  W.enterCombat()
  t.noerr(function()
    W.fire("UNIT_THREAT_LIST_UPDATE")
    W.fire("UNIT_THREAT_LIST_UPDATE", "mouseover")
    W.fire("UNIT_THREAT_SITUATION_UPDATE")
    W.fire("UNIT_TARGET", "unknown7")
    W.fire("UNIT_FACTION")
    W.fire("UNIT_FACTION", "target")
    W.fire("NAME_PLATE_UNIT_REMOVED", "nameplate9")
    W.fire("PLAYER_TARGET_CHANGED"); W.fire("PLAYER_FOCUS_CHANGED")
    W.fire("UPDATE_MOUSEOVER_UNIT"); W.fire("PLAYER_SOFT_ENEMY_CHANGED")
  end)
  W.advance(1)
end)

test("events: nothing is created during combat once plates exist", function(t)
  local W, TD = t:boot()
  local m1, m2 = t:engage("nameplate1"), t:engage("nameplate2")
  local g = t:party{ { name = "A", class = "MAGE" } }
  W.enterCombat()
  local frames = #W.frames
  for i = 1, 30 do
    t:set(m1, W.player, 1000 + i * 10, { tank = true }); t:set(m1, g[1], 100)
    t:set(m2, W.player, 500 + i, { tank = true })
    W.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1"); W.fire("UNIT_THREAT_LIST_UPDATE", "nameplate2")
    W.advance(0.2)
  end
  t.eq(#W.frames, frames, "no frames created while fighting")
end)

test("events: 'enemy nameplates are off' hint appears once when combat starts", function(t)
  local W, TD = t:boot()
  W.cvars.nameplateShowEnemies = false
  W.enterCombat(); W.leaveCombat(); W.enterCombat()
  local n = 0
  for _, l in ipairs(W.chat) do if l:find("enemy nameplates are off") then n = n + 1 end end
  t.eq(n, 1)
end)

test("events: no hint when enemy nameplates are on", function(t)
  local W, TD = t:boot()
  W.enterCombat()
  t.eq(W.chatHas("nameplates are off"), nil)
end)

-- the reported multi-target behaviour -------------------------------------------------

test("multi-target: tanking two mobs, the untargeted one keeps a dimmed last value (game hides it), refreshes on target/mouseover", function(t)
  local W, TD = t:boot()
  W.hideOnPlates = true                                  -- Forever hides threat read through nameplate tokens
  local a, b = t:engage("nameplate1", "A", true), t:engage("nameplate2", "B")
  t:set(a, W.player, 5000, { tank = true }); t:set(b, W.player, 3000, { tank = true })
  W.enterCombat(); W.advance(0.3)
  t.eq(t:plate("nameplate1").text, "+5.0k")
  t.eq(t:plate("nameplate2").vis, false, "never readable yet")
  W.bind("target", b)                                    -- switch target to B
  W.fire("PLAYER_TARGET_CHANGED"); W.advance(0.3)
  t.eq(t:plate("nameplate2").text, "+3.0k")
  t:set(b, W.player, 3500, { tank = true })
  W.fire("UNIT_THREAT_LIST_UPDATE", "target"); W.advance(0.3)
  t.eq(t:plate("nameplate2").text, "+3.5k", "live while targeted")
  t:set(a, W.player, 9000, { tank = true })              -- A grows while untargeted
  W.advance(1.5)
  t.eq(t:plate("nameplate1").text, "+5.0k", "stale value stays")
  t.eq(t:plate("nameplate1").dim, true, "and is dimmed")
  W.bind("mouseover", a)
  W.fire("UPDATE_MOUSEOVER_UNIT"); W.advance(0.3)
  t.eq(t:plate("nameplate1").text, "+9.0k", "mouseover refreshes it")
  t.eq(t:plate("nameplate1").dim, false)
end)

test("multi-target: focus, soft-target and boss frames also provide live numbers", function(t)
  local W, TD = t:boot()
  W.hideOnPlates = true
  local a, b, c = t:engage("nameplate1", "A"), t:engage("nameplate2", "B"), t:engage("nameplate3", "C")
  for _, m in ipairs({ a, b, c }) do t:set(m, W.player, 4000, { tank = true }) end
  W.bind("focus", a); W.bind("softenemy", b); W.bind("boss1", c)
  W.enterCombat()
  W.fire("PLAYER_FOCUS_CHANGED"); W.fire("PLAYER_SOFT_ENEMY_CHANGED")
  for _, tok in ipairs({ "nameplate1", "nameplate2", "nameplate3" }) do W.fire("UNIT_THREAT_LIST_UPDATE", tok) end
  W.advance(0.3)
  for _, tok in ipairs({ "nameplate1", "nameplate2", "nameplate3" }) do t.eq(t:plate(tok).text, "+4.0k", tok) end
end)

test("multi-target: pet's target is readable too", function(t)
  local W, TD = t:boot()
  local pet = W.bind("pet", W.friend("Wolf", "HUNTER"))
  W.fire("UNIT_PET", "player"); W.advance(0.3)
  W.hideOnPlates = true
  local a = t:engage("nameplate1", "A")
  t:set(a, W.player, 2000); t:set(a, pet, 3000, { tank = true })
  W.bind("pettarget", a)
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, true)
  t.eq(t:plate().state, "PET")
end)

test("multi-target: 'Keep the last number' = 0 clears unreadable mobs immediately", function(t)
  local W, TD = t:boot()
  W.hideOnPlates = true
  local a = t:engage("nameplate1", "A", true)
  t:set(a, W.player, 5000, { tank = true })
  TD.db.keepLast = 0
  W.enterCombat(); t:tick()
  t.eq(t:plate().vis, true)
  W.units.target = nil
  W.advance(1.5)
  t.eq(t:plate().vis, false)
end)
