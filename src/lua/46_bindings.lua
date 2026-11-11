-- Key bindings: the binding API, addons' Bindings.xml, a few default game bindings, running the bound action on
-- key press, Escape (TOGGLEGAMEMENU) and a minimal game menu. Saved bindings persist across reloads.
-- Key names are the game's: letters/digits, F1…, SPACE, ENTER, ESCAPE, TAB, UP…, NUMPAD1…, LSHIFT/LCTRL/LALT…;
-- a combination is written ALT-CTRL-SHIFT-KEY.

ACCOUNT_BINDINGS, CHARACTER_BINDINGS, DEFAULT_BINDINGS = 1, 2, 0
KEY_BINDINGS = "Key Bindings"

do
  local actions, order = {}, {}           -- name -> { header, category, fn, runOnUp, builtin }
  local binds = {}                        -- key combo -> action
  local seq, bindSeq = 0, {}              -- assignment order, so GetBindingKey returns keys in a stable order
  local overrides, overrideOrder = {}, {} -- owner -> { key -> action }
  local bindingSet = ACCOUNT_BINDINGS

  local function addAction(name, t)
    if not actions[name] then order[#order + 1] = name end
    actions[name] = t
  end

  -- ------------------------------------------------------------ default game actions
  local function builtin(name, label, header, fn, key)
    _G["BINDING_NAME_" .. name] = _G["BINDING_NAME_" .. name] or label
    addAction(name, { header = header, fn = fn, builtin = true, default = key })
  end
  BINDING_HEADER_MOVEMENT, BINDING_HEADER_INTERFACE, BINDING_HEADER_TARGETING, BINDING_HEADER_MISC =
    "Movement Keys", "Interface Panel Functions", "Targeting Functions", "Miscellaneous"
  local nop = function() end
  builtin("MOVEFORWARD", "Move Forward", "MOVEMENT", nop, "W")
  builtin("MOVEBACKWARD", "Move Backward", "MOVEMENT", nop, "S")
  builtin("TURNLEFT", "Turn Left", "MOVEMENT", nop, "A")
  builtin("TURNRIGHT", "Turn Right", "MOVEMENT", nop, "D")
  builtin("JUMP", "Jump", "MOVEMENT", nop, "SPACE")
  builtin("SITORSTAND", "Sit/Move Down", "MOVEMENT", function() DEFAULT_CHAT_FRAME:AddMessage("You sit down.", 1, 1, 0) end, "X")
  builtin("TOGGLEAUTORUN", "Toggle Autorun", "MOVEMENT", nop, "NUMLOCK")
  builtin("TARGETNEARESTENEMY", "Target Nearest Enemy", "TARGETING", nop, "TAB")
  builtin("INTERACTTARGET", "Interact With Target", "TARGETING", nop, nil)
  builtin("TOGGLEGAMEMENU", "Toggle Game Menu", "INTERFACE", function() __ToggleGameMenu() end, "ESCAPE")
  builtin("OPENALLBAGS", "Open All Bags", "INTERFACE", function() ToggleAllBags() end, "B")
  builtin("TOGGLEBACKPACK", "Toggle Backpack", "INTERFACE", function() ToggleBackpack() end, "F12")
  builtin("TOGGLECHARACTER0", "Toggle Character Pane", "INTERFACE", nop, "C")
  builtin("TOGGLESPELLBOOK", "Toggle Spellbook", "INTERFACE", nop, "P")
  builtin("TOGGLEWORLDMAP", "Toggle World Map", "INTERFACE", nop, "M")
  builtin("TOGGLESOCIAL", "Toggle Social Pane", "INTERFACE", nop, "O")
  builtin("SCREENSHOT", "Screen Shot", "MISC", function() DEFAULT_CHAT_FRAME:AddMessage("Screen captured (not really: this is the sandbox).", 1, 1, 0) end, "PRINTSCREEN")

  local function resetToDefaults()
    binds, bindSeq, seq = {}, {}, 0
    for _, name in ipairs(order) do
      local a = actions[name]
      if a.builtin and a.default then seq = seq + 1 binds[a.default] = name bindSeq[a.default] = seq end
    end
  end
  resetToDefaults()

  local function persisted()
    local j = __restore and __restore("bindings")
    return j and __unjson(j)
  end
  local function applySaved(t)
    if not t or type(t.keys) ~= "table" then return false end
    binds, bindSeq, seq = {}, {}, 0
    for _, e in ipairs(t.keys) do
      seq = seq + 1
      binds[e[1]] = e[2]
      bindSeq[e[1]] = seq
    end
    bindingSet = t.set or ACCOUNT_BINDINGS
    return true
  end
  applySaved(persisted())

  -- ------------------------------------------------------------ Bindings.xml
  local function loadBindingsXml(addon)
    local json = __readXml and __readXml(addon, "Bindings.xml")
    if not json then return end
    local root = __unjson(json)
    if not root or root.t ~= "Bindings" then return end
    for _, n in ipairs(root.c or {}) do
      if n.t == "Binding" and n.a and n.a.name then
        local name, body = n.a.name, n.x or ""
        local fn, err = load("local keystate = ...\n" .. body, "@" .. addon .. "/Bindings.xml:" .. name)
        if not fn then __log("error", addon .. "/Bindings.xml: " .. tostring(err)) end
        addAction(name, { header = n.a.header, category = n.a.category, fn = fn, runOnUp = n.a.runOnUp == "true", addon = addon })
      end
    end
  end
  local endAddon = __EndAddon
  function __EndAddon(name)
    loadBindingsXml(name)
    endAddon(name)
  end

  -- ------------------------------------------------------------ API
  local function lookup(key)
    for i = #overrideOrder, 1, -1 do
      local o = overrides[overrideOrder[i]]
      if o and o[key] then return o[key] end
    end
    return binds[key]
  end

  function GetBindingKey(action)
    local keys = {}
    for k, a in pairs(binds) do if a == action then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return (bindSeq[a] or 0) < (bindSeq[b] or 0) end)
    return table.unpack(keys)
  end
  function GetBindingAction(key, checkOverride)
    if type(key) ~= "string" then return "" end
    return (checkOverride and lookup(key)) or binds[key] or ""
  end
  GetBindingByKey = function(key) local a = lookup(key) return a end
  function SetBinding(key, action)
    if type(key) ~= "string" or key == "" then return false end
    if action == nil or action == "" then
      binds[key], bindSeq[key] = nil, nil
    else
      seq = seq + 1
      binds[key], bindSeq[key] = action, seq
    end
    return true
  end
  function SetBindingClick(key, button, mouse) return SetBinding(key, "CLICK " .. tostring(button) .. ":" .. (mouse or "LeftButton")) end
  function SetBindingSpell(key, spell) return SetBinding(key, "SPELL " .. tostring(spell)) end
  function SetBindingItem(key, item) return SetBinding(key, "ITEM " .. tostring(item)) end
  function SetBindingMacro(key, macro) return SetBinding(key, "MACRO " .. tostring(macro)) end
  function SaveBindings(set)
    bindingSet = set == CHARACTER_BINDINGS and CHARACTER_BINDINGS or ACCOUNT_BINDINGS
    local keys = {}
    for k, a in pairs(binds) do keys[#keys + 1] = { k, a } end
    table.sort(keys, function(x, y) return (bindSeq[x[1]] or 0) < (bindSeq[y[1]] or 0) end)
    if __persist then __persist("bindings", __json({ set = bindingSet, keys = keys })) end
    __GameEvent("UPDATE_BINDINGS")
  end
  function LoadBindings(set)
    if set == DEFAULT_BINDINGS or not applySaved(persisted()) then resetToDefaults() end
    __GameEvent("UPDATE_BINDINGS")
  end
  function GetCurrentBindingSet() return bindingSet end
  function GetBindingName(action) return _G["BINDING_NAME_" .. tostring(action)] or action end
  function GetNumBindings() return #order end
  -- command, category, key1, key2
  function GetBinding(i)
    local name = order[i]
    if not name then return nil end
    local a = actions[name]
    return name, a.category or (a.header and ("BINDING_HEADER_" .. a.header)) or "ADDONS", GetBindingKey(name)
  end
  function RunBinding(action, keystate)
    local a = actions[action]
    if a and a.fn then __safecall(a.fn, keystate or "down") return end
    local button, mouse = string.match(action or "", "^CLICK ([^:]+):?(.*)$")
    if button and _G[button] and _G[button].Click then _G[button]:Click(mouse ~= "" and mouse or "LeftButton") end
  end
  function SetOverrideBinding(owner, priority, key, action)
    if not owner or not key then return end
    if not overrides[owner] then overrides[owner] = {} overrideOrder[#overrideOrder + 1] = owner end
    overrides[owner][key] = (action ~= "" and action) or nil
  end
  function SetOverrideBindingClick(owner, priority, key, button, mouse) SetOverrideBinding(owner, priority, key, "CLICK " .. button .. ":" .. (mouse or "LeftButton")) end
  function SetOverrideBindingSpell(owner, priority, key, spell) SetOverrideBinding(owner, priority, key, "SPELL " .. tostring(spell)) end
  function SetOverrideBindingItem(owner, priority, key, item) SetOverrideBinding(owner, priority, key, "ITEM " .. tostring(item)) end
  function SetOverrideBindingMacro(owner, priority, key, macro) SetOverrideBinding(owner, priority, key, "MACRO " .. tostring(macro)) end
  function ClearOverrideBindings(owner)
    overrides[owner] = nil
    for i = #overrideOrder, 1, -1 do if overrideOrder[i] == owner then table.remove(overrideOrder, i) end end
  end

  local keyText = {
    SPACE = "Spacebar", ESCAPE = "Escape", ENTER = "Enter", TAB = "Tab", BACKSPACE = "Backspace", DELETE = "Delete",
    INSERT = "Insert", HOME = "Home", END = "End", PAGEUP = "Page Up", PAGEDOWN = "Page Down", UP = "Up Arrow",
    DOWN = "Down Arrow", LEFT = "Left Arrow", RIGHT = "Right Arrow", CAPSLOCK = "Caps Lock", NUMLOCK = "Num Lock",
    PRINTSCREEN = "Print Screen", NUMPADENTER = "Num Pad Enter", NUMPADPLUS = "Num Pad +", NUMPADMINUS = "Num Pad -",
    NUMPADMULTIPLY = "Num Pad *", NUMPADDIVIDE = "Num Pad /", NUMPADDECIMAL = "Num Pad .", BUTTON1 = "Left Mouse Button",
    BUTTON2 = "Right Mouse Button", BUTTON3 = "Middle Mouse", MOUSEWHEELUP = "Mouse Wheel Up", MOUSEWHEELDOWN = "Mouse Wheel Down",
  }
  local modText = { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift", META = "Cmd" }
  function GetBindingText(key, prefix, abbreviate)
    if type(key) ~= "string" then return "" end
    local parts = {}
    for p in string.gmatch(key, "[^-]+") do parts[#parts + 1] = p end
    if string.sub(key, -1) == "-" then parts[#parts + 1] = "-" end
    for i, p in ipairs(parts) do
      if i < #parts and modText[p] then parts[i] = modText[p]
      elseif prefix and _G[prefix .. p] then parts[i] = _G[prefix .. p]
      else parts[i] = keyText[p] or (string.match(p, "^NUMPAD(%d)$") and ("Num Pad " .. string.sub(p, 7))) or p end
    end
    return table.concat(parts, "-")
  end

  -- ------------------------------------------------------------ dispatch
  local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }
  local downAction = {}
  function __RunKeyBinding(key, down)
    if MODIFIER_KEYS[key] then return end
    if down then
      local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
      local action = lookup(combo)
      downAction[key] = action
      if action then RunBinding(action, "down") end
    else
      local action = downAction[key]
      downAction[key] = nil
      if action and actions[action] and actions[action].runOnUp then RunBinding(action, "up") end
    end
  end

  -- ------------------------------------------------------------ Escape and the game menu
  local menu = CreateFrame("Frame", "GameMenuFrame", UIParent, "DialogBorderTemplate")
  menu:SetSize(200, 150)
  menu:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  menu:SetFrameStrata("DIALOG")
  menu:EnableMouse(true)
  menu:Hide()
  local mtitle = menu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  mtitle:SetPoint("TOP", menu, "TOP", 0, -18)
  mtitle:SetText("Game Menu")
  local function menuButton(text, y, fn)
    local b = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    b:SetSize(150, 24)
    b:SetPoint("TOP", menu, "TOP", 0, y)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
  end
  menuButton("Options", -44, function() menu:Hide() SettingsPanel:Show() end)
  menuButton("Key Bindings", -72, function() menu:Hide() Settings.OpenToCategory(__keybindingsCategory) end)
  menuButton("Return to Game", -110, function() menu:Hide() end)

  -- What Escape does when no frame kept the key: drop the cursor item, close a popup / special frame, or the game menu.
  function __ToggleGameMenu()
    if CursorHasItem and CursorHasItem() then ClearCursor() return end
    if menu:IsShown() then menu:Hide() return end
    local popup = _G.StaticPopup1
    if popup and popup:IsShown() then popup:Hide() return end
    local closed = false
    for _, name in ipairs(UISpecialFrames) do
      local f = _G[name]
      if f and f.IsShown and f:IsShown() then f:Hide() closed = true end
    end
    if not closed then menu:Show() end
  end

  -- ------------------------------------------------------------ Game > Keybindings page
  local page = __AddGameSettingsPage("Keybindings", function(f)
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    title:SetText("Keybindings")
    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetText("Click a key, then press the new key (Escape cancels, right-click unbinds).")
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -56)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 10)
    scroll:SetScrollChild(content)
    local rows, capturing, captureBtn = {}, nil, nil
    -- only one key button listens at a time; it stops listening when done, replaced or hidden
    local function stopCapture()
      if captureBtn then captureBtn:EnableKeyboard(false) captureBtn:SetScript("OnKeyDown", nil) end
      capturing, captureBtn = nil, nil
    end
    local function refresh()
      for _, r in ipairs(rows) do r.label:Hide() r.key:Hide() if r.header then r.header:Hide() end end
      local y, i, lastHeader = 0, 0, nil
      for _, name in ipairs(order) do
        local a = actions[name]
        local header = a.header or "ADDONS"
        i = i + 1
        local r = rows[i]
        if not r then
          r = {}
          r.header = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
          r.label = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
          r.label:SetJustifyH("LEFT")
          r.key = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
          r.key:SetSize(160, 20)
          r.key:RegisterForClicks("LeftButtonUp", "RightButtonUp")
          rows[i] = r
        end
        if header ~= lastHeader then
          lastHeader = header
          y = y + (y > 0 and 10 or 0)
          r.header:ClearAllPoints()
          r.header:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
          r.header:SetText(_G["BINDING_HEADER_" .. header] or header)
          r.header:Show()
          y = y + 20
        end
        r.label:ClearAllPoints()
        r.label:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -y - 3)
        r.label:SetText(GetBindingName(name))
        r.label:Show()
        r.key:ClearAllPoints()
        r.key:SetPoint("TOPLEFT", content, "TOPLEFT", 330, -y)
        local k = GetBindingKey(name)
        r.key:SetText(capturing == name and "Press a key…" or (k and GetBindingText(k) or "Not Bound"))
        r.key:SetScript("OnClick", function(self, button)
          if button == "RightButton" then
            for _, key in ipairs({ GetBindingKey(name) }) do SetBinding(key) end
            SaveBindings(GetCurrentBindingSet())
            stopCapture()
            refresh()
            return
          end
          stopCapture()
          capturing, captureBtn = name, self
          self:EnableKeyboard(true)
          self:SetPropagateKeyboardInput(false)
          self:SetScript("OnKeyDown", function(btn, key)
            if MODIFIER_KEYS[key] then return end
            stopCapture()
            if key ~= "ESCAPE" then
              local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
              local old = GetBindingKey(name)
              if old then SetBinding(old) end
              SetBinding(combo, name)
              SaveBindings(GetCurrentBindingSet())
            end
            refresh()
          end)
          refresh()
        end)
        r.key:Show()
        y = y + 24
      end
      content:SetHeight(y + 8)
    end
    f.OnRefresh = refresh
    f.OnDefault = function() LoadBindings(DEFAULT_BINDINGS) SaveBindings(ACCOUNT_BINDINGS) refresh() end
    f:SetScript("OnShow", refresh)
    f:SetScript("OnHide", stopCapture)
    local watcher = CreateFrame("Frame", nil, f)
    watcher:RegisterEvent("UPDATE_BINDINGS")
    watcher:SetScript("OnEvent", function() if f:IsVisible() then refresh() end end)
  end)
  __keybindingsCategory = page:GetID()
end
