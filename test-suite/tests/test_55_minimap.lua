local test = T.test

test("minimap: button exists, sits on the minimap edge at the saved angle", function(t)
  local W, TD = t:boot()
  local b = _G.ThreatDiffMinimapButton
  t.ok(b and b:IsShown())
  local p = b._.points[1]
  t.eq(p.point, "CENTER"); t.eq(p.rel, Minimap)
  t.near(p.x, math.cos(math.rad(200)) * 75, 0.01)
  t.near(p.y, math.sin(math.rad(200)) * 75, 0.01)
end)

test("minimap: left click opens settings, right click toggles the meter, shift-click previews", function(t)
  local W, TD = t:boot()
  local b = _G.ThreatDiffMinimapButton
  b:Click("LeftButton")
  t.ok(_G.ThreatDiffConfig:IsShown())
  b:Click("LeftButton")
  t.eq(_G.ThreatDiffConfig:IsShown(), false)
  W.clearChat()
  b:Click("RightButton")
  t.eq(TD.db.meter.enabled, false); t.has(W.chatText(), "meter hidden")
  b:Click("RightButton")
  t.eq(TD.db.meter.enabled, true); t.has(W.chatText(), "meter shown")
  t.eq(_G.ThreatDiffMeter:IsShown(), true)
  W.mods.shift = true
  b:Click("LeftButton")
  t.eq(TD.testMode, true)
  b:Click("LeftButton")
  t.eq(TD.testMode, false)
  t.eq(_G.ThreatDiffConfig:IsShown(), false, "shift-click must not open settings")
end)

test("minimap: dragging moves it around the minimap and keeps the angle", function(t)
  local W, TD = t:boot()
  local b = _G.ThreatDiffMinimapButton
  W.fireScript(b, "OnDragStart")
  t.ok(b._.hlLocked)
  W.cursor = { x = 1700, y = 1000 }     -- straight above the minimap centre (1700, 900)
  W.fireScript(b, "OnUpdate", 0.01)
  t.near(TD:GetAccountSettings().minimap.angle, 90, 0.01)
  t.near(b._.points[1].y, 75, 0.01)
  t.near(b._.points[1].x, 0, 0.01)
  W.fireScript(b, "OnDragStop")
  t.eq(b._.scripts.OnUpdate, nil)
  t.eq(b._.hlLocked, false)
end)

test("minimap: square minimaps keep the button on the square's edge", function(t)
  local W, TD = t:boot({ noLogin = true })
  _G.GetMinimapShape = function() return "SQUARE" end
  t:login()
  local b = _G.ThreatDiffMinimapButton
  local p = b._.points[1]
  t.ok(math.abs(p.x) <= 75.001 and math.abs(p.y) <= 75.001)
  t.near(math.max(math.abs(p.x), math.abs(p.y)), 75, 0.01)
end)

test("minimap: hidden setting persists and applies to every character/profile", function(t)
  local W, TD = t:boot({ saved = { profiles = { Default = {} }, chars = {}, minimap = { hide = true, angle = 10 } } })
  t.eq(_G.ThreatDiffMinimapButton, nil, "no button when hidden")
  TD.SetMinimapShown(true)
  t.ok(_G.ThreatDiffMinimapButton:IsShown())
  TD:NewProfile("Other")
  TD.SetMinimapShown(false)
  TD:SetProfile("Default")
  t.eq(_G.ThreatDiffMinimapButton:IsShown(), false, "account-wide, not per profile")
  t.eq(_G.ThreatDiffDB.minimap.hide, true)
end)

test("minimap: tooltip lists the click actions", function(t)
  local W, TD = t:boot()
  local b = _G.ThreatDiffMinimapButton
  W.fireScript(b, "OnEnter")
  local lines = GameTooltip._.lines
  t.eq(lines[1], "ThreatDiff")
  t.eq(#lines, 5)
  t.has(lines[2], "Left%-click")
  t.has(lines[3], "Right%-click")
  t.has(lines[4], "Shift")
  W.fireScript(b, "OnLeave")
end)

test("minimap: addon works when the Minimap frame is missing", function(t)
  local W, TD = t:boot({ noLogin = true })
  _G.Minimap = nil
  t:login()
  t.eq(_G.ThreatDiffMinimapButton, nil)
  t.eq(#W.errors, 0)
end)
