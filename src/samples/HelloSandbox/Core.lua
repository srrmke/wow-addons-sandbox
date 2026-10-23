local addonName, ns = ...

HelloSandboxDB = HelloSandboxDB or { clicks = 0, scale = 1, locked = false }
local db = HelloSandboxDB

---------------------------------------------------------------------------
-- Main window (movable, with the built-in dialog template)
---------------------------------------------------------------------------
local win = CreateFrame("Frame", "HelloSandboxFrame", UIParent, "BasicFrameTemplateWithInset")
win:SetSize(320, 340)
win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetClampedToScreen(true)
win:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
win:SetScale(db.scale)
win.TitleText:SetText("Hello Sandbox")
tinsert(UISpecialFrames, "HelloSandboxFrame")

---------------------------------------------------------------------------
-- Health bar bound to the mock player
---------------------------------------------------------------------------
local bar = CreateFrame("StatusBar", nil, win)
bar:SetSize(280, 18)
bar:SetPoint("TOP", win, "TOP", 0, -40)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
bar:SetMinMaxValues(0, 100)
local barBG = bar:CreateTexture(nil, "BACKGROUND")
barBG:SetAllPoints()
barBG:SetColorTexture(0, 0, 0, 0.6)
local barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
barText:SetPoint("CENTER")

local function UpdateHealth()
  local hp, max = UnitHealth("player"), UnitHealthMax("player")
  bar:SetMinMaxValues(0, max)
  bar:SetValue(hp)
  local pct = hp / max
  bar:SetStatusBarColor(ColorGradient(pct, 1, 0, 0, 1, 1, 0, 0, 1, 0))
  barText:SetText(format("%s / %s  (%d%%)", BreakUpLargeNumbers(hp), BreakUpLargeNumbers(max), pct * 100))
end

---------------------------------------------------------------------------
-- Click counter button
---------------------------------------------------------------------------
local btn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
btn:SetSize(140, 26)
btn:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -72)
local function RefreshButton() btn:SetText("Clicked " .. db.clicks .. "x") end
btn:SetScript("OnClick", function(_, button)
  db.clicks = db.clicks + (button == "RightButton" and -1 or 1)
  RefreshButton()
end)
btn:RegisterForClicks("AnyUp")
btn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Counter", 1, 0.82, 0)
  GameTooltip:AddLine("Left click: +1", 1, 1, 1)
  GameTooltip:AddLine("Right click: -1", 1, 1, 1)
  GameTooltip:AddDoubleLine("Saved clicks", tostring(db.clicks), 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
RefreshButton()

---------------------------------------------------------------------------
-- Checkbox + slider + edit box
---------------------------------------------------------------------------
local lock = CreateFrame("CheckButton", "HelloSandboxLock", win, "UICheckButtonTemplate")
lock:SetPoint("TOPLEFT", btn, "TOPRIGHT", 14, 2)
lock.Text:SetText("Lock window")
lock:SetChecked(db.locked)
lock:SetScript("OnClick", function(self) db.locked = self:GetChecked() end)

local slider = CreateFrame("Slider", "HelloSandboxScale", win, "OptionsSliderTemplate")
slider:SetPoint("TOPLEFT", win, "TOPLEFT", 24, -126)
slider:SetWidth(272)
slider:SetMinMaxValues(0.6, 1.4)
slider:SetValueStep(0.1)
slider:SetValue(db.scale)
slider.Text:SetText("Window scale")
slider.Low:SetText("0.6")
slider.High:SetText("1.4")
slider:SetScript("OnValueChanged", function(_, v)
  db.scale = v
  win:SetScale(v)
end)

local input = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
input:SetSize(272, 22)
input:SetPoint("TOPLEFT", win, "TOPLEFT", 24, -168)
input:SetAutoFocus(false)
input:SetText("type something and press Enter")
input:SetScript("OnEnterPressed", function(self)
  print("|cff71d5ff[Hello]|r you typed:", self:GetText())
  self:ClearFocus()
end)
input:SetScript("OnEscapePressed", input.ClearFocus)

---------------------------------------------------------------------------
-- Rows from the XML template, showing live events
---------------------------------------------------------------------------
local rows = {}
for i, label in ipairs({ "Last event", "Events seen", "Uptime" }) do
  local row = CreateFrame("Frame", nil, win, "HelloRowTemplate")
  row:SetPoint("TOPLEFT", win, "TOPLEFT", 28, -204 - (i - 1) * 26)
  row.Label:SetText(label)
  row.Value:SetText("-")
  rows[label] = row
end

local seen = 0
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UNIT_HEALTH")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 ~= addonName then return end
  seen = seen + 1
  rows["Last event"].Value:SetText(event)
  rows["Events seen"].Value:SetText(seen)
  if event == "UNIT_HEALTH" or event == "ADDON_LOADED" then UpdateHealth() end
end)

local acc = 0
win:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + elapsed
  if acc >= 0.25 then
    acc = 0
    rows["Uptime"].Value:SetText(format("%.1fs", GetTime()))
  end
end)

---------------------------------------------------------------------------
-- A pulsing icon using an animation group
---------------------------------------------------------------------------
local icon = win:CreateTexture(nil, "ARTWORK")
icon:SetSize(36, 36)
icon:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 28, 22)
icon:SetTexture("Interface\\Icons\\Spell_Fire_FlameBolt")
local pulse = icon:CreateAnimationGroup()
pulse:SetLooping("REPEAT")
local fadeOut = pulse:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1) fadeOut:SetToAlpha(0.3) fadeOut:SetDuration(0.8) fadeOut:SetOrder(1)
local fadeIn = pulse:CreateAnimation("Alpha")
fadeIn:SetFromAlpha(0.3) fadeIn:SetToAlpha(1) fadeIn:SetDuration(0.8) fadeIn:SetOrder(2)
pulse:Play()

local label = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("LEFT", icon, "RIGHT", 10, 0)
label:SetText("Type |cff71d5ff/hello|r in the command line")

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_HELLOSANDBOX1 = "/hello"
SlashCmdList.HELLOSANDBOX = function(msg)
  if msg == "reset" then
    db.clicks, db.scale, db.locked = 0, 1, false
    win:SetScale(1)
    slider:SetValue(1)
    lock:SetChecked(false)
    RefreshButton()
    print("Hello Sandbox: settings reset")
  else
    win:SetShown(not win:IsShown())
  end
end

C_Timer.After(1, function() print("|cff71d5ff[Hello]|r loaded - try /hello, /hello reset, drag the window") end)
