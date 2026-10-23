-- Game-world mock API: units, addon registry, slash commands, SavedVariables, popups, misc helpers.

---------------------------------------------------------------------------
-- Mock game state (edited from the sandbox UI)
---------------------------------------------------------------------------
__mock = {
  combat = false,
  mods = { shift = false, ctrl = false, alt = false },
  units = {
    player = { name = "Sandbox", class = "MAGE", classLoc = "Mage", race = "Human", level = 80, hp = 85000, hpMax = 100000,
      power = 40000, powerMax = 50000, powerType = 0, powerToken = "MANA", sex = 2, faction = "Alliance", isPlayer = true, guid = "Player-1-00000001" },
    target = { name = "Training Dummy", class = "WARRIOR", classLoc = "Warrior", race = "Human", level = 82, hp = 1000000, hpMax = 1000000,
      power = 0, powerMax = 100, powerType = 1, powerToken = "RAGE", sex = 2, faction = "Horde", isPlayer = false, hostile = true, guid = "Creature-0-1-1-1-1-00000001" },
  },
}

function __SetMock(json)
  local patch = __unjson(json)
  for unit, vals in pairs(patch.units or {}) do
    if vals == false then __mock.units[unit] = nil
    else
      __mock.units[unit] = __mock.units[unit] or {}
      for k, v in pairs(vals) do __mock.units[unit][k] = v end
    end
  end
  if patch.combat ~= nil then __mock.combat = patch.combat end
  if patch.mods then for k, v in pairs(patch.mods) do __mock.mods[k] = v end end
end
function __GetMock() return __json(__mock) end

local function U(unit)
  if unit == "mouseover" then return nil end
  if unit == "targettarget" then unit = "player" end
  return __mock.units[unit]
end

function UnitExists(u) return U(u) ~= nil end
function UnitName(u) local x = U(u) return x and x.name, nil end
function UnitFullName(u) local x = U(u) return x and x.name, "Sandbox" end
function GetUnitName(u) local x = U(u) return x and x.name end
function UnitClass(u) local x = U(u) if x then return x.classLoc, x.class, 1 end end
function UnitClassBase(u) local x = U(u) if x then return x.class end end
function UnitRace(u) local x = U(u) if x then return x.race, x.race end end
function UnitLevel(u) local x = U(u) return x and x.level or 0 end
function UnitEffectiveLevel(u) return UnitLevel(u) end
function UnitHealth(u) local x = U(u) return x and x.hp or 0 end
function UnitHealthMax(u) local x = U(u) return x and x.hpMax or 0 end
function UnitPower(u) local x = U(u) return x and x.power or 0 end
function UnitPowerMax(u) local x = U(u) return x and x.powerMax or 0 end
function UnitPowerType(u) local x = U(u) if x then return x.powerType, x.powerToken end return 0, "MANA" end
function UnitIsDead(u) local x = U(u) return x and x.hp <= 0 or false end
function UnitIsDeadOrGhost(u) return UnitIsDead(u) end
function UnitIsGhost() return false end
function UnitIsPlayer(u) local x = U(u) return x and x.isPlayer or false end
function UnitIsUnit(a, b) return a == b or (U(a) ~= nil and U(a) == U(b)) end
function UnitIsEnemy(a, b) local x = U(b) return x and x.hostile or false end
function UnitIsFriend(a, b) local x = U(b) return x and not x.hostile or false end
function UnitCanAttack(a, b) local x = U(b) return x and x.hostile or false end
function UnitIsConnected() return true end
function UnitIsAFK() return false end
function UnitIsDND() return false end
function UnitIsVisible(u) return U(u) ~= nil end
function UnitInRange() return true end
function UnitAffectingCombat() return __mock.combat end
function UnitGUID(u) local x = U(u) return x and x.guid end
function UnitSex(u) local x = U(u) return x and x.sex or 1 end
function UnitFactionGroup(u) local x = U(u) return x and x.faction, x and x.faction end
function UnitReaction(a, b) local x = U(b) return x and (x.hostile and 2 or 5) or nil end
function UnitIsGroupLeader() return false end
function UnitInParty() return false end
function UnitInRaid() return nil end
function UnitPlayerControlled(u) return UnitIsPlayer(u) end
function UnitCreatureType() return "Humanoid" end
function UnitClassification() return "normal" end
function UnitThreatSituation() return nil end
function UnitGetTotalAbsorbs() return 0 end
function UnitGetIncomingHeals() return 0 end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function UnitBuff() return nil end
function UnitDebuff() return nil end
function UnitAura() return nil end
function GetNumSubgroupMembers() return 0 end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 62, "Arcane", "", 135932, "DAMAGER" end

function IsShiftKeyDown() return __mock.mods.shift end
function IsControlKeyDown() return __mock.mods.ctrl end
function IsAltKeyDown() return __mock.mods.alt end
function IsModifierKeyDown() return __mock.mods.shift or __mock.mods.ctrl or __mock.mods.alt end
function IsModifiedClick() return false end
function IsLeftShiftKeyDown() return __mock.mods.shift end
function IsRightShiftKeyDown() return false end
function IsMouseButtonDown() return false end
function GetMouseButtonClicked() return "LeftButton" end

local spells = {
  [133] = { "Fireball", 135812 }, [116] = { "Frostbolt", 135846 }, [1459] = { "Arcane Intellect", 135932 },
  [2139] = { "Counterspell", 135856 }, [45438] = { "Ice Block", 135841 }, [1953] = { "Blink", 135736 },
}
function GetSpellInfo(id)
  local s = spells[id]
  if s then return s[1], nil, s[2], 0, 0, 40, id, s[2] end
  return "Spell " .. tostring(id), nil, 134400, 0, 0, 40, id, 134400
end
function GetSpellTexture(id) local s = spells[id] return s and s[2] or 134400 end
function GetSpellLink(id) return "|cff71d5ff|Hspell:" .. id .. "|h[" .. (GetSpellInfo(id)) .. "]|h|r" end
function IsSpellKnown() return true end
function GetSpellCooldown() return 0, 0, 1 end
function GetItemInfo() return nil end
function GetItemInfoInstant() return nil end
function GetItemCount() return 0 end
function GetItemIcon() return 134400 end
C_Spell = { GetSpellInfo = function(id) local n, _, ic = GetSpellInfo(id) return { name = n, iconID = ic, spellID = id } end,
  GetSpellTexture = GetSpellTexture, GetSpellName = function(id) return (GetSpellInfo(id)) end }
C_Item = { GetItemInfo = GetItemInfo, GetItemCount = GetItemCount, GetItemIconByID = GetItemIcon }
C_CVar = { GetCVar = GetCVar, SetCVar = SetCVar, GetCVarBool = GetCVarBool }
C_Map = { GetBestMapForUnit = function() return 1 end, GetMapInfo = function() return { name = "Sandbox Isle", mapID = 1 } end }
C_ClassColor = { GetClassColor = function(c) return RAID_CLASS_COLORS[c] end }
function GetRealZoneText() return "Sandbox Isle" end
function GetZoneText() return "Sandbox Isle" end
function GetSubZoneText() return "" end
function GetMinimapZoneText() return "Sandbox Isle" end
function GetMoney() return 1234567 end
function GetFramerate() return 60 end
function GetNetStats() return 0, 0, 30, 30 end
function GetNumGuildMembers() return 0 end

---------------------------------------------------------------------------
-- Formatting helpers
---------------------------------------------------------------------------
function BreakUpLargeNumbers(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
FormatLargeNumber = BreakUpLargeNumbers
function AbbreviateNumbers(n)
  if n >= 1e9 then return string.format("%.1fB", n / 1e9) elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
  elseif n >= 1e3 then return string.format("%.1fK", n / 1e3) end
  return tostring(math.floor(n))
end
AbbreviateLargeNumbers = AbbreviateNumbers
function GetMoneyString(c)
  local g, s, cc = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  return string.format("%dg %ds %dc", g, s, cc)
end
GetCoinText = GetMoneyString
GetCoinTextureString = GetMoneyString
function SecondsToTime(s)
  s = math.floor(s)
  if s >= 3600 then return string.format("%d hr %d min", s // 3600, (s % 3600) // 60) end
  if s >= 60 then return string.format("%d min %d sec", s // 60, s % 60) end
  return string.format("%d sec", s)
end
function GetClassColor(class) local c = RAID_CLASS_COLORS[class] if c then return c.r, c.g, c.b, c.colorStr end return 1, 1, 1, "ffffffff" end
function ColorGradient(perc, ...)
  if perc >= 1 then local n = select("#", ...) return select(n - 2, ...) end
  if perc <= 0 then return ... end
  local num = select("#", ...) / 3
  local segment, relperc = math.modf(perc * (num - 1))
  local r1, g1, b1, r2, g2, b2 = select((segment * 3) + 1, ...)
  return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
end
function WrapTextInColorCode(text, hex) return "|c" .. hex .. text .. "|r" end

---------------------------------------------------------------------------
-- Callback registry
---------------------------------------------------------------------------
EventRegistry = { _cb = {} }
function EventRegistry:RegisterCallback(ev, fn, owner)
  self._cb[ev] = self._cb[ev] or {}
  table.insert(self._cb[ev], { fn = fn, owner = owner })
end
function EventRegistry:UnregisterCallback(ev, owner)
  local l = self._cb[ev]
  if l then for i = #l, 1, -1 do if l[i].owner == owner then table.remove(l, i) end end end
end
function EventRegistry:TriggerEvent(ev, ...)
  local l = self._cb[ev]
  if l then for _, c in ipairs(l) do __safecall(c.fn, c.owner, ...) end end
end
function CreateFromMixinsCallbackRegistry() return setmetatable({}, { __index = EventRegistry }) end

---------------------------------------------------------------------------
-- Addons: registry, metadata, loading
---------------------------------------------------------------------------
__addons = {}
function __BeginAddon(name, metaJson, svJson)
  local meta = __unjson(metaJson) or {}
  __addons[name] = { ns = {}, meta = meta, loaded = false, sv = {} }
  __addonList[#__addonList + 1] = name
  local savedVars = {}
  for v in string.gmatch((meta.SavedVariables or ""), "[^,%s]+") do savedVars[#savedVars + 1] = v end
  __addons[name].svNames = savedVars
  local saved = svJson and __unjson(svJson, true) or {}
  for _, v in ipairs(savedVars) do _G[v] = saved[v] end
end

function __RunFile(addon, path)
  local lower = string.lower(path)
  if string.sub(lower, -4) == ".lua" then
    local src = __readFile(addon, path)
    if not src then __log("error", "Missing file listed in TOC: " .. path) return end
    local fn, err = load(src, "@" .. path)
    if not fn then __log("error", tostring(err)) return end
    __safecall(fn, addon, __addons[addon].ns)
  elseif string.sub(lower, -4) == ".xml" then
    local json = __readXml(addon, path)
    if not json then __log("error", "Missing or invalid XML file: " .. path) return end
    __RunXML(addon, path, json)
  end
end

function __EndAddon(name)
  __addons[name].loaded = true
  __FireEvent("ADDON_LOADED", name)
end

function __DumpSV()
  local out = {}
  for name, a in pairs(__addons) do
    local vars = {}
    for _, v in ipairs(a.svNames or {}) do
      local val = _G[v]
      if type(val) == "table" then vars[v] = val end
    end
    out[name] = vars
  end
  return __json(out, true)
end

function GetAddOnMetadata(name, field)
  local a = __addons[name]
  return a and a.meta[field]
end
C_AddOns = {
  GetAddOnMetadata = GetAddOnMetadata,
  IsAddOnLoaded = function(n) return __addons[n] ~= nil and __addons[n].loaded end,
  GetNumAddOns = GetNumAddOns,
  IsAddOnLoadOnDemand = function() return false end,
  LoadAddOn = function() return false, "DISABLED" end,
  EnableAddOn = function() end, DisableAddOn = function() end,
}
function IsAddOnLoaded(n) return __addons[n] ~= nil and __addons[n].loaded end
function LoadAddOn() return false, "DISABLED" end
function GetAddOnInfo(n)
  local a = __addons[n]
  if not a then return end
  return n, a.meta.Title or n, a.meta.Notes or "", true, "LOADED", "", false
end
function EnableAddOn() end
function DisableAddOn() end
function ReloadUI() __reload() end
function Logout() end
function Quit() end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SlashCmdList = {}

function __Slash(line)
  local cmd, rest = string.match(line, "^(/%S+)%s*(.*)$")
  if not cmd then return false end
  local lc = string.lower(cmd)
  if lc == "/reload" or lc == "/reloadui" or lc == "/rl" then __reload() return true end
  if lc == "/run" or lc == "/script" then
    local fn, err = load(rest, "@/run")
    if not fn then __log("error", tostring(err)) else __safecall(fn) end
    return true
  end
  if lc == "/dump" then
    local fn, err = load("return " .. rest, "@/dump")
    if not fn then __log("error", tostring(err)) return true end
    local ok, v = pcall(fn)
    if not ok then __log("error", tostring(v)) return true end
    __log("chat", type(v) == "table" and __json(v) or tostring(v))
    return true
  end
  if lc == "/framestack" or lc == "/fstack" then __log("info", "Use the Inspector panel to explore frames.") return true end
  for key, fn in pairs(SlashCmdList) do
    local i = 1
    while true do
      local c = _G["SLASH_" .. key .. i]
      if not c then break end
      if string.lower(c) == lc then __safecall(fn, rest, DEFAULT_CHAT_FRAME) return true end
      i = i + 1
    end
  end
  __log("chat", "|cffff6060Unknown command:|r " .. cmd)
  return false
end

---------------------------------------------------------------------------
-- Static popups
---------------------------------------------------------------------------
StaticPopupDialogs = {}
local popup
function StaticPopup_Show(which, a1, a2, data)
  local d = StaticPopupDialogs[which]
  if not d then return end
  if not popup then
    popup = CreateFrame("Frame", "StaticPopup1", UIParent, "BackdropTemplate")
    popup:SetFrameStrata("DIALOG")
    popup:SetSize(340, 120)
    popup:SetPoint("TOP", UIParent, "TOP", 0, -140)
    Templates.DialogBorderTemplate(popup)
    popup.text = popup:CreateFontString("StaticPopup1Text", "ARTWORK", "GameFontHighlight")
    popup.text:SetPoint("TOP", popup, "TOP", 0, -22)
    popup.text:SetWidth(290)
    popup.button1 = CreateFrame("Button", "StaticPopup1Button1", popup, "UIPanelButtonTemplate")
    popup.button1:SetSize(120, 24)
    popup.button1:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 18)
    popup.button2 = CreateFrame("Button", "StaticPopup1Button2", popup, "UIPanelButtonTemplate")
    popup.button2:SetSize(120, 24)
    popup.button2:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 18)
  end
  popup.data = data
  popup.text:SetText(string.format(d.text or "", a1, a2))
  popup.button1:SetText(d.button1 or "Okay")
  popup.button2:SetText(d.button2 or "Cancel")
  popup.button2:SetShown(d.button2 ~= nil)
  popup.button1:SetScript("OnClick", function() popup:Hide() if d.OnAccept then __safecall(d.OnAccept, popup, popup.data) end end)
  popup.button2:SetScript("OnClick", function() popup:Hide() if d.OnCancel then __safecall(d.OnCancel, popup, popup.data) end end)
  popup:Show()
  return popup
end
function StaticPopup_Hide() if popup then popup:Hide() end end
OKAY, CANCEL, ACCEPT, YES, NO, CLOSE = "Okay", "Cancel", "Accept", "Yes", "No", "Close"

---------------------------------------------------------------------------
-- Macros (account slots 1..120, character slots 121..138), kept in memory
---------------------------------------------------------------------------
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120, 18
local macros = {
  [1] = { name = "Sandbox Hello", icon = 134400, body = "/run print('hello from a macro')" },
  [2] = { name = "Focus", icon = 134400, body = "#showtooltip\n/focus [@mouseover,exists][]" },
  [121] = { name = "Char Macro", icon = 134400, body = "/dance" },
}
local function macroIndexRange(perChar) if perChar then return 121, 120 + MAX_CHARACTER_MACROS end return 1, MAX_ACCOUNT_MACROS end
function GetNumMacros()
  local a, c = 0, 0
  for i in pairs(macros) do if i <= MAX_ACCOUNT_MACROS then a = a + 1 else c = c + 1 end end
  return a, c
end
function GetMacroInfo(i)
  if type(i) == "string" then i = GetMacroIndexByName(i) end
  local m = macros[i]
  if m then return m.name, m.icon, m.body end
end
function GetMacroBody(i) local m = macros[i] return m and m.body end
function GetMacroIndexByName(name) for i, m in pairs(macros) do if m.name == name then return i end end return 0 end
function CreateMacro(name, icon, body, perChar)
  local lo, hi = macroIndexRange(perChar)
  for i = lo, hi do
    if not macros[i] then macros[i] = { name = name, icon = type(icon) == "number" and icon or 134400, body = body or "" } return i end
  end
end
function EditMacro(i, name, icon, body)
  local m = macros[i]
  if not m then return end
  m.name = name or m.name
  if icon then m.icon = icon end
  if body then m.body = body end
  return i
end
function DeleteMacro(i) macros[i] = nil end
function PickupMacro() end
function SetMacroItem() end
function SetMacroSpell() end
function GetNumMacroIcons() return 0 end
function GetMacroIcons(t) return t or {} end
function GetMacroItemIcons(t) return t or {} end
function RunMacroText(text) for line in string.gmatch(text, "[^\n]+") do __Slash(line) end end
function RunMacro(i) local m = macros[i] if m then RunMacroText(m.body) end end
function GetRunningMacro() return nil end

---------------------------------------------------------------------------
-- FauxScrollFrame helpers
---------------------------------------------------------------------------
local function fauxBar(frame) return frame.ScrollBar or _G[(frame:GetName() or "") .. "ScrollBar"] end
function FauxScrollFrame_GetOffset(frame) return frame.offset or 0 end
function FauxScrollFrame_SetOffset(frame, offset) frame.offset = offset end
function FauxScrollFrame_Update(frame, numItems, numToDisplay, valueStep, button, smallWidth, bigWidth, highlightFrame, smallHighlightWidth, bigHighlightWidth)
  local bar = fauxBar(frame)
  local show = numItems > numToDisplay
  frame.offset = frame.offset or 0
  if bar then
    local maxv = math.max(0, (numItems - numToDisplay) * valueStep)
    bar:SetMinMaxValues(0, maxv)
    bar:SetValueStep(valueStep)
    bar:SetShown(show)
    if not show then
      bar:SetValue(0)
      frame.offset = 0
    end
  end
  if highlightFrame then
    highlightFrame:SetWidth(show and (smallHighlightWidth or highlightFrame:GetWidth()) or (bigHighlightWidth or highlightFrame:GetWidth()))
  end
  if button and smallWidth and bigWidth then
    for i = 1, numToDisplay do
      local b = _G[button .. i]
      if b then b:SetWidth(show and smallWidth or bigWidth) end
    end
  end
  return show
end
function FauxScrollFrame_OnVerticalScroll(self, value, itemHeight, updateFunction)
  local bar = fauxBar(self)
  if bar then bar:SetValue(value) end
  self.offset = math.floor(value / itemHeight + 0.5)
  if updateFunction then updateFunction(self) end
end
function ScrollFrameTemplate_OnMouseWheel(self, delta)
  local bar = fauxBar(self)
  if not bar then return end
  local step = bar:GetValueStep()
  if not step or step == 0 then step = 20 end
  bar:SetValue(bar:GetValue() - delta * step)
end
FauxScrollFrame_OnMouseWheel = ScrollFrameTemplate_OnMouseWheel
