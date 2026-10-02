-- Tiny test framework. Every test gets a brand-new fake WoW (fresh Lua state)
-- and calls t.boot{...} to load the real addon from its TOC.

local H = dofile(ROOT .. "/harness.lua")

T = { tests = {}, order = {} }

function T.test(name, fn, meta)
  assert(not T.tests[name], "duplicate test name: " .. name)
  T.tests[name] = { fn = fn, meta = meta or {} }
  T.order[#T.order + 1] = name
end

function T.names() return T.order end

-- tests whose meta.bug is set document a CONFIRMED defect in the addon
-- (the python runner treats them as strict expected-failures)
function T.bugOf(name) return T.tests[name].meta.bug end

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

local ctx = {}
ctx.__index = ctx

function ctx:boot(o)
  o = o or {}
  local W = H.new(o)
  H.load_addon(W, ADDON_DIR, o.saved)
  if not o.noLogin then H.login(W) end
  self.W, self.TD = W, W.ns.TD
  return W, W.ns.TD
end

-- second half of boot{noLogin=true}: lets a test tweak the fake world first
function ctx:login()
  H.login(self.W)
  return self.W, self.TD
end

function ctx.ok(v, msg) if not v then error(msg or "expected a truthy value", 2) end end
function ctx.eq(a, b, msg)
  if a ~= b then error((msg and (msg .. ": ") or "") .. "expected " .. fmt(b) .. " but got " .. fmt(a), 2) end
end
function ctx.near(a, b, eps, msg)
  if type(a) ~= "number" or math.abs(a - b) > (eps or 1e-6) then
    error((msg and (msg .. ": ") or "") .. "expected ~" .. fmt(b) .. " but got " .. fmt(a), 2)
  end
end
function ctx.has(s, pat, msg)
  if type(s) ~= "string" or not s:find(pat) then
    error((msg and (msg .. ": ") or "") .. "expected " .. fmt(s) .. " to match pattern " .. fmt(pat), 2)
  end
end
function ctx.hasnt(s, pat, msg)
  if type(s) == "string" and s:find(pat) then
    error((msg and (msg .. ": ") or "") .. "expected " .. fmt(s) .. " NOT to match " .. fmt(pat), 2)
  end
end
function ctx.noerr(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then error("unexpected error: " .. tostring(err), 2) end
  return err
end
function ctx.throws(fn, ...)
  local ok = pcall(fn, ...)
  if ok then error("expected an error but none was raised", 2) end
end
-- tolerate collected callback errors in this test
function ctx:allowErrors() self.errorsAllowed = true end

-------------------------------------------------------------------------------
-- scenario helpers
-------------------------------------------------------------------------------
-- t:party{ {name=, class=, role=, mainTank=}, ... } -> list of friend objects (party1..n)
function ctx:party(spec)
  local W = self.W
  local members, out = {}, {}
  for i, s in ipairs(spec) do
    local f = W.friend(s.name or ("Friend" .. i), s.class, { role = s.role or "NONE", mainTank = s.mainTank })
    out[i] = f
    members[i] = { token = "party" .. i, obj = f }
  end
  W.setParty(members)
  return out
end

-- t:raid(n) -> n-1 other raid members (raid1 is the player)
function ctx:raid(n, roles)
  local W = self.W
  local list, out = { "player" }, {}
  for i = 2, n do
    local f = W.friend("Raider" .. i, "MAGE", { role = (roles and roles[i]) or "NONE" })
    list[i] = f; out[#out + 1] = f
  end
  W.setRaid(list)
  return out
end

-- a hostile mob on a nameplate (optionally also bound to "target")
function ctx:engage(tok, name, asTarget)
  local W = self.W
  local mob = W.mob(name or tok)
  W.addPlate(tok, mob)
  if asTarget then W.bind("target", mob) end
  return mob
end

function ctx:set(mob, unit, v, o)
  o = o or {}
  self.W.setThreat(mob, unit, {
    v = v, tank = o.tank or false, status = o.status or (o.tank and 3 or 0),
    sp = o.sp, rp = o.rp,
  })
end

-- fire a threat event on the plate and let the throttled flush run
function ctx:tick(tok)
  self.W.fire("UNIT_THREAT_LIST_UPDATE", tok or "nameplate1")
  self.W.advance(0.25)
end

-- what is on screen for a plate token
function ctx:plate(tok)
  local TD = self.TD
  local h = TD.active[tok or "nameplate1"]
  if not h then return { active = false, vis = false } end
  local r, g, b = h.fs:GetTextColor()
  return {
    active = true, vis = h.vis and true or false, text = h.fs:GetText(),
    state = h.st and TD.STATES[h.st].key or nil, color = { r, g, b },
    alpha = h._.alpha, dim = h.dim and true or false, holder = h,
  }
end

function T.run(name)
  local t = setmetatable({}, ctx)
  local entry = T.tests[name]
  local ok, err = xpcall(function() entry.fn(t) end, function(e) return debug.traceback(tostring(e), 2) end)
  local out = { ok = ok, message = ok and "" or tostring(err), errors = "", chat = "" }
  if t.W then
    out.chat = t.W.chatText()
    if ok and #t.W.errors > 0 and not t.errorsAllowed then
      out.ok = false
      out.message = "Lua error inside an event/script/timer callback:\n" .. table.concat(t.W.errors, "\n---\n")
    end
    if ok and not t.errorsAllowed then
      local bad = t.W.chatHas("error:")
      if bad then out.ok = false; out.message = "addon printed an internal error report in chat: " .. bad end
    end
  end
  return out
end

for _, f in ipairs(TEST_FILES) do dofile(f) end
