local test = T.test

-- Pure formatting / rounding helpers --------------------------------------------

test("format: Round2 rounds half away from zero and survives float error", function(t)
  local _, TD = t:boot()
  t.eq(TD.Round2(1.005), 1.01)
  t.eq(TD.Round2(-1.005), -1.01)
  t.eq(TD.Round2(2.345), 2.35)
  t.eq(TD.Round2(10.255), 10.26)
  t.eq(TD.Round2(0.004), 0)
  t.eq(TD.Round2(-0.004), 0)
  t.eq(1 / TD.Round2(-0.004) > 0, true, "must not return negative zero")
  t.eq(TD.Round2(-6), -6)
end)

test("format: Fmt2 always prints two decimals", function(t)
  local _, TD = t:boot()
  t.eq(TD.Fmt2(2.3), "2.30")
  t.eq(TD.Fmt2(-6), "-6.00")
  t.eq(TD.Fmt2(10.255), "10.26")
  t.eq(TD.Fmt2(0), "0.00")
end)

test("format: abbreviated numbers (default 1 decimal)", function(t)
  local _, TD = t:boot()
  local F = TD.FormatAbs
  t.eq(F(0), "0")
  t.eq(F(812), "812")
  t.eq(F(999.4), "999")
  t.eq(F(999.5), "1.0k")
  t.eq(F(1234), "1.2k")
  t.eq(F(4210), "4.2k")
  t.eq(F(999499), "999.5k")
  t.eq(F(999500), "1.00m")
  t.eq(F(1500000), "1.50m")
end)

test("format: decimals setting changes k/m precision", function(t)
  local _, TD = t:boot()
  TD.db.decimals = 0; TD:ApplySettings()
  t.eq(TD.FormatAbs(1234), "1k")
  t.eq(TD.FormatAbs(1500000), "1.5m")
  TD.db.decimals = 2; TD:ApplySettings()
  t.eq(TD.FormatAbs(1234), "1.23k")
  t.eq(TD.FormatAbs(1500000), "1.50m")
end)

test("format: abbreviate=false prints whole numbers", function(t)
  local _, TD = t:boot()
  TD.db.abbreviate = false; TD:ApplySettings()
  t.eq(TD.FormatAbs(1234567), "1234567")
  t.eq(TD.FormatAbs(812.4), "812")
end)

test("format: BuildText signs, tie marker and switches", function(t)
  local _, TD = t:boot()
  t.eq(TD.BuildText(4210, 4210), "+4.2k")
  t.eq(TD.BuildText(-154, -154), "-154")
  t.eq(TD.BuildText(0, 0), "!!!")
  t.eq(TD.BuildText(0.3, 0), "!!!")
  TD.db.bangOnTie = false
  t.eq(TD.BuildText(0, 0), "0")
  TD.db.bangOnTie = true
  TD.db.showPlus = false
  t.eq(TD.BuildText(812, 812), "812")
  TD.db.showMinus = false
  t.eq(TD.BuildText(-812, -812), "812")
end)
