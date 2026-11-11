-- Loot: lootable corpses in the world, the loot API and events, and a simple loot window (LootFrame).
-- Corpses are spawned from the Game state tab (or __LootSpawn from Lua) and drawn as nameplates at the
-- bottom of the screen. Hover one for its unit tooltip (unit "mouseover"); click it to loot. Holding Shift
-- inverts auto loot (the autoLootDefault CVar), like the game's AUTOLOOTTOGGLE modified click.
-- Event order matches the client: LOOT_READY(autoLoot), LOOT_OPENED(autoLoot); LootSlot() clears the slot a
-- moment later (LOOT_SLOT_CLEARED), and the window closes by itself (LOOT_CLOSED) once it is empty.

Enum.LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 }
LOOT_SLOT_NONE, LOOT_SLOT_ITEM, LOOT_SLOT_MONEY, LOOT_SLOT_CURRENCY = 0, 1, 2, 3
LOOT_ROUTED_TO_BAG_DELAY = 0.15 -- seconds between LootSlot() and LOOT_SLOT_CLEARED (server round trip)
ERR_INV_FULL = "Inventory is full."
ERR_LOOT_NO_UI = "There is no loot."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
YOU_LOOT_MONEY = "You loot %s"
LOOT_NO_DROP = "Looting %s will bind it to you."

do
  local corpses = {}  -- { guid, name, level, ctype, loot = { { id, count } | { money } }, opened }
  local spawnSeq = 0
  local lootOpen      -- { slots = { ... }, sources = { corpse… }, autoLoot }
  local Refresh, RefreshWorld

  local function persist()
    if not __persist then return end
    local out = {}
    for _, c in ipairs(corpses) do out[#out + 1] = { guid = c.guid, name = c.name, level = c.level, ctype = c.ctype, loot = c.loot, opened = c.opened } end
    __persist("corpses", __json(out))
  end

  local function moneyName(copper)
    -- the game lists coin types on separate lines in the loot window ("1 Silver\n12 Copper")
    return GetCoinText(copper, "\n")
  end

  local function corpseByGUID(guid)
    for _, c in ipairs(corpses) do if c.guid == guid then return c end end
  end
  local function hasLoot(c) return #c.loot > 0 end

  -- ------------------------------------------------------------ units
  local function corpseUnit(c)
    return { name = c.name, level = c.level, creatureType = c.ctype, guid = c.guid, hp = 0, hpMax = 100, power = 0, powerMax = 0,
      powerType = 0, powerToken = "MANA", class = "WARRIOR", classLoc = "Warrior", race = "", sex = 1, isPlayer = false, hostile = true }
  end
  function CanLootUnit(guid)
    local c = corpseByGUID(guid)
    local has = c ~= nil and hasLoot(c)
    return has, has
  end

  -- ------------------------------------------------------------ loot window state
  local function slotEntry(s)
    local e = lootOpen and lootOpen.slots[s]
    if e and not e.cleared then return e end
  end

  -- Build slots from one or more corpses. Several corpses at once is area loot: the same item from several
  -- corpses shares one slot, and so does money; GetLootSourceInfo lists every source.
  local function buildSlots(list)
    local slots, byItem, moneySlot = {}, {}, nil
    for _, c in ipairs(list) do
      for _, src in ipairs(c.loot) do
        if src.money then
          if not moneySlot then moneySlot = { money = 0, sources = {} } slots[#slots + 1] = moneySlot end
          moneySlot.money = moneySlot.money + src.money
          moneySlot.sources[#moneySlot.sources + 1] = { corpse = c, src = src, qty = src.money }
        else
          local e = byItem[src.id]
          if not e then e = { id = src.id, count = 0, sources = {} } byItem[src.id] = e slots[#slots + 1] = e end
          e.count = e.count + (src.count or 1)
          e.sources[#e.sources + 1] = { corpse = c, src = src, qty = src.count or 1 }
          __CacheItem(src.id)
        end
      end
    end
    return slots
  end

  local function removeSources(e)
    for _, so in ipairs(e.sources) do
      for i, x in ipairs(so.corpse.loot) do
        if x == so.src then table.remove(so.corpse.loot, i) break end
      end
    end
    persist()
  end

  function GetNumLootItems() return lootOpen and #lootOpen.slots or 0 end
  function GetLootSlotType(s)
    local e = slotEntry(s)
    if not e then return LOOT_SLOT_NONE end
    return e.money and LOOT_SLOT_MONEY or LOOT_SLOT_ITEM
  end
  function LootSlotHasItem(s) return GetLootSlotType(s) == LOOT_SLOT_ITEM end
  function GetLootSlotLink(s)
    local e = slotEntry(s)
    if e and e.id then return __ItemLink(e.id) end
  end
  -- icon, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive
  function GetLootSlotInfo(s)
    local e = slotEntry(s)
    if not e then return nil end
    if e.money then return "Interface\\Icons\\INV_Misc_Coin_01", moneyName(e.money), 0, nil, 0, false, false, nil, false end
    local it = __itemDB[e.id]
    return it.icon, it.name, e.count, nil, it.quality, false, it.class == Enum.ItemClass.Questitem, nil, false
  end
  function GetLootInfo()
    local out = {}
    for s = 1, GetNumLootItems() do
      local icon, name, qty, cur, quality, locked, quest, questID, active = GetLootSlotInfo(s)
      out[s] = { texture = icon, item = name, quantity = qty, currencyID = cur, quality = quality, locked = locked,
        isQuestItem = quest, questID = questID, isActive = active, roll = false }
    end
    return out
  end
  function GetLootSourceInfo(s)
    local e = lootOpen and lootOpen.slots[s]
    if not e then return nil end
    local out = {}
    for _, so in ipairs(e.sources) do out[#out + 1] = so.corpse.guid out[#out + 1] = so.qty end
    return table.unpack(out)
  end
  function IsFishingLoot() return false end
  function GetLootThreshold() return 2 end
  function GetOptOutOfLoot() return false end
  C_Loot = C_Loot or {}
  C_Loot.IsLegacyLootModeEnabled = function() return false end

  function CloseLoot()
    if not lootOpen then return end
    local was = lootOpen
    lootOpen = nil
    for _, c in ipairs(was.sources) do c.opened = true end
    persist()
    if LootFrame:IsShown() then LootFrame:Hide() end
    StaticPopup_Hide("LOOT_BIND")
    __GameEvent("LOOT_CLOSED")
    RefreshWorld()
  end

  local function finishSlot(s, e)
    local got
    if e.money then
      __AddMoney(e.money)
      local text = string.format(YOU_LOOT_MONEY, GetCoinText(e.money))
      DEFAULT_CHAT_FRAME:AddMessage(text, 1, 1, 0)
      __GameEvent("CHAT_MSG_MONEY", text, "", "", "", "", "", 0, 0, "", 0, 0, nil)
      got = true
    else
      local added = __BagAdd(e.id, e.count)
      if added == 0 then
        UIErrorsFrame:AddMessage(ERR_INV_FULL, 1, 0.1, 0.1)
        __GameEvent("UI_ERROR_MESSAGE", 0, ERR_INV_FULL)
        return false
      end
      local link = __ItemLink(e.id)
      local text = added > 1 and string.format(LOOT_ITEM_SELF_MULTIPLE, link, added) or string.format(LOOT_ITEM_SELF, link)
      DEFAULT_CHAT_FRAME:AddMessage(text, 0, 0.67, 0)
      __GameEvent("CHAT_MSG_LOOT", text, UnitName("player"), "", "", UnitName("player"), "", 0, 0, "", 0, 0, UnitGUID("player"))
      if added < e.count then
        -- only part of it fit: take that much off the corpses, the rest stays in the slot
        e.count = e.count - added
        local rest = added
        for _, so in ipairs(e.sources) do
          local take = math.min(so.qty, rest)
          so.qty, so.src.count, rest = so.qty - take, (so.src.count or 1) - take, rest - take
          if so.src.count <= 0 then
            for i, x in ipairs(so.corpse.loot) do if x == so.src then table.remove(so.corpse.loot, i) break end end
          end
        end
        persist()
        UIErrorsFrame:AddMessage(ERR_INV_FULL, 1, 0.1, 0.1)
        return false
      end
      got = true
    end
    if got then
      e.cleared = true
      removeSources(e)
      __GameEvent("LOOT_SLOT_CLEARED", s)
    end
    return got
  end

  local function takeSlot(s, confirmed)
    local e = slotEntry(s)
    if not e or e.pending then return end
    local it = e.id and __itemDB[e.id]
    if it and it.bind == Enum.ItemBind.OnAcquire and not confirmed and not e.confirmed then
      -- the server answers with LOOT_BIND_CONFIRM a moment later, not from inside LootSlot()
      if e.awaitingBind then return end
      e.awaitingBind = true
      local session = lootOpen
      C_Timer.After(LOOT_ROUTED_TO_BAG_DELAY, function()
        if lootOpen ~= session or not e.awaitingBind then return end
        __GameEvent("LOOT_BIND_CONFIRM", s)
        if e.awaitingBind and lootOpen == session then
          StaticPopup_Show("LOOT_BIND", __ItemLink(e.id), nil, s)
          if Refresh then Refresh() end
        end
      end)
      return
    end
    e.awaitingBind, e.confirmed, e.pending = nil, true, true
    local session = lootOpen
    C_Timer.After(LOOT_ROUTED_TO_BAG_DELAY, function()
      if lootOpen ~= session then return end
      e.pending = nil
      finishSlot(s, e)
      if Refresh then Refresh() end
      RefreshWorld()
      for _, x in ipairs(session.slots) do if not x.cleared then return end end
      CloseLoot()
    end)
  end
  function LootSlot(s) takeSlot(s, false) end
  function ConfirmLootSlot(s)
    local e = slotEntry(s)
    if e and e.awaitingBind then
      e.awaitingBind = nil
      takeSlot(s, true)
    end
  end
  StaticPopupDialogs.LOOT_BIND = {
    text = LOOT_NO_DROP, button1 = OKAY, button2 = CANCEL,
    OnAccept = function(_, slot) ConfirmLootSlot(slot) end,
    OnCancel = function(_, slot) local e = slotEntry(slot) if e then e.awaitingBind = nil end end, -- clicking the item asks again
    timeout = 0, whileDead = true, hideOnEscape = true,
  }

  -- Open loot on these corpses. invert = the auto-loot toggle modifier (Shift) is held.
  local function openLoot(list, invert)
    if lootOpen then CloseLoot() end
    local usable = {}
    for _, c in ipairs(list) do if hasLoot(c) then usable[#usable + 1] = c end end
    if #usable == 0 then
      UIErrorsFrame:AddMessage(ERR_LOOT_NO_UI, 1, 0.1, 0.1)
      return
    end
    local autoLoot = (GetCVarBool("autoLootDefault") and true or false) ~= (invert and true or false)
    lootOpen = { slots = buildSlots(usable), sources = usable, autoLoot = autoLoot }
    local session = lootOpen
    __GameEvent("LOOT_READY", autoLoot)
    if lootOpen ~= session then return end
    if autoLoot then for s = 1, #session.slots do takeSlot(s, false) end end
    if lootOpen ~= session then return end
    __GameEvent("LOOT_OPENED", autoLoot, false)
    if lootOpen ~= session then return end
    -- with auto loot the window stays closed unless something is left (bind confirmation, full bags)
    if not autoLoot then LootFrame:Show() end
    if Refresh then Refresh() end
    RefreshWorld()
  end

  -- ------------------------------------------------------------ host (Game state tab) helpers
  function __LootSpawn(json)
    local t = type(json) == "string" and __unjson(json) or json
    spawnSeq = spawnSeq + 1
    local npc = tonumber(t.npcID) or (1000 + spawnSeq)
    local c = {
      guid = string.format("Creature-0-1-1-1-%d-%010X", npc, math.floor(__now() * 1000) * 100 + spawnSeq % 100),
      name = t.name or "Corpse", level = tonumber(t.level) or 1, ctype = t.ctype or t.type or "Beast", loot = {},
    }
    for _, l in ipairs(t.loot or {}) do
      if l.money and tonumber(l.money) and tonumber(l.money) > 0 then c.loot[#c.loot + 1] = { money = math.floor(tonumber(l.money)) }
      elseif l.id and __itemDB[tonumber(l.id)] then c.loot[#c.loot + 1] = { id = tonumber(l.id), count = math.max(1, tonumber(l.count) or 1) } end
    end
    corpses[#corpses + 1] = c
    persist()
    RefreshWorld()
    return c.guid
  end
  function __LootSpawnSamples()
    __LootSpawn({ name = "Timber Wolf", level = 6, ctype = "Beast", npcID = 69, loot = { { id = 7073, count = 1 }, { id = 2672, count = 1 }, { money = 23 } } })
    __LootSpawn({ name = "Defias Thug", level = 9, ctype = "Humanoid", npcID = 38, loot = { { id = 2589, count = 2 }, { id = 752, count = 1 }, { id = 7074, count = 1 }, { money = 112 } } })
    __LootSpawn({ name = "Defias Pillager", level = 15, ctype = "Humanoid", npcID = 589, loot = { { id = 2592, count = 1 }, { id = 10399, count = 1 }, { id = 2589, count = 1 }, { money = 205 } } })
    __LootSpawn({ name = "Edwin VanCleef", level = 21, ctype = "Humanoid", npcID = 639, loot = { { id = 5191, count = 1 }, { id = 1482, count = 1 }, { money = 4321 } } })
  end
  function __LootOpen(index, invert)
    if index == "all" then
      local list = {}
      for _, c in ipairs(corpses) do list[#list + 1] = c end
      openLoot(list, invert)
    elseif corpses[index] then
      openLoot({ corpses[index] }, invert)
    end
  end
  function __LootRemove(index)
    if lootOpen then CloseLoot() end
    table.remove(corpses, index)
    persist()
    RefreshWorld()
  end
  function __LootClear()
    if lootOpen then CloseLoot() end
    corpses = {}
    persist()
    RefreshWorld()
  end
  function __LootState()
    local out = {}
    for i, c in ipairs(corpses) do
      local loot = {}
      for _, l in ipairs(c.loot) do
        if l.money then loot[#loot + 1] = { money = l.money }
        else loot[#loot + 1] = { id = l.id, count = l.count, name = __itemDB[l.id].name, quality = __itemDB[l.id].quality } end
      end
      out[#out + 1] = { index = i, guid = c.guid, name = c.name, level = c.level, ctype = c.ctype, loot = loot, opened = c.opened or false }
    end
    return __json({ corpses = out, open = lootOpen ~= nil, autoLoot = GetCVarBool("autoLootDefault") and true or false })
  end

  -- ------------------------------------------------------------ the loot window
  local ROW = 40
  local win = CreateFrame("Frame", "LootFrame", UIParent, "BasicFrameTemplate")
  win:SetSize(220, 80)
  win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -120)
  win:SetFrameStrata("HIGH")
  win:EnableMouse(true)
  win:SetMovable(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:Hide()
  win:SetScript("OnHide", function() if lootOpen then CloseLoot() end end)
  table.insert(UISpecialFrames, "LootFrame")
  local rows = {}
  local function row(i)
    if rows[i] then return rows[i] end
    local b = CreateFrame("Button", "LootButton" .. i, win)
    b:SetSize(196, ROW - 4)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(32, 32)
    b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
    b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.Count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 1)
    b.Text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.Text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.Text:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    b.Text:SetJustifyH("LEFT")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
      if GetLootSlotType(self.slot) == LOOT_SLOT_ITEM then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetLootItem(self.slot)
      end
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", function(self)
      if IsModifiedClick() and HandleModifiedItemClick(GetLootSlotLink(self.slot)) then return end
      LootSlot(self.slot)
    end)
    rows[i] = b
    return b
  end

  function Refresh()
    local n = 0
    for _, b in ipairs(rows) do b:Hide() end
    if not lootOpen then return end
    local first = lootOpen.sources[1]
    win:SetTitle(#lootOpen.sources > 1 and (first.name .. " +" .. (#lootOpen.sources - 1)) or first.name)
    for s, e in ipairs(lootOpen.slots) do
      if not e.cleared then
        n = n + 1
        local b = row(n)
        b.slot = s
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -30 - (n - 1) * ROW)
        local icon, name, qty, _, quality = GetLootSlotInfo(s)
        b.icon:SetTexture(icon)
        b.Count:SetText(qty and qty > 1 and qty or "")
        b.Text:SetText(e.money and string.gsub(name, "\n", " ") or name)
        local q = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
        b.Text:SetTextColor(q.r, q.g, q.b)
        b:Show()
      end
    end
    win:SetHeight(40 + math.max(1, n) * ROW)
    if lootOpen.autoLoot and n > 0 and not win:IsShown() then
      -- auto loot left something behind (bind confirmation, full bags): show what is left
      local waiting = false
      for _, e in ipairs(lootOpen.slots) do if not e.cleared and not e.pending then waiting = true end end
      if waiting then win:Show() end
    end
  end

  -- ------------------------------------------------------------ corpses in the world
  local world = {}
  local function setMouseover(c)
    __mock.units.mouseover = c and corpseUnit(c) or nil
    __FireEvent("UPDATE_MOUSEOVER_UNIT")
  end
  local function plate(i)
    if world[i] then return world[i] end
    local b = CreateFrame("Button", "SandboxCorpse" .. i, WorldFrame)
    b:SetSize(150, 26)
    b:SetFrameStrata("BACKGROUND")
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropColor(0.05, 0.05, 0.05, 0.75)
    b:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    b.Name = b:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    b.Name:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.Name:SetPoint("RIGHT", b, "RIGHT", -18, 0)
    b.Name:SetJustifyH("LEFT")
    b.Sparkle = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.Sparkle:SetPoint("RIGHT", b, "RIGHT", -5, 0)
    b.Sparkle:SetText("✦")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
      setMouseover(corpses[self.index])
      GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
      GameTooltip:SetUnit("mouseover")
    end)
    b:SetScript("OnLeave", function()
      setMouseover(nil)
      GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
      local c = corpses[self.index]
      if c then openLoot({ c }, IsModifiedClick("AUTOLOOTTOGGLE")) end
      if GameTooltip:IsShown() and __mock.units.mouseover then GameTooltip:RefreshData() end
    end)
    world[i] = b
    return b
  end
  function RefreshWorld()
    for _, b in ipairs(world) do b:Hide() end
    local perRow = 6
    for i, c in ipairs(corpses) do
      local b = plate(i)
      b.index = i
      local col, r = (i - 1) % perRow, math.floor((i - 1) / perRow)
      local n = math.min(perRow, #corpses - r * perRow)
      b:ClearAllPoints()
      b:SetPoint("BOTTOM", UIParent, "BOTTOM", (col - (n - 1) / 2) * 158, 12 + r * 32)
      b.Name:SetText(c.name .. " (" .. c.level .. ")")
      -- Forever stops the sparkle once a corpse has been opened, even if items remain; retail keeps it while loot is left
      local forever = select(4, GetBuildInfo()) == 16001
      b.Sparkle:SetShown(hasLoot(c) and not (forever and c.opened))
      b:Show()
    end
  end

  -- restore corpses from the last session
  local saved = __restore and __restore("corpses")
  for _, c in ipairs(saved and __unjson(saved) or {}) do
    if type(c) == "table" and c.guid then
      spawnSeq = spawnSeq + 1
      -- drop loot that no longer exists (e.g. an item added with __RegisterItem in an earlier session)
      local loot = {}
      for _, l in ipairs(type(c.loot) == "table" and c.loot or {}) do
        if (tonumber(l.money) or 0) > 0 then loot[#loot + 1] = { money = tonumber(l.money) }
        elseif l.id and __itemDB[l.id] and (tonumber(l.count) or 1) > 0 then loot[#loot + 1] = { id = l.id, count = tonumber(l.count) or 1 } end
      end
      c.loot = loot
      c.name, c.level, c.ctype = c.name or "Corpse", tonumber(c.level) or 1, c.ctype or "Beast"
      corpses[#corpses + 1] = c
    end
  end
  RefreshWorld()
  -- the client (Forever or not) is only known once the addons' TOCs are read
  local login = CreateFrame("Frame")
  login:RegisterEvent("PLAYER_LOGIN")
  login:SetScript("OnEvent", RefreshWorld)
end
