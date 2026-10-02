local test = T.test

test("load: addon loads from its TOC and logs in with no errors", function(t)
  local W, TD = t:boot()
  t.ok(TD, "TD namespace missing")
  t.ok(_G.ThreatDiff == TD, "global ThreatDiff not exported")
  t.ok(TD.db, "profile not loaded")
  t.eq(TD.profileName, "Default")
  t.eq(#W.errors, 0, "errors during load")
end)
