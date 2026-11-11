-- Bags, money and the cursor: C_Container for the backpack, GetCursorInfo/ClearCursor, and a simple
-- backpack window (ContainerFrame1, toggled with B or from the Game state tab).
-- Left-click a bag item to pick it up (it follows the mouse), click a slot to put it down,
-- right-click or Escape to drop it back. Shift-click inserts the item link.

BACKPACK_CONTAINER, NUM_BAG_SLOTS, NUM_BAG_FRAMES = 0, 4, 4
Enum.BagIndex = Enum.BagIndex or { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4 }

do
  local SLOTS = 16
  local bag = {} -- [slot] = { id, count }
  local cursor   -- { id, count, slot }
  local start = { { 6948, 1 }, { 4540, 5 }, { 118, 3 }, { 2589, 12 }, { 7073, 2 } }
  for i, e in ipairs(start) do
    bag[i] = { id = e[1], count = e[2] }
    __CacheItem(e[1])
  end
  __mock.money = __mock.money or 1234567
  function GetMoney() return __mock.money end
  -- Copper looted or given from the sandbox UI.
  function __AddMoney(copper)
    __mock.money = __mock.money + copper
    __GameEvent("PLAYER_MONEY")
  end

  local Refresh -- backpack window refresh, defined below

  local function changed()
    __GameEvent("BAG_UPDATE", 0)
    __GameEvent("BAG_UPDATE_DELAYED")
    if Refresh then Refresh() end
  end

  function __BagItemCount(id)
    if not id then return 0 end
    local n = 0
    for s = 1, SLOTS do if bag[s] and bag[s].id == id then n = n + bag[s].count end end
    return n
  end

  -- Adds items like looting does: tops up existing stacks, then fills empty slots. Returns how many fit.
  function __BagAdd(id, count)
    local it = __itemDB[id]
    if not it then return 0 end
    __CacheItem(id)
    local left = count
    for s = 1, SLOTS do
      local e = bag[s]
      if left > 0 and e and e.id == id and e.count < it.stack and not (cursor and cursor.slot == s) then
        local n = math.min(it.stack - e.count, left)
        e.count, left = e.count + n, left - n
      end
    end
    for s = 1, SLOTS do
      if left > 0 and not bag[s] then
        local n = math.min(it.stack, left)
        bag[s], left = { id = id, count = n }, left - n
      end
    end
    if left < count then changed() end
    return count - left
  end
  function __BagState()
    local out = {}
    for s = 1, SLOTS do
      local e = bag[s]
      if e then out[#out + 1] = { slot = s, id = e.id, count = e.count, name = __itemDB[e.id].name, quality = __itemDB[e.id].quality } end
    end
    return __json({ slots = out, free = C_Container.GetContainerNumFreeSlots(0), money = __mock.money })
  end
  function __BagClear(slot)
    if not bag[slot] then return end
    if cursor and cursor.slot == slot then ClearCursor() end
    bag[slot] = nil
    changed()
  end

  local function entry(b, s) if b == 0 then return bag[s] end end

  C_Container = {
    GetContainerNumSlots = function(b) return b == 0 and SLOTS or 0 end,
    GetContainerNumFreeSlots = function(b)
      if b ~= 0 then return 0, 0 end
      local n = 0
      for s = 1, SLOTS do if not bag[s] then n = n + 1 end end
      return n, 0
    end,
    GetContainerItemID = function(b, s) local e = entry(b, s) return e and e.id end,
    GetContainerItemLink = function(b, s) local e = entry(b, s) return e and __ItemLink(e.id) end,
    GetContainerItemInfo = function(b, s)
      local e = entry(b, s)
      if not e then return nil end
      local it = __itemDB[e.id]
      return {
        iconFileID = it.icon, stackCount = e.count, isLocked = cursor ~= nil and cursor.slot == s, quality = it.quality,
        isReadable = false, hasLoot = false, hyperlink = __ItemLink(e.id), isFiltered = false, hasNoValue = (it.sell or 0) == 0,
        itemID = e.id, isBound = (it.bind or 0) == 1,
      }
    end,
    GetBagName = function(b) return b == 0 and "Backpack" or nil end,
    PickupContainerItem = function(b, s) if b == 0 then __PickupSlot(s) end end,
    UseContainerItem = function(b, s)
      local e = entry(b, s)
      if e then UIErrorsFrame:AddMessage("You can't use that here.", 1, 0.1, 0.1) end
    end,
    SplitContainerItem = function() end,
    GetContainerItemCooldown = function() return 0, 0, 0 end,
    IsContainerFiltered = function() return false end,
    SortBags = function() end,
  }

  -- ------------------------------------------------------------ cursor
  local cursorFrame = CreateFrame("Frame", nil, UIParent)
  cursorFrame:SetFrameStrata("TOOLTIP")
  cursorFrame:SetSize(30, 30)
  cursorFrame:EnableMouse(false)
  cursorFrame:Hide()
  local cursorIcon = cursorFrame:CreateTexture(nil, "ARTWORK")
  cursorIcon:SetAllPoints()
  local cursorCount = cursorFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  cursorCount:SetPoint("BOTTOMRIGHT", cursorFrame, "BOTTOMRIGHT", -1, 1)
  cursorFrame:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 6, y - 6)
  end)

  local function setCursor(c)
    local old = cursor
    cursor = c
    if c then
      cursorIcon:SetTexture(__itemDB[c.id].icon)
      cursorCount:SetText(c.count > 1 and c.count or "")
      cursorFrame:Show()
    else
      cursorFrame:Hide()
    end
    __GameEvent("CURSOR_CHANGED", c == nil, c and 1 or 0, old and 1 or 0, 0)
    if Refresh then Refresh() end
  end

  function GetCursorInfo()
    if cursor then return "item", cursor.id, __ItemLink(cursor.id) end
  end
  function CursorHasItem() return cursor ~= nil end
  function ClearCursor() if cursor then setCursor(nil) end end
  function ResetCursor() end
  function SetCursor() end
  function DeleteCursorItem()
    if not cursor then return end
    bag[cursor.slot] = nil
    setCursor(nil)
    changed()
  end
  C_Cursor = { GetCursorItem = function() return nil end }

  -- Picks up a bag slot, or puts the item on the cursor down there (swapping with what the slot holds).
  function __PickupSlot(s)
    if cursor then
      local from = cursor.slot
      if from ~= s then bag[from], bag[s] = bag[s], bag[from] end
      setCursor(nil)
      if from ~= s then changed() end
    elseif bag[s] then
      setCursor({ id = bag[s].id, count = bag[s].count, slot = s })
    end
  end

  -- ------------------------------------------------------------ backpack window
  local SIZE, GAP, COLS = 37, 4, 4
  local win = CreateFrame("Frame", "ContainerFrame1", UIParent, "BasicFrameTemplate")
  win:SetSize(COLS * (SIZE + GAP) + 26, math.ceil(SLOTS / COLS) * (SIZE + GAP) + 64)
  win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 60)
  win:SetFrameStrata("MEDIUM")
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetTitle("Backpack")
  win:Hide()
  local money = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  money:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -16, 14)
  money:SetJustifyH("RIGHT")

  local buttons = {}
  for s = 1, SLOTS do
    local b = CreateFrame("Button", "ContainerFrame1Item" .. s, win)
    b:SetID(s)
    b:SetSize(SIZE, SIZE)
    local col, row = (s - 1) % COLS, math.floor((s - 1) / COLS)
    b:SetPoint("TOPLEFT", win, "TOPLEFT", 13 + col * (SIZE + GAP), -32 - row * (SIZE + GAP))
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropColor(0.08, 0.08, 0.08, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.Count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    function b:GetBagID() return 0 end
    b:SetScript("OnEnter", function(self)
      if not bag[s] then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetBagItem(0, s)
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", function(self, button)
      if button == "RightButton" then
        if cursor then ClearCursor() else C_Container.UseContainerItem(0, s) end
      elseif IsModifiedClick("CHATLINK") and bag[s] and not cursor then
        HandleModifiedItemClick(__ItemLink(bag[s].id))
      else
        __PickupSlot(s)
      end
    end)
    b:SetScript("OnDragStart", function() if not cursor and bag[s] then __PickupSlot(s) end end)
    b:SetScript("OnReceiveDrag", function() if cursor then __PickupSlot(s) end end)
    buttons[s] = b
  end

  function Refresh()
    for s = 1, SLOTS do
      local b, e = buttons[s], bag[s]
      local it = e and __itemDB[e.id]
      b.icon:SetTexture(it and it.icon or nil)
      b.icon:SetShown(it ~= nil)
      b.icon:SetDesaturated(cursor ~= nil and cursor.slot == s)
      b.Count:SetText(e and e.count > 1 and e.count or "")
      local q = it and it.quality >= 2 and ITEM_QUALITY_COLORS[it.quality]
      if q then b:SetBackdropBorderColor(q.r, q.g, q.b, 1) else b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) end
    end
    money:SetText(GetCoinTextureString(GetMoney()))
  end
  Refresh()
  win:SetScript("OnShow", Refresh)
  local moneyWatch = CreateFrame("Frame")
  moneyWatch:RegisterEvent("PLAYER_MONEY")
  moneyWatch:SetScript("OnEvent", Refresh)

  function ToggleBackpack() win:SetShown(not win:IsShown()) end
  function OpenBackpack() win:Show() end
  function CloseBackpack() win:Hide() end
  function OpenAllBags() win:Show() end
  function CloseAllBags() win:Hide() end
  function ToggleAllBags() ToggleBackpack() end
  function IsBagOpen(b) return b == 0 and win:IsShown() end
  table.insert(UISpecialFrames, "ContainerFrame1")
end
