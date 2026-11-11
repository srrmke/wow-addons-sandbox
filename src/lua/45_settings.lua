-- Settings: the game's Options window (SettingsPanel) with a Game / AddOns category list on the left.
-- Canvas categories (Settings.RegisterCanvasLayoutCategory / Subcategory) show the addon's own frame;
-- legacy InterfaceOptions_AddCategory panels work too. Vertical-layout settings are accepted but only listed.

do
  local categories, byID, nextID = {}, {}, 1
  local current
  local W, H, LIST_W = 860, 600, 200

  local panel = CreateFrame("Frame", "SettingsPanel", UIParent, "BasicFrameTemplate")
  panel:SetSize(W, H)
  panel:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
  panel:SetFrameStrata("HIGH")
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetTitle("Options")
  panel:Hide()
  table.insert(UISpecialFrames, "SettingsPanel")

  local list = CreateFrame("Frame", "SettingsPanelCategoryList", panel, "InsetFrameTemplate")
  list:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -56)
  list:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 48)
  list:SetWidth(LIST_W)

  local container = CreateFrame("Frame", "SettingsPanelContainer", panel, "InsetFrameTemplate")
  container:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
  container:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 48)
  panel.Container = container
  local canvas = CreateFrame("Frame", "SettingsPanelCanvas", container)
  canvas:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -4)
  canvas:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 4)

  local tabs, activeTab = {}, "AddOns"
  local function tab(name, x)
    local b = CreateFrame("Button", "SettingsPanel" .. name .. "Tab", panel, "UIPanelButtonTemplate")
    b:SetSize(96, 22)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -28)
    b:SetText(name)
    tabs[name] = b
    return b
  end
  tab("Game", 16)
  tab("AddOns", 116)

  local defaults = CreateFrame("Button", "SettingsPanelDefaultsButton", panel, "UIPanelButtonTemplate")
  defaults:SetSize(120, 22)
  defaults:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 16)
  defaults:SetText("Defaults")
  local close = CreateFrame("Button", "SettingsPanelCloseButton2", panel, "UIPanelButtonTemplate")
  close:SetSize(120, 22)
  close:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
  close:SetText("Close")
  close:SetScript("OnClick", function() panel:Hide() end)
  panel.CloseButton:SetScript("OnClick", function() panel:Hide() end)

  -- ------------------------------------------------------------ categories
  local CategoryMixin = {}
  function CategoryMixin:GetID() return self.ID end
  function CategoryMixin:GetName() return self.name end
  function CategoryMixin:SetName(n) self.name = n end
  function CategoryMixin:GetParentCategory() return self.parent end
  function CategoryMixin:GetSubcategories() return self.subcategories end
  function CategoryMixin:HasSubcategories() return #self.subcategories > 0 end
  function CategoryMixin:SetOrder(o) self.order = o end
  function CategoryMixin:GetOrder() return self.order or 0 end
  function CategoryMixin:SetExpanded(b) self.expanded = b end
  function CategoryMixin:IsExpanded() return self.expanded end

  local function newCategory(frame, name, parent, group)
    local c = CreateFromMixins(CategoryMixin)
    c.ID, c.name, c.frame, c.parent, c.subcategories, c.group, c.expanded = nextID, name, frame, parent, {}, group or "AddOns", true
    nextID = nextID + 1
    byID[c.ID] = c
    if parent then parent.subcategories[#parent.subcategories + 1] = c else categories[#categories + 1] = c end
    if frame then frame:Hide() end
    return c
  end

  local layoutMixin = {}
  function layoutMixin:AddInitializer() end
  function layoutMixin:GetInitializers() return {} end
  function layoutMixin:GetLayoutType() return self.kind end
  local function newLayout(kind) local l = CreateFromMixins(layoutMixin) l.kind = kind return l end

  -- ------------------------------------------------------------ the category list
  local buttons = {}
  local RefreshList
  local function flat()
    local out = {}
    local function add(c, depth)
      -- an addon's canvas category is only listed once it calls Settings.RegisterAddOnCategory
      if c.group ~= activeTab or c.pending then return end
      out[#out + 1] = { cat = c, depth = depth }
      if c.expanded then for _, s in ipairs(c.subcategories) do add(s, depth + 1) end end
    end
    local sorted = {}
    for _, c in ipairs(categories) do sorted[#sorted + 1] = c end
    table.sort(sorted, function(a, b)
      if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
      return a.ID < b.ID
    end)
    for _, c in ipairs(sorted) do add(c, 0) end
    return out
  end

  local Select
  function RefreshList()
    for _, b in ipairs(buttons) do b:Hide() end
    for i, e in ipairs(flat()) do
      local b = buttons[i]
      if not b then
        b = CreateFrame("Button", "SettingsPanelCategory" .. i, list)
        b:SetSize(LIST_W - 12, 20)
        b.Label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        b.Label:SetPoint("LEFT", b, "LEFT", 4, 0)
        b.Label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        b.Label:SetJustifyH("LEFT")
        b.Label:SetWordWrap(false)
        b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
        b:SetScript("OnClick", function(self)
          if self.cat == current and self.cat:HasSubcategories() then self.cat.expanded = not self.cat.expanded RefreshList() return end
          Select(self.cat)
        end)
        buttons[i] = b
      end
      b.cat = e.cat
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -6 - (i - 1) * 21)
      local label = (e.depth > 0 and "   " or "") .. e.cat.name
      if e.cat:HasSubcategories() then label = (e.cat.expanded and "- " or "+ ") .. label end
      b.Label:SetText(label)
      b.Label:SetFontObject(e.depth > 0 and "GameFontHighlightSmall" or "GameFontNormal")
      if e.cat == current then b:LockHighlight() else b:UnlockHighlight() end
      b:Show()
    end
    for name, t in pairs(tabs) do if name == activeTab then t:LockHighlight() else t:UnlockHighlight() end end
  end

  local placeholder = canvas:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  placeholder:SetPoint("CENTER", canvas, "CENTER")

  function Select(cat)
    if not cat then return end
    if current and current ~= cat and current.frame then current.frame:Hide() end
    current = cat
    activeTab = cat.group
    if cat.parent then cat.parent.expanded = true end
    placeholder:SetText("")
    local f = cat.frame
    if f then
      f:SetParent(canvas)
      f:ClearAllPoints()
      f:SetAllPoints(canvas)
      if not panel:IsShown() then panel:Show() end
      f:Show()
      if f.OnRefresh then __safecall(f.OnRefresh, f) end
    else
      if not panel:IsShown() then panel:Show() end
      placeholder:SetText(cat.vertical and "Vertical-layout settings aren't drawn by the sandbox." or "")
    end
    RefreshList()
    __FireEvent("SETTINGS_PANEL_CATEGORY_CHANGED", cat:GetID())
  end
  local function firstOf(group)
    local saved = activeTab
    activeTab = group
    local first = flat()[1]
    activeTab = saved
    return first and first.cat
  end
  tabs.Game:SetScript("OnClick", function() Select(firstOf("Game")) end)
  tabs.AddOns:SetScript("OnClick", function()
    local c = firstOf("AddOns")
    if c then Select(c) else activeTab = "AddOns" if current and current.frame then current.frame:Hide() end current = nil placeholder:SetText("No addon registered an options category.") RefreshList() end
  end)

  panel:SetScript("OnShow", function()
    if not current then
      local c = firstOf(activeTab) or firstOf("Game")
      if c then Select(c) end
    end
    RefreshList()
  end)
  panel:SetScript("OnHide", function()
    for _, c in pairs(byID) do if c.frame and c.frame.OnCommit then __safecall(c.frame.OnCommit, c.frame) end end
  end)

  StaticPopupDialogs.GAME_SETTINGS_APPLY_DEFAULTS = {
    text = "Reset \"%s\" to its default settings?", button1 = OKAY, button2 = CANCEL,
    OnAccept = function(_, cat)
      local f = cat and cat.frame
      if f and f.OnDefault then __safecall(f.OnDefault, f) end
      if f and f.OnRefresh then __safecall(f.OnRefresh, f) end
    end,
  }
  defaults:SetScript("OnClick", function()
    if current then StaticPopup_Show("GAME_SETTINGS_APPLY_DEFAULTS", current.name, nil, current) end
  end)

  function panel:SelectCategory(cat)
    if type(cat) == "number" then cat = byID[cat] end
    Select(cat)
  end
  function panel:Open() self:Show() end
  function panel:OpenToCategory(id) return Settings.OpenToCategory(id) end
  function panel:GetCategory(id) return byID[id] end
  function panel:GetCurrentCategory() return current end
  function panel:GetCategoryList() return categories end

  -- ------------------------------------------------------------ Settings API
  Settings = Settings or {}
  Settings.CategorySet = { Game = 1, AddOns = 2 }
  function Settings.RegisterCanvasLayoutCategory(frame, name, group)
    local c = newCategory(frame, name or (frame and frame.name) or "?", nil, "AddOns")
    c.pending = true -- listed once RegisterAddOnCategory is called, like the game
    return c, newLayout("canvas")
  end
  function Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)
    return newCategory(frame, name or (frame and frame.name) or "?", parent, parent and parent.group), newLayout("canvas")
  end
  function Settings.RegisterVerticalLayoutCategory(name)
    local c = newCategory(nil, name, nil, "AddOns")
    c.vertical = true
    return c, newLayout("vertical")
  end
  function Settings.RegisterVerticalLayoutSubcategory(parent, name)
    local c = newCategory(nil, name, parent, parent and parent.group)
    c.vertical = true
    return c, newLayout("vertical")
  end
  function Settings.RegisterAddOnCategory(cat)
    if cat then cat.pending = nil end
    if panel:IsShown() then RefreshList() end
  end
  function Settings.GetCategory(id) return byID[id] end
  function Settings.OpenToCategory(id)
    local cat = type(id) == "table" and id or byID[id]
    if not cat and type(id) == "string" then
      for _, c in pairs(byID) do if c.name == id then cat = c break end end
    end
    if not cat then return false end
    Select(cat)
    return true
  end
  -- Vertical-layout settings: stored and readable, not drawn.
  local SettingMixin = {}
  function SettingMixin:GetValue() if self.tbl then local v = self.tbl[self.key] if v == nil then return self.default end return v end return self.value end
  function SettingMixin:SetValue(v)
    if self.tbl then self.tbl[self.key] = v else self.value = v end
    if self.cb then for _, fn in ipairs(self.cb) do __safecall(fn, nil, self, v) end end
  end
  function SettingMixin:GetDefaultValue() return self.default end
  function SettingMixin:GetVariable() return self.variable end
  function SettingMixin:GetName() return self.name end
  function SettingMixin:SetValueChangedCallback(fn) self.cb = self.cb or {} self.cb[#self.cb + 1] = fn end
  function Settings.RegisterAddOnSetting(cat, variable, key, tbl, varType, name, default)
    local s = CreateFromMixins(SettingMixin)
    s.variable, s.key, s.tbl, s.name, s.default = variable, key, tbl, name, default
    return s
  end
  function Settings.RegisterProxySetting(cat, variable, varType, name, default, getter, setter)
    local s = CreateFromMixins(SettingMixin)
    s.variable, s.name, s.default = variable, name, default
    if getter then s.GetValue = function() return getter() end end
    if setter then s.SetValue = function(_, v) setter(v) end end
    return s
  end
  function Settings.CreateCheckbox() return {} end
  function Settings.CreateSlider() return {} end
  function Settings.CreateDropdown() return {} end
  function Settings.CreateControlTextContainer() local t = {} function t:Add() end function t:GetData() return {} end return t end
  function Settings.CreateSliderOptions(min, max, step) local o = { min = min, max = max, step = step } function o:SetLabelFormatter() end return o end
  function Settings.SetValue(variable, v) end
  function Settings.GetValue() return nil end
  Settings.VarType = { Boolean = "boolean", Number = "number", String = "string" }
  Settings.Default = { True = true, False = false }

  -- legacy Interface Options
  function InterfaceOptions_AddCategory(frame)
    local parent
    if frame.parent then for _, c in pairs(byID) do if c.name == frame.parent and not c.parent then parent = c end end end
    local c = parent and Settings.RegisterCanvasLayoutSubcategory(parent, frame, frame.name) or Settings.RegisterCanvasLayoutCategory(frame, frame.name)
    Settings.RegisterAddOnCategory(c)
    frame.settingsCategory = c
  end
  function InterfaceOptionsFrame_OpenToCategory(f)
    if type(f) == "table" and f.settingsCategory then return Select(f.settingsCategory) end
    return Settings.OpenToCategory(f)
  end
  InterfaceOptionsFrame = panel
  function ShowUIPanel(f) if f then f:Show() end end
  function HideUIPanel(f) if f then f:Hide() end end

  -- ------------------------------------------------------------ built-in Game pages
  -- Pages under the Game tab: anything that registers through __AddGameSettingsPage.
  function __AddGameSettingsPage(name, build)
    local f = CreateFrame("Frame")
    f.name = name
    local c = newCategory(f, name, nil, "Game")
    build(f)
    return c
  end
  __AddGameSettingsPage("Controls", function(f)
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    title:SetText("Controls")
    local cb = CreateFrame("CheckButton", "SettingsPanelAutoLoot", f, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -14)
    cb.Text:SetText("Auto Loot")
    cb.Text:SetFontObject("GameFontHighlight")
    cb:SetScript("OnClick", function(self) SetCVar("autoLootDefault", self:GetChecked() and "1" or "0") end)
    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 30, 0)
    hint:SetText("Hold Shift while looting to do the opposite (autoLootDefault CVar).")
    f.OnRefresh = function() cb:SetChecked(GetCVarBool("autoLootDefault")) end
    f.OnDefault = function() SetCVar("autoLootDefault", GetCVarDefault("autoLootDefault")) end
    f:SetScript("OnShow", f.OnRefresh)
  end)
end

function __ToggleSettings() SettingsPanel:SetShown(not SettingsPanel:IsShown()) end
