--[[ ThreatDiff - minimap button.

  Left-click: settings.  Right-click: show / hide the threat meter.
  Shift-click: preview.  Drag: move it around the minimap.
  Hide it from the settings (Home page) or with /tdiff minimap.
  Its position and on/off state are account-wide.
]]

local _, ns = ...
local TD = ns.TD

local ICON = "Interface\\Icons\\Ability_Warrior_DefensiveStance"
local btn
local rad, cos, sin, sqrt, deg = math.rad, math.cos, math.sin, math.sqrt, math.deg
local atan2 = math.atan2 or _G.atan2
local max, min = math.max, math.min

local function Opts() return TD:GetAccountSettings().minimap end

-- Sits on the minimap's edge; square minimaps (some UI addons) are handled too.
local function Place()
  local a = rad(Opts().angle or 200)
  local x, y = cos(a), sin(a)
  local w = Minimap:GetWidth() / 2 + 5
  local h = Minimap:GetHeight() / 2 + 5
  local shape = _G.GetMinimapShape and _G.GetMinimapShape() or "ROUND"
  if shape == "ROUND" then
    x, y = x * w, y * h
  else
    x = max(-w, min(w, x * w * sqrt(2)))
    y = max(-h, min(h, y * h * sqrt(2)))
  end
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function DragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  Opts().angle = deg(atan2(cy / s - my, cx / s - mx)) % 360
  Place()
end

local function Build()
  btn = CreateFrame("Button", "ThreatDiffMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
  icon:SetPoint("TOPLEFT", 7, -6)
  btn.icon = icon
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")

  btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      local m = TD.db.meter
      m.enabled = not m.enabled
      TD:ApplySettings()
      TD.Print(m.enabled and "threat meter shown." or "threat meter hidden.")
    elseif IsShiftKeyDown() then
      TD:SetTestMode(not TD.testMode)
    else
      TD:ToggleConfig()
    end
  end)
  btn:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", DragUpdate)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
  end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("ThreatDiff", 0.31, 0.76, 0.97)
    GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
    GameTooltip:AddLine("Right-click: show / hide the threat meter", 1, 1, 1)
    GameTooltip:AddLine("Shift-click: preview numbers", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function TD.MinimapShown() return not Opts().hide end

function TD.MinimapApply()
  if not Minimap then return end
  if Opts().hide then
    if btn then btn:Hide() end
    return
  end
  if not btn then Build() end
  Place()
  btn:Show()
end

function TD.SetMinimapShown(show)
  Opts().hide = not show
  TD.MinimapApply()
end

-- Runs once saved settings are loaded (after the settings entry is registered).
local prevLoaded = TD.OnLoaded
TD.OnLoaded = function()
  if prevLoaded then prevLoaded() end
  local ok, err = pcall(TD.MinimapApply)
  if not ok then TD.ReportError("minimap button", err) end
end
