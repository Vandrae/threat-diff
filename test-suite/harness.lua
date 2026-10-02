-- Fake World of Warcraft environment (Lua 5.1) used to run the real ThreatDiff
-- files outside the game. It is deliberately STRICT: calling a widget method
-- that the real client does not have raises an error, Lua errors inside event /
-- script / timer callbacks are collected in W.errors, and "secret values" are
-- tables that blow up on comparison or arithmetic (like the modern client).

local H = {}

local unpack = unpack
local function pack(...) return { n = select("#", ...), ... } end

function H.new(opts)
  opts = opts or {}
  local W = {
    now = 1000, chat = {}, errors = {}, frames = {}, timers = {}, nameplates = {},
    units = {}, threat = {}, interface = opts.interface or 16001,
    combat = false, lockdown = false, formID = nil, auras = {}, mods = {},
    cursor = { x = 0, y = 0 }, badFonts = {}, badEvents = opts.badEvents or {},
    hideOnPlates = false, cvars = { nameplateShowEnemies = true },
    memory = 123.4,
  }

  ---------------------------------------------------------------------------
  -- secret values
  ---------------------------------------------------------------------------
  local SECRET = {}
  local function boom() error("attempt to use a secret value", 2) end
  SECRET.__lt, SECRET.__le, SECRET.__add, SECRET.__sub, SECRET.__mul = boom, boom, boom, boom, boom
  SECRET.__div, SECRET.__unm, SECRET.__concat, SECRET.__len = boom, boom, boom, boom
  function W.secret() return setmetatable({}, SECRET) end
  _G.issecretvalue = function(v) return getmetatable(v) == SECRET end
  local issecret = _G.issecretvalue

  ---------------------------------------------------------------------------
  -- error capture
  ---------------------------------------------------------------------------
  local function protected(f, ...)
    local args = pack(...)
    local ok, err = xpcall(function() return f(unpack(args, 1, args.n)) end,
      function(e) return debug.traceback(tostring(e), 2) end)
    if not ok then W.errors[#W.errors + 1] = err end
    return ok, err
  end
  W.protected = protected

  _G.print = function(...)
    local t = pack(...)
    for i = 1, t.n do t[i] = tostring(t[i]) end
    W.chat[#W.chat + 1] = table.concat(t, " ", 1, t.n)
  end
  function W.chatText() return table.concat(W.chat, "\n") end
  function W.clearChat() W.chat = {} end
  function W.chatHas(pat) for _, l in ipairs(W.chat) do if l:find(pat) then return l end end end

  ---------------------------------------------------------------------------
  -- time / timers
  ---------------------------------------------------------------------------
  _G.GetTime = function() return W.now end
  local seq = 0
  local function schedule(delay, fn, ticker)
    seq = seq + 1
    local t = { at = W.now + delay, fn = fn, seq = seq, ticker = ticker }
    W.timers[#W.timers + 1] = t
    return t
  end
  _G.C_Timer = {
    After = function(delay, fn) schedule(delay, fn) end,
    NewTicker = function(interval, fn)
      local tk = { interval = interval, cancelled = false }
      function tk:Cancel() self.cancelled = true end
      function tk:IsCancelled() return self.cancelled end
      tk.t = schedule(interval, fn, tk)
      return tk
    end,
  }
  function W.pendingTimers()
    local n = 0
    for _, t in ipairs(W.timers) do if not (t.ticker and t.ticker.cancelled) then n = n + 1 end end
    return n
  end
  function W.advance(dt)
    local target = W.now + dt
    local guard = 0
    while true do
      local best, bi
      for i, t in ipairs(W.timers) do
        if t.at <= target and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then best, bi = t, i end
      end
      if not best then break end
      guard = guard + 1
      if guard > 20000 then error("timer loop runaway") end
      table.remove(W.timers, bi)
      if not (best.ticker and best.ticker.cancelled) then
        W.now = best.at
        protected(best.fn)
        if best.ticker and not best.ticker.cancelled then
          best.at = W.now + best.ticker.interval
          seq = seq + 1; best.seq = seq
          W.timers[#W.timers + 1] = best
        end
      end
    end
    W.now = target
  end

  ---------------------------------------------------------------------------
  -- widgets
  ---------------------------------------------------------------------------
  local Region, FrameM, TextureM, FontStringM = {}, {}, {}, {}
  local ButtonM, StatusBarM, SliderM, EditBoxM, ScrollM, TooltipM = {}, {}, {}, {}, {}, {}
  local function merge(...)
    local out = {}
    for _, t in ipairs({ ... }) do for k, v in pairs(t) do out[k] = v end end
    return out
  end

  local function fire(o, name, ...)
    local u = o._
    local s = u.scripts[name]
    if s then protected(s, o, ...) end
    local hk = u.hooks[name]
    if hk then for i = 1, #hk do protected(hk[i], o, ...) end end
  end
  W.fireScript = fire

  -- Region -------------------------------------------------------------------
  function Region:GetObjectType() return self._.kind end
  function Region:GetParent() return self._.parent end
  function Region:GetName() return self._.name end
  function Region:Show()
    local u = self._
    if not u.shown then u.shown = true; if u.isFrame then fire(self, "OnShow") end end
  end
  function Region:Hide()
    local u = self._
    if u.shown then u.shown = false; if u.isFrame then fire(self, "OnHide") end end
  end
  function Region:SetShown(b) if b then self:Show() else self:Hide() end end
  function Region:IsShown() return self._.shown end
  function Region:IsVisible()
    local o = self
    while o do
      if not o._.shown then return false end
      o = o._.parent
    end
    return true
  end
  function Region:SetAlpha(a) self._.alpha = a end
  function Region:GetAlpha() return self._.alpha end
  function Region:SetParent(p) self._.parent = p end
  function Region:ClearAllPoints() self._.points = {} end
  local VALID_POINT = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 1, CENTER = 1, RIGHT = 1,
    BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1 }
  local function dependsOn(obj, target, depth)
    if depth > 50 then return false end
    for _, p in ipairs(obj._.points) do
      local r = p.rel
      if r == target then return true end
      if r and r._ and r ~= obj and dependsOn(r, target, depth + 1) then return true end
    end
    return false
  end
  function Region:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if type(a) == "number" then x, y = a, b
    elseif a == nil then
    else
      rel = a
      if type(rel) == "string" then rel = _G[rel] end
      if type(b) == "string" then relPoint = b; x, y = c, d else x, y = b, c end
    end
    if not VALID_POINT[point] then error("Unknown anchor point '" .. tostring(point) .. "'", 2) end
    if relPoint ~= nil and not VALID_POINT[relPoint] then error("Unknown relative anchor point '" .. tostring(relPoint) .. "'", 2) end
    if (x ~= nil and type(x) ~= "number") or (y ~= nil and type(y) ~= "number") then
      error("SetPoint: offsets must be numbers (got " .. type(x) .. ", " .. type(y) .. ")", 2)
    end
    if rel == self then error("Cannot anchor a region to itself", 2) end
    if rel and rel._ and dependsOn(rel, self, 0) then error("Cannot anchor to a region dependent on this region", 2) end
    local pts = self._.points
    pts[#pts + 1] = { point = point, rel = rel or self._.parent, relPoint = relPoint or point, x = x or 0, y = y or 0 }
  end
  function Region:GetPoint(i)
    local p = self._.points[i or 1]
    if p then return p.point, p.rel, p.relPoint, p.x, p.y end
  end
  function Region:GetNumPoints() return #self._.points end
  function Region:SetAllPoints(rel)
    self._.points = { { point = "TOPLEFT", rel = rel or self._.parent, relPoint = "TOPLEFT", x = 0, y = 0, all = true } }
  end
  function Region:SetSize(w, h) self._.w, self._.h = w, h end
  function Region:SetWidth(w) self._.w = w end
  function Region:SetHeight(h) self._.h = h end
  function Region:GetWidth() return self._.w or 0 end
  function Region:GetHeight() return self._.h or 0 end
  function Region:GetSize() return self._.w or 0, self._.h or 0 end
  function Region:GetLeft() return self._.left end
  function Region:GetTop() return self._.top end
  function Region:GetCenter() return self._.cx, self._.cy end
  function Region:GetEffectiveScale() return self._.scale or 1 end
  function Region:SetScale(s) self._.scale = s end
  function Region:GetScale() return self._.scale or 1 end

  -- Texture ------------------------------------------------------------------
  function TextureM:SetTexture(p) self._.texture = p end
  function TextureM:GetTexture() return self._.texture end
  function TextureM:SetColorTexture(r, g, b, a)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then error("SetColorTexture needs numbers", 2) end
    self._.color = { r, g, b, a }; self._.texture = nil
  end
  function TextureM:SetTexCoord(...) self._.coords = { ... } end
  function TextureM:SetVertexColor(r, g, b, a) self._.vcolor = { r, g, b, a } end
  function TextureM:SetRotation(r) self._.rotation = r end
  function TextureM:SetBlendMode(m) self._.blend = m end
  function TextureM:SetDrawLayer(l) self._.layer = l end
  function TextureM:SetGradient(orient, c1, c2)
    if not (type(c1) == "table" and type(c2) == "table") then error("SetGradient needs ColorMixin tables", 2) end
    self._.gradient = { orient, c1, c2 }
  end
  TextureM = merge(Region, TextureM)

  -- FontString ---------------------------------------------------------------
  function FontStringM:SetFont(path, size, flags)
    if type(path) ~= "string" or type(size) ~= "number" then error("SetFont: bad arguments", 2) end
    if W.badFonts[path] then return false end
    self._.font, self._.fontSize, self._.fontFlags = path, size, flags
    return true
  end
  function FontStringM:GetFont() return self._.font, self._.fontSize, self._.fontFlags end
  function FontStringM:SetText(t)
    if not self._.font then error("Font not set", 2) end
    self._.text = (t ~= nil) and tostring(t) or ""
  end
  function FontStringM:GetText() return self._.text end
  function FontStringM:SetTextColor(r, g, b, a) self._.tcolor = { r, g, b, a } end
  function FontStringM:GetTextColor() local c = self._.tcolor or { 1, 1, 1 }; return c[1], c[2], c[3], c[4] or 1 end
  function FontStringM:SetShadowColor(...) self._.shadowColor = { ... } end
  function FontStringM:SetShadowOffset(x, y) self._.shadowOffset = { x, y } end
  function FontStringM:SetJustifyH(j) self._.justifyH = j end
  function FontStringM:SetJustifyV(j) self._.justifyV = j end
  function FontStringM:SetWordWrap(b) self._.wordWrap = b end
  function FontStringM:SetSpacing(s) self._.spacing = s end
  function FontStringM:GetStringWidth() return #(self._.text or "") * 6 end
  FontStringM = merge(Region, FontStringM)

  -- Frame --------------------------------------------------------------------
  function FrameM:SetScript(n, f) self._.scripts[n] = f end
  function FrameM:GetScript(n) return self._.scripts[n] end
  function FrameM:HookScript(n, f)
    local h = self._.hooks
    h[n] = h[n] or {}
    h[n][#h[n] + 1] = f
  end
  function FrameM:HasScript(n) return true end
  function FrameM:RegisterEvent(e)
    if W.badEvents[e] then error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. e .. "\"", 2) end
    self._.events[e] = true
  end
  function FrameM:RegisterUnitEvent(e, ...)
    if W.badEvents[e] then error("Frame:RegisterUnitEvent(): Attempt to register unknown event \"" .. e .. "\"", 2) end
    self._.events[e] = true
    local set = {}
    for _, u in ipairs({ ... }) do set[u] = true end
    self._.unitFilter[e] = set
  end
  function FrameM:UnregisterEvent(e) self._.events[e] = nil; self._.unitFilter[e] = nil end
  function FrameM:UnregisterAllEvents() self._.events = {}; self._.unitFilter = {} end
  function FrameM:IsEventRegistered(e) return self._.events[e] and true or false end
  function FrameM:EnableMouse(b) self._.mouse = b end
  function FrameM:IsMouseEnabled() return self._.mouse and true or false end
  function FrameM:EnableMouseWheel(b) self._.wheel = b end
  function FrameM:SetFrameLevel(l) self._.level = l end
  function FrameM:GetFrameLevel() return self._.level end
  function FrameM:SetFrameStrata(s) self._.strata = s end
  function FrameM:GetFrameStrata() return self._.strata end
  function FrameM:SetMovable(b) self._.movable = b end
  function FrameM:SetClampedToScreen(b) self._.clamped = b end
  function FrameM:SetToplevel(b) self._.toplevel = b end
  function FrameM:SetClipsChildren(b) self._.clips = b end
  function FrameM:RegisterForDrag(...) self._.drag = { ... } end
  function FrameM:StartMoving() self._.moving = true end
  function FrameM:StopMovingOrSizing() self._.moving = false end
  function FrameM:SetHitRectInsets(...) self._.insets = { ... } end
  function FrameM:CreateTexture(name, layer)
    return W.newObject("Texture", name, self, nil, layer)
  end
  function FrameM:CreateFontString(name, layer, inherits)
    local fs = W.newObject("FontString", name, self, nil, layer)
    if inherits then fs._.font, fs._.fontSize = "Fonts\\FRIZQT__.TTF", 12 end
    return fs
  end
  function FrameM:SetBackdrop(b)
    if not self._.backdropTemplate then error("attempt to call method 'SetBackdrop' (a nil value)", 2) end
    self._.backdrop = b
  end
  function FrameM:SetBackdropColor(r, g, b, a)
    if not self._.backdropTemplate then error("attempt to call method 'SetBackdropColor' (a nil value)", 2) end
    self._.bdColor = { r, g, b, a }
  end
  function FrameM:SetBackdropBorderColor(r, g, b, a)
    if not self._.backdropTemplate then error("attempt to call method 'SetBackdropBorderColor' (a nil value)", 2) end
    self._.bdBorder = { r, g, b, a }
  end
  FrameM = merge(Region, FrameM)

  -- Button ---------------------------------------------------------------------
  function ButtonM:Click(btn) fire(self, "OnClick", btn or "LeftButton", false) end
  function ButtonM:RegisterForClicks(...) self._.clicks = { ... } end
  function ButtonM:SetHighlightTexture(path, mode)
    self._.highlight = path
    if not self._.hlTex then self._.hlTex = W.newObject("Texture", nil, self, nil, "HIGHLIGHT") end
  end
  function ButtonM:GetHighlightTexture() return self._.hlTex end
  function ButtonM:SetNormalTexture(p) self._.normal = p end
  function ButtonM:LockHighlight() self._.hlLocked = true end
  function ButtonM:UnlockHighlight() self._.hlLocked = false end
  function ButtonM:Enable() self._.enabled = true end
  function ButtonM:Disable() self._.enabled = false end
  ButtonM = merge(FrameM, ButtonM)

  -- StatusBar ------------------------------------------------------------------
  function StatusBarM:SetMinMaxValues(a, b) self._.min, self._.max = a, b end
  function StatusBarM:GetMinMaxValues() return self._.min, self._.max end
  function StatusBarM:SetValue(v)
    if type(v) ~= "number" then error("StatusBar:SetValue needs a number", 2) end
    self._.value = v
  end
  function StatusBarM:GetValue() return self._.value end
  function StatusBarM:SetStatusBarTexture(p)
    if type(p) ~= "string" then error("SetStatusBarTexture needs a path", 2) end
    self._.sbTexture = p
  end
  function StatusBarM:SetStatusBarColor(r, g, b, a) self._.sbColor = { r, g, b, a } end
  StatusBarM = merge(FrameM, StatusBarM)

  -- Slider ---------------------------------------------------------------------
  function SliderM:SetOrientation(o) self._.orientation = o end
  function SliderM:SetValueStep(s) self._.step = s end
  function SliderM:SetObeyStepOnDrag(b) self._.obey = b end
  function SliderM:SetMinMaxValues(a, b)
    self._.min, self._.max = a, b
    if self._.value then self:SetValue(self._.value) end
  end
  function SliderM:GetMinMaxValues() return self._.min, self._.max end
  function SliderM:SetValue(v)
    local u = self._
    if u.min then
      if v < u.min then v = u.min end
      if v > u.max then v = u.max end
      if u.step and u.step > 0 then v = u.min + math.floor((v - u.min) / u.step + 0.5) * u.step end
    end
    local old = u.value
    u.value = v
    if old ~= v then fire(self, "OnValueChanged", v, false) end
  end
  function SliderM:GetValue() return self._.value or self._.min or 0 end
  function SliderM:SetThumbTexture(p)
    self._.thumb = self._.thumb or W.newObject("Texture", nil, self, nil, "OVERLAY")
    self._.thumb._.texture = p
  end
  function SliderM:GetThumbTexture() return self._.thumb end
  SliderM = merge(FrameM, SliderM)

  -- EditBox --------------------------------------------------------------------
  function EditBoxM:SetAutoFocus(b) self._.autofocus = b end
  function EditBoxM:SetTextInsets(...) self._.textInsets = { ... } end
  function EditBoxM:SetFont(path, size, flags)
    if W.badFonts[path] then return false end
    self._.font, self._.fontSize = path, size
    return true
  end
  function EditBoxM:GetFont() return self._.font, self._.fontSize end
  function EditBoxM:SetTextColor(r, g, b) self._.tcolor = { r, g, b } end
  function EditBoxM:SetJustifyH(j) self._.justifyH = j end
  function EditBoxM:SetText(t)
    if not self._.font then error("Font not set", 2) end
    self._.text = tostring(t or "")
    fire(self, "OnTextChanged", false)
  end
  function EditBoxM:GetText() return self._.text or "" end
  function EditBoxM:HighlightText(a, b) self._.highlight = { a, b } end
  function EditBoxM:SetFocus()
    if not self._.focus then self._.focus = true; fire(self, "OnEditFocusGained") end
  end
  function EditBoxM:ClearFocus()
    if self._.focus then self._.focus = false; fire(self, "OnEditFocusLost") end
  end
  function EditBoxM:HasFocus() return self._.focus and true or false end
  EditBoxM = merge(FrameM, EditBoxM)

  -- ScrollFrame ----------------------------------------------------------------
  function ScrollM:SetScrollChild(c) self._.scrollChild = c end
  function ScrollM:SetVerticalScroll(v) self._.vscroll = v end
  function ScrollM:GetVerticalScroll() return self._.vscroll or 0 end
  ScrollM = merge(FrameM, ScrollM)

  -- GameTooltip ----------------------------------------------------------------
  function TooltipM:SetOwner(o, anchor) self._.owner = o; self._.lines = {} end
  function TooltipM:SetText(t) self._.lines = { t } end
  function TooltipM:AddLine(t) self._.lines[#self._.lines + 1] = t end
  function TooltipM:ClearLines() self._.lines = {} end
  TooltipM = merge(FrameM, TooltipM)

  local METHODS = {
    Frame = FrameM, Button = ButtonM, StatusBar = StatusBarM, Slider = SliderM,
    EditBox = EditBoxM, ScrollFrame = ScrollM, GameTooltip = TooltipM,
    Texture = TextureM, FontString = FontStringM,
  }
  local IS_FRAME = { Frame = true, Button = true, StatusBar = true, Slider = true,
    EditBox = true, ScrollFrame = true, GameTooltip = true }

  function W.newObject(kind, name, parent, template, layer)
    local o = {}
    setmetatable(o, { __index = METHODS[kind] })
    o._ = {
      kind = kind, name = name, parent = parent, shown = true, points = {}, scripts = {}, hooks = {},
      events = {}, unitFilter = {}, alpha = 1, children = {}, regions = {}, isFrame = IS_FRAME[kind],
      level = parent and parent._ and parent._.level and (parent._.level + 1) or 1, layer = layer,
      backdropTemplate = template and tostring(template):find("BackdropTemplate") and true or false,
    }
    if parent and parent._ then
      local list = IS_FRAME[kind] and parent._.children or parent._.regions
      list[#list + 1] = o
    end
    if IS_FRAME[kind] then W.frames[#W.frames + 1] = o end
    if name then _G[name] = o end
    return o
  end

  _G.CreateFrame = function(kind, name, parent, template)
    if not METHODS[kind] or not IS_FRAME[kind] then error("CreateFrame: unknown frame type '" .. tostring(kind) .. "'", 2) end
    if name and _G[name] then error("CreateFrame: frame name '" .. name .. "' already in use", 2) end
    parent = parent or _G.UIParent
    local f = W.newObject(kind, name, parent, template)
    return f
  end

  _G.UIParent = W.newObject("Frame", "UIParent", nil)
  _G.UIParent._.w, _G.UIParent._.h = 1920, 1080
  _G.Minimap = W.newObject("Frame", "Minimap", _G.UIParent)
  _G.Minimap._.w, _G.Minimap._.h, _G.Minimap._.cx, _G.Minimap._.cy = 140, 140, 1700, 900
  _G.GameTooltip = W.newObject("GameTooltip", "GameTooltip", _G.UIParent)
  _G.GameTooltip._.shown = false
  _G.UISpecialFrames = {}
  _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  _G.tinsert, _G.tremove, _G.wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
  _G.format = string.format
  _G.atan2 = math.atan2
  _G.SlashCmdList = {}
  _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
  _G.RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
    MAGE = { r = 0.25, g = 0.78, b = 0.92 }, HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 }, PRIEST = { r = 1, g = 1, b = 1 },
    DRUID = { r = 1, g = 0.49, b = 0.04 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    SHAMAN = { r = 0, g = 0.44, b = 0.87 },
  }
  _G.CLASS_ICON_TCOORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.5, 0, 0.25 }, ROGUE = { 0.5, 0.75, 0, 0.25 },
    DRUID = { 0.75, 1, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.5, 0.25, 0.5 },
    PRIEST = { 0.5, 0.75, 0.25, 0.5 }, WARLOCK = { 0.75, 1, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
  }

  -- Settings / colour picker -------------------------------------------------
  W.settingsCategories = {}
  if not opts.noSettings then
    _G.Settings = {
      RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end,
      RegisterAddOnCategory = function(cat) W.settingsCategories[#W.settingsCategories + 1] = cat end,
    }
  end
  _G.SettingsPanel = W.newObject("Frame", "SettingsPanel", _G.UIParent)
  _G.SettingsPanel._.shown = false
  _G.HideUIPanel = function(f) f:Hide() end
  local picker = W.newObject("Frame", "ColorPickerFrame", _G.UIParent)
  picker._.shown = false
  picker.rgb = { 1, 1, 1 }
  function picker:SetupColorPickerAndShow(info) W.picker = info; self:Show() end
  function picker:GetColorRGB() return unpack(self.rgb) end
  W.pickerFrame = picker

  -- input state ----------------------------------------------------------------
  _G.GetCursorPosition = function() return W.cursor.x, W.cursor.y end
  _G.IsShiftKeyDown = function() return W.mods.shift and true or false end
  _G.IsAltKeyDown = function() return W.mods.alt and true or false end
  _G.IsControlKeyDown = function() return W.mods.ctrl and true or false end

  ---------------------------------------------------------------------------
  -- units, nameplates and threat
  ---------------------------------------------------------------------------
  W.player = { name = "Tester", class = "WARRIOR", guid = "Player-1", role = "NONE", friendly = true }
  W.units.player = W.player
  local function resolve(tok)
    if type(tok) ~= "string" then return nil end
    return W.units[tok]
  end
  W.resolve = resolve

  local mobSeq = 0
  function W.mob(name, extra)
    mobSeq = mobSeq + 1
    local m = { name = name or "Mob", class = "WARRIOR", guid = "Creature-" .. tostring(name) .. "-" .. mobSeq, hostile = true }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
  end
  function W.friend(name, class, extra)
    local m = { name = name, class = class or "WARRIOR", guid = "Player-" .. name, friendly = true, role = "NONE" }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
  end
  function W.bind(tok, obj) W.units[tok] = obj; return obj end

  -- Put a mob on a nameplate and announce it. Returns the plate frame.
  function W.addPlate(tok, obj, noEvent)
    W.units[tok] = obj
    local plate = W.newObject("Frame", nil, _G.UIParent)
    plate._.w, plate._.h = 110, 45
    plate.namePlateUnitToken = tok
    local hb = W.newObject("Frame", nil, plate)
    hb._.w, hb._.h = 100, 10
    plate.UnitFrame = { healthBar = hb }
    plate._.unitObj = obj
    plate._.token = tok
    obj.plate = plate
    W.nameplates[#W.nameplates + 1] = plate
    if not noEvent then W.fire("NAME_PLATE_UNIT_ADDED", tok) end
    return plate
  end
  function W.removePlate(tok)
    local obj = W.units[tok]
    local plate = obj and obj.plate
    W.fire("NAME_PLATE_UNIT_REMOVED", tok)
    for i, p in ipairs(W.nameplates) do if p == plate then table.remove(W.nameplates, i) break end end
    if obj then obj.plate = nil end
    W.units[tok] = nil
  end

  _G.C_NamePlate = {
    GetNamePlateForUnit = function(tok)
      if W.noPlateLookup and W.noPlateLookup[tok] then return nil end
      local obj = resolve(tok)
      if not obj or obj.forbidden then return nil end
      return obj.plate
    end,
    GetNamePlates = function() local l = {}; for i, p in ipairs(W.nameplates) do l[i] = p end; return l end,
    GetNamePlateSize = function() return 140, 40 end,
  }

  _G.UnitExists = function(tok) return resolve(tok) ~= nil end
  _G.UnitIsUnit = function(a, b)
    local x, y = resolve(a), resolve(b)
    return x ~= nil and x == y
  end
  _G.UnitCanAttack = function(a, b)
    local x, y = resolve(a), resolve(b)
    if not x or not y then return false end
    return y.hostile and true or false
  end
  _G.UnitGUID = function(tok) local o = resolve(tok); return o and o.guid or nil end
  _G.UnitName = function(tok) local o = resolve(tok); return o and o.name or nil end
  _G.UnitClass = function(tok)
    local o = resolve(tok)
    if not o then return nil end
    return o.class, o.class, 1
  end
  _G.UnitAffectingCombat = function(tok)
    if tok == "player" then return W.combat end
    local o = resolve(tok); return o and o.inCombat or false
  end
  _G.InCombatLockdown = function() return W.lockdown end
  _G.UnitGroupRolesAssigned = function(tok) local o = resolve(tok); return o and o.role or "NONE" end
  _G.GetPartyAssignment = function(kind, tok) local o = resolve(tok); return o and o.mainTank and kind == "MAINTANK" or false end
  _G.GetShapeshiftFormID = function() return W.formID end
  _G.IsInRaid = function() return W.raid and true or false end
  _G.IsInGroup = function() return (W.raid or W.party) and true or false end
  _G.GetNumGroupMembers = function() return W.groupSize or 0 end
  _G.GetBuildInfo = function() return "1.60.1", "99999", "Jan 1 2026", W.interface end
  _G.GetRealmName = function() return "Testrealm" end
  _G.GetMinimapShape = nil
  _G.C_UnitAuras = { GetPlayerAuraBySpellID = function(id) return W.auras[id] and { spellId = id } or nil end }
  _G.C_CVar = { GetCVarBool = function(n) return W.cvars[n] end }
  _G.C_AddOns = { UpdateAddOnMemoryUsage = function() end, GetAddOnMemoryUsage = function() return W.memory end }

  -- UnitDetailedThreatSituation(unit, mob)
  --   W.threat[mobObj][unitObj] = { tank=bool, status=n, sp=scaled%, rp=raw%, v=value }
  function W.setThreat(mob, unit, e)
    W.threat[mob] = W.threat[mob] or {}
    W.threat[mob][unit] = e
  end
  W.calls = 0
  _G.UnitDetailedThreatSituation = function(unitTok, mobTok)
    W.calls = W.calls + 1
    local u, m = resolve(unitTok), resolve(mobTok)
    if not u or not m then return nil end
    local row = W.threat[m] and W.threat[m][u]
    if not row then return nil end
    local hide = W.hideOnPlates and type(mobTok) == "string" and mobTok:find("^nameplate")
    if hide then
      local S = W.secret
      return S(), S(), S(), S(), S()
    end
    local function val(x) if type(x) == "table" and x.secret then return W.secret() end return x end
    return val(row.tank), val(row.status), val(row.sp), val(row.rp), val(row.v)
  end

  ---------------------------------------------------------------------------
  -- events / combat / groups
  ---------------------------------------------------------------------------
  function W.fire(event, ...)
    local first = ...
    local list = {}
    for _, f in ipairs(W.frames) do list[#list + 1] = f end
    for _, f in ipairs(list) do
      local u = f._
      if u.events[event] then
        local filter = u.unitFilter[event]
        if not filter or filter[first] then fire(f, "OnEvent", event, ...) end
      end
    end
  end
  function W.enterCombat()
    W.combat, W.lockdown = true, true
    W.fire("PLAYER_REGEN_DISABLED")
  end
  function W.leaveCombat()
    W.combat, W.lockdown = false, false
    W.fire("PLAYER_REGEN_ENABLED")
  end

  -- members: { {token="party1", obj=...}, ... }
  function W.setParty(members, pets)
    W.party, W.raid = true, false
    W.groupSize = #members + 1
    for _, m in ipairs(members) do W.units[m.token] = m.obj end
    W.fire("GROUP_ROSTER_UPDATE")
    W.advance(0.3)
  end
  function W.setRaid(members)
    W.party, W.raid = false, true
    W.groupSize = #members
    for i, m in ipairs(members) do W.units["raid" .. i] = (m == "player") and W.player or m end
    W.fire("GROUP_ROSTER_UPDATE")
    W.advance(0.3)
  end
  function W.setSolo()
    W.party, W.raid, W.groupSize = false, false, 0
  end

  ---------------------------------------------------------------------------
  -- widget lookup helpers for UI tests
  ---------------------------------------------------------------------------
  function W.eachObject(fn)
    local function walk(o)
      if fn(o) then return o end
      for _, c in ipairs(o._.children) do local r = walk(c); if r then return r end end
      for _, c in ipairs(o._.regions) do local r = fn(c) and c; if r then return r end end
    end
    return walk(_G.UIParent)
  end
  function W.findText(pat, root)
    local found = {}
    local function walk(o)
      for _, r in ipairs(o._.regions) do
        if r._.kind == "FontString" and r._.text and r._.text:find(pat) then found[#found + 1] = r end
      end
      for _, c in ipairs(o._.children) do walk(c) end
    end
    walk(root or _G.UIParent)
    return found
  end
  -- The row frame whose label text equals `label` (nth match, default 1).
  function W.row(label, nth, root)
    local n = 0
    for _, fs in ipairs(W.findText("^" .. label:gsub("%p", "%%%0") .. "$", root)) do
      if fs._.parent and fs._.parent.Control then
        n = n + 1
        if n == (nth or 1) then return fs._.parent end
      end
    end
  end
  function W.control(label, nth, root)
    local row = W.row(label, nth, root)
    if not row then return nil end
    return row._.children[1], row._.children[2], row
  end
  function W.buttonByText(text, root)
    local hit
    local function walk(o)
      if hit then return end
      if o._.kind == "Button" and o.label and o.label._ and o.label._.text == text then hit = o return end
      for _, c in ipairs(o._.children) do walk(c) end
    end
    walk(root or _G.UIParent)
    return hit
  end

  W.G = _G
  return W
end

-- Load the real addon from its TOC (so a bad TOC entry is a test failure).
function H.load_addon(W, dir, savedVars)
  local toc = assert(io.open(dir .. "/ThreatDiff.toc", "r"))
  local files, meta = {}, {}
  for line in toc:lines() do
    line = line:gsub("\r", "")
    local k, v = line:match("^##%s*([%w%-]+):%s*(.-)%s*$")
    if k then meta[k] = v
    elseif line ~= "" and not line:find("^#") then files[#files + 1] = line end
  end
  toc:close()
  W.toc, W.tocFiles = meta, files
  local ns = {}
  W.ns = ns
  for _, f in ipairs(files) do
    local fh = assert(io.open(dir .. "/" .. f, "rb"), "TOC lists a missing file: " .. f)
    local src = fh:read("*a"); fh:close()
    local chunk, err = loadstring(src, "@" .. f)
    if not chunk then error("syntax error in " .. f .. ": " .. tostring(err), 0) end
    chunk("ThreatDiff", ns)
  end
  if savedVars ~= nil then _G.ThreatDiffDB = savedVars end
  return ns
end

function H.login(W)
  W.fire("ADDON_LOADED", "ThreatDiff")
  W.fire("PLAYER_ENTERING_WORLD")
  W.advance(0.3)
  return W.ns.TD
end

return H
