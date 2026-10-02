local test = T.test

local function openEditor(t)
  local W, TD = t:boot()
  TD:ToggleEditor(true)
  return W, TD, _G.ThreatDiffEditor
end

local function btn(W, text) return W.buttonByText(text, _G.ThreatDiffEditor) end

local function readout(ed)
  for _, r in ipairs(ed._.regions) do
    if r._.text and r._.text:find("^x ") then return r._.text end
  end
end

local function area(ed)
  for _, c in ipairs(ed._.children) do if c._.clips then return c end end
end

local function mockPlate(ed) return area(ed)._.children[1]._.children[1] end

test("editor: opens, shows the exact position and the anchor description", function(t)
  local W, TD, ed = openEditor(t)
  t.ok(ed:IsShown())
  t.eq(readout(ed), "x -6.00, y 0.00")
  t.ok(#W.findText("text RIGHT  %->  nameplate LEFT", ed) == 1)
  t.eq(btn(W, "Step 1") ~= nil, true)
  t.eq(btn(W, "Zoom 2x") ~= nil, true)
  t.eq(btn(W, "Test on plates") ~= nil, true)
end)

test("editor: toggling closes it and Escape is wired", function(t)
  local W, TD, ed = openEditor(t)
  TD:ToggleEditor()
  t.eq(ed:IsShown(), false)
  TD:ToggleEditor(true)
  t.eq(ed:IsShown(), true)
  local seen = false
  for _, n in ipairs(UISpecialFrames) do if n == "ThreatDiffEditor" then seen = true end end
  t.ok(seen)
end)

test("editor: arrow buttons nudge by the step; Step button cycles 1 / 0.1 / 0.01", function(t)
  local W, TD, ed = openEditor(t)
  TD:SetPosition(0, 0)
  btn(W, ">"):Click("LeftButton"); t.eq(TD.db.x, 1)
  btn(W, "<"):Click("LeftButton"); btn(W, "<"):Click("LeftButton"); t.eq(TD.db.x, -1)
  btn(W, "^"):Click("LeftButton"); t.eq(TD.db.y, 1)
  btn(W, "v"):Click("LeftButton"); btn(W, "v"):Click("LeftButton"); t.eq(TD.db.y, -1)
  btn(W, "Step 1"):Click("LeftButton")
  t.ok(btn(W, "Step 0.1"))
  btn(W, ">"):Click("LeftButton"); t.eq(TD.db.x, -0.9)
  btn(W, "Step 0.1"):Click("LeftButton")
  t.ok(btn(W, "Step 0.01"))
  btn(W, ">"):Click("LeftButton"); t.eq(TD.db.x, -0.89)
  btn(W, "Step 0.01"):Click("LeftButton")
  t.ok(btn(W, "Step 1"))
  W.mods.shift = true
  btn(W, ">"):Click("LeftButton"); t.eq(TD.db.x, -0.79, "shift = step / 10")
  W.mods.shift, W.mods.ctrl = false, true
  btn(W, ">"):Click("LeftButton"); t.eq(TD.db.x, -0.78, "ctrl = step / 100")
  t.eq(readout(ed), "x -0.78, y -1.00")
end)

test("editor: Zero button and live readout follow every change", function(t)
  local W, TD, ed = openEditor(t)
  TD:SetPosition(12.34, -5.67)
  t.eq(readout(ed), "x 12.34, y -5.67")
  btn(W, "Zero (0, 0)"):Click("LeftButton")
  t.eq(TD.db.x, 0); t.eq(TD.db.y, 0)
  t.eq(readout(ed), "x 0.00, y 0.00")
  SlashCmdList.THREATDIFF("pos 1 2")
  t.eq(readout(ed), "x 1.00, y 2.00")
end)

test("editor: Zoom button cycles 1x-4x and scales the mock", function(t)
  local W, TD, ed = openEditor(t)
  local zoomBox = area(ed)._.children[1]
  t.eq(zoomBox:GetScale(), 2)
  btn(W, "Zoom 2x"):Click("LeftButton"); t.eq(zoomBox:GetScale(), 3); t.ok(btn(W, "Zoom 3x"))
  btn(W, "Zoom 3x"):Click("LeftButton"); t.eq(zoomBox:GetScale(), 4)
  btn(W, "Zoom 4x"):Click("LeftButton"); t.eq(zoomBox:GetScale(), 1)
  btn(W, "Zoom 1x"):Click("LeftButton"); t.eq(zoomBox:GetScale(), 2)
end)

test("editor: dragging moves the number 1:1 (Shift = 10x finer) and lands on 0.01", function(t)
  local W, TD, ed = openEditor(t)
  btn(W, "Zoom 2x"):Click("LeftButton"); btn(W, "Zoom 3x"):Click("LeftButton"); btn(W, "Zoom 4x"):Click("LeftButton")
  -- zoom is now 1x
  TD:SetPosition(0, 0)
  local a = area(ed)
  W.cursor = { x = 500, y = 500 }
  W.fireScript(a, "OnMouseDown", "LeftButton")
  t.ok(a._.scripts.OnUpdate, "tracks the mouse while dragging")
  W.cursor = { x = 520, y = 510 }
  W.fireScript(a, "OnUpdate", 0.01)
  t.eq(TD.db.x, 20); t.eq(TD.db.y, 10)
  W.mods.shift = true
  W.cursor = { x = 530, y = 500 }
  W.fireScript(a, "OnUpdate", 0.01)
  t.near(TD.db.x, 21, 1e-9); t.near(TD.db.y, 9, 1e-9, "shift moved 10x less")
  W.mods.shift = false
  W.fireScript(a, "OnMouseUp", "LeftButton")
  t.eq(a._.scripts.OnUpdate, nil)
end)

test("editor: mouse wheel changes Y, Alt+wheel changes X", function(t)
  local W, TD, ed = openEditor(t)
  TD:SetPosition(0, 0)
  local a = area(ed)
  W.fireScript(a, "OnMouseWheel", 1); t.eq(TD.db.y, 1)
  W.fireScript(a, "OnMouseWheel", -1); W.fireScript(a, "OnMouseWheel", -1); t.eq(TD.db.y, -1)
  W.mods.alt = true
  W.fireScript(a, "OnMouseWheel", 1); t.eq(TD.db.x, 1)
end)

test("editor: right-click cycles the sample number and colour", function(t)
  local W, TD, ed = openEditor(t)
  local sample
  local plate = mockPlate(ed)
  for _, r in ipairs(plate._.regions) do if r._.kind == "FontString" then sample = r end end
  t.eq(sample._.text, "+4.2k")
  local a = area(ed)
  local seen = { sample._.text }
  for i = 1, 5 do W.fireScript(a, "OnMouseDown", "RightButton"); seen[#seen + 1] = sample._.text end
  t.eq(table.concat(seen, " "), "+4.2k +812 !!! -2.4k -212 -3.1k")
  W.fireScript(a, "OnMouseDown", "RightButton")
  t.eq(sample._.text, "+4.2k", "wraps around")
end)

test("editor: 'Test on plates' button toggles preview and relabels", function(t)
  local W, TD, ed = openEditor(t)
  local mob = W.mob("Boar"); W.addPlate("nameplate1", mob)
  btn(W, "Test on plates"):Click("LeftButton")
  t.eq(TD.testMode, true); t.ok(btn(W, "Stop test"))
  t.eq(TD.active.nameplate1.vis, true)
  btn(W, "Stop test"):Click("LeftButton")
  t.eq(TD.testMode, false); t.ok(btn(W, "Test on plates"))
end)

test("editor: 'Re-measure plate' copies a real nameplate's size", function(t)
  local W, TD, ed = openEditor(t)
  local mob = W.mob("Boar"); local plate = W.addPlate("nameplate1", mob)
  plate._.w, plate._.h = 150, 60
  plate.UnitFrame.healthBar._.w, plate.UnitFrame.healthBar._.h = 140, 12
  btn(W, "Re-measure plate"):Click("LeftButton")
  local mp = mockPlate(ed)
  t.eq(mp:GetWidth(), 150); t.eq(mp:GetHeight(), 60)
end)

test("editor: health-bar anchoring shows in the description and moves the sample", function(t)
  local W, TD, ed = openEditor(t)
  TD.db.anchorTo = "HEALTH"; TD:ApplySettings()
  t.ok(#W.findText("health bar", ed) >= 1)
end)

test("editor: survives secret/odd plate geometry and no plates at all", function(t)
  local W, TD, ed = openEditor(t)
  TD:ToggleEditor(false)
  local mob = W.mob("Odd"); local plate = W.addPlate("nameplate1", mob)
  plate._.w, plate._.h = W.secret(), W.secret()
  t.noerr(function() TD:ToggleEditor(true) end)
end)
