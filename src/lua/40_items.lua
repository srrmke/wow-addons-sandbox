-- Item data: a small item table, item links, C_Item, the Item mixin, quality colours.
-- Items load asynchronously like in the game: GetItemInfo() returns nil for an item the client
-- hasn't cached yet, requests it, and ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED fire a moment later.
-- Add your own items from Lua with __RegisterItem(id, { name = "...", quality = 2, ... }).

-- Fired by sandbox systems (loot, bags, CVars…) rather than by the user. The host shows them in the Events tab.
function __GameEvent(event, ...)
  if __logEvent then
    local parts = {}
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      parts[i] = type(v) == "string" and ('"' .. v .. '"') or tostring(v)
    end
    __logEvent(event .. "(" .. table.concat(parts, ", ") .. ")")
  end
  __FireEvent(event, ...)
end

Enum = Enum or {}
Enum.ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Artifact = 6, Heirloom = 7, WoWToken = 8 }
Enum.ItemClass = {
  Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6, Tradegoods = 7,
  ItemEnhancement = 8, Recipe = 9, CurrencyTokenObsolete = 10, Quiver = 11, Questitem = 12, Key = 13,
  PermanentObsolete = 14, Miscellaneous = 15, Glyph = 16, Battlepet = 17, WoWToken = 18, Profession = 19,
}
Enum.ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4 }

do
  local qualityHex = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff", "00ccff" }
  ITEM_QUALITY_COLORS = {}
  for q = 0, #qualityHex do
    local hex = qualityHex[q]
    local c = CreateColorFromHexString("ff" .. hex)
    ITEM_QUALITY_COLORS[q] = { r = c.r, g = c.g, b = c.b, hex = "|cff" .. hex, color = c }
  end
  function GetItemQualityColor(q)
    local c = ITEM_QUALITY_COLORS[q] or ITEM_QUALITY_COLORS[1]
    return c.r, c.g, c.b, "ff" .. string.sub(c.hex, 5)
  end
  for name, q in pairs(Enum.ItemQuality) do _G["LE_ITEM_QUALITY_" .. string.upper(name)] = q end

  local classNames = {
    [0] = "Consumable", [1] = "Container", [2] = "Weapon", [3] = "Gem", [4] = "Armor", [5] = "Reagent", [6] = "Projectile",
    [7] = "Tradeskill", [8] = "Item Enhancement", [9] = "Recipe", [11] = "Quiver", [12] = "Quest", [13] = "Key", [15] = "Miscellaneous",
  }
  local subClassNames = {
    [0] = { [0] = "Consumable", [1] = "Potion", [5] = "Food & Drink" },
    [2] = { [0] = "One-Handed Axes", [4] = "One-Handed Maces", [7] = "One-Handed Swords", [10] = "Staves", [15] = "Daggers" },
    [4] = { [0] = "Miscellaneous", [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" },
    [7] = { [5] = "Cloth", [6] = "Leather", [7] = "Metal & Stone", [8] = "Cooking", [9] = "Herb" },
    [12] = { [0] = "Quest" },
    [15] = { [0] = "Junk", [4] = "Other" },
  }
  function GetItemClassInfo(classID) return classNames[classID] end
  function GetItemSubClassInfo(classID, subID) local t = subClassNames[classID] return t and t[subID] or classNames[classID], false end

  -- id = { name, quality, itemLevel, minLevel, classID, subclassID, equipLoc, icon, sellPrice (copper), stack, bind, extra tooltip lines }
  local DB = {}
  local function def(id, t) DB[id] = t end
  __itemDB = DB

  def(2589, { name = "Linen Cloth", quality = 1, ilvl = 5, class = 7, sub = 5, icon = "Interface\\Icons\\INV_Fabric_Linen_01", sell = 13, stack = 20 })
  def(2592, { name = "Wool Cloth", quality = 1, ilvl = 15, class = 7, sub = 5, icon = "Interface\\Icons\\INV_Fabric_Wool_01", sell = 33, stack = 20 })
  def(4306, { name = "Silk Cloth", quality = 1, ilvl = 25, class = 7, sub = 5, icon = "Interface\\Icons\\INV_Fabric_Silk_01", sell = 150, stack = 20 })
  def(2318, { name = "Light Leather", quality = 1, ilvl = 10, class = 7, sub = 6, icon = "Interface\\Icons\\INV_Misc_LeatherScrap_03", sell = 15, stack = 20 })
  def(2770, { name = "Copper Ore", quality = 1, ilvl = 10, class = 7, sub = 7, icon = "Interface\\Icons\\INV_Ore_Copper_01", sell = 5, stack = 20 })
  def(2447, { name = "Peacebloom", quality = 1, ilvl = 5, class = 7, sub = 9, icon = "Interface\\Icons\\INV_Misc_Flower_02", sell = 10, stack = 20 })
  def(769, { name = "Chunk of Boar Meat", quality = 1, ilvl = 7, class = 7, sub = 8, icon = "Interface\\Icons\\INV_Misc_Food_14", sell = 4, stack = 10 })
  def(2672, { name = "Stringy Wolf Meat", quality = 1, ilvl = 5, class = 7, sub = 8, icon = "Interface\\Icons\\INV_Misc_Food_14", sell = 4, stack = 10 })
  def(118, { name = "Minor Healing Potion", quality = 1, ilvl = 5, minLevel = 1, class = 0, sub = 1, icon = "Interface\\Icons\\INV_Potion_49", sell = 1, stack = 5,
    lines = { "|cff1eff00Use: Restores 70 to 90 health.|r" } })
  def(4540, { name = "Tough Hunk of Bread", quality = 1, ilvl = 5, minLevel = 1, class = 0, sub = 5, icon = "Interface\\Icons\\INV_Misc_Food_11", sell = 1, stack = 20,
    lines = { "|cff1eff00Use: Restores 61 health over 18 sec. Must remain seated while eating.|r" } })
  def(7073, { name = "Broken Fang", quality = 0, ilvl = 1, class = 15, sub = 0, icon = "Interface\\Icons\\INV_Misc_Bone_08", sell = 6, stack = 5 })
  def(7074, { name = "Chipped Claw", quality = 0, ilvl = 1, class = 15, sub = 0, icon = "Interface\\Icons\\INV_Misc_MonsterClaw_04", sell = 4, stack = 5 })
  def(752, { name = "Red Burlap Bandana", quality = 1, ilvl = 1, class = 12, sub = 0, icon = "Interface\\Icons\\INV_Misc_Bandana_01", sell = 0, stack = 20, bind = 4 })
  def(10399, { name = "Blackened Defias Armor", quality = 2, ilvl = 23, minLevel = 18, class = 4, sub = 2, equip = "INVTYPE_CHEST",
    icon = "Interface\\Icons\\INV_Chest_Leather_03", sell = 459, stack = 1, bind = 1 })
  def(5191, { name = "Cruel Barb", quality = 3, ilvl = 24, minLevel = 19, class = 2, sub = 7, equip = "INVTYPE_WEAPON",
    icon = "Interface\\Icons\\INV_Sword_10", sell = 1655, stack = 1, bind = 1 })
  def(1482, { name = "Shadowfang", quality = 3, ilvl = 30, minLevel = 25, class = 2, sub = 7, equip = "INVTYPE_WEAPON",
    icon = "Interface\\Icons\\INV_Sword_23", sell = 3810, stack = 1, bind = 2 })
  def(19019, { name = "Thunderfury, Blessed Blade of the Windseeker", quality = 5, ilvl = 80, minLevel = 60, class = 2, sub = 7, equip = "INVTYPE_WEAPON",
    icon = "Interface\\Icons\\INV_Sword_39", sell = 51066, stack = 1, bind = 1, unique = true })
  def(6948, { name = "Hearthstone", quality = 1, ilvl = 1, class = 15, sub = 4, icon = "Interface\\Icons\\INV_Misc_Rune_01", sell = 0, stack = 1, bind = 1, unique = true,
    lines = { "|cff1eff00Use: Returns you to Sandbox Isle. Speak to an Innkeeper in a different place to change your home location.|r" } })

  function __RegisterItem(id, t)
    t.quality, t.ilvl, t.class, t.sub = t.quality or 1, t.ilvl or 1, t.class or 15, t.sub or 0
    t.icon, t.sell, t.stack = t.icon or "Interface\\Icons\\INV_Misc_QuestionMark", t.sell or 0, t.stack or 1
    DB[id] = t
  end
  function __ItemList()
    local out = {}
    for id, it in pairs(DB) do out[#out + 1] = { id = id, name = it.name, quality = it.quality } end
    table.sort(out, function(a, b) return a.name < b.name end)
    return __json(out)
  end

  -- ------------------------------------------------------------ cache
  local cached, loading = {}, {}
  local LOAD_DELAY = 0.15

  local function finishLoad(id)
    loading[id] = nil
    local ok = DB[id] ~= nil
    if ok then cached[id] = true end
    __GameEvent("ITEM_DATA_LOAD_RESULT", id, ok)
    __GameEvent("GET_ITEM_INFO_RECEIVED", id, ok)
  end
  local function request(id)
    if type(id) ~= "number" or cached[id] or loading[id] then return end
    loading[id] = {}
    C_Timer.After(LOAD_DELAY, function()
      local waiting = loading[id]
      finishLoad(id)
      for _, fn in ipairs(waiting or {}) do __safecall(fn) end
    end)
  end
  -- Items the player can see (bags, loot) are known to the client right away.
  function __CacheItem(id) if DB[id] then cached[id] = true end end
  function __IsItemCached(id) return cached[id] == true end
  local function onLoad(id, fn)
    if cached[id] then fn() return end
    if not DB[id] then return end
    request(id)
    table.insert(loading[id], fn)
  end

  -- Accepts an itemID, "item:123…" strings, item links, numeric strings, or the name of a cached item.
  local function resolve(x)
    if type(x) == "number" then return DB[x] and x or nil, x end
    if type(x) ~= "string" then return nil end
    local id = tonumber(string.match(x, "item:(%d+)")) or tonumber(x)
    if id then return DB[id] and id or nil, id end
    local lx = string.lower(x)
    for k, it in pairs(DB) do
      if cached[k] and string.lower(it.name) == lx then return k, k end
    end
  end
  __ResolveItem = resolve

  local function link(id)
    local it = DB[id]
    if not it then return nil end
    local q = ITEM_QUALITY_COLORS[it.quality] or ITEM_QUALITY_COLORS[1]
    return q.hex .. "|Hitem:" .. id .. "::::::::" .. UnitLevel("player") .. ":::::|h[" .. it.name .. "]|h|r"
  end
  __ItemLink = link

  local function info(x)
    local id, wanted = resolve(x)
    if not id then
      if wanted then request(wanted) end
      return nil
    end
    if not cached[id] then request(id) return nil end
    local it = DB[id]
    return it.name, link(id), it.quality, it.ilvl, it.minLevel or 0, classNames[it.class] or "", GetItemSubClassInfo(it.class, it.sub) or "",
      it.stack, it.equip or "", it.icon, it.sell, it.class, it.sub, it.bind or 0, 0, nil, it.class == 7
  end
  local function instant(x)
    local id = resolve(x)
    if not id then return nil end
    local it = DB[id]
    return id, classNames[it.class] or "", GetItemSubClassInfo(it.class, it.sub) or "", it.equip or "", it.icon, it.class, it.sub
  end
  local function cachedField(field)
    return function(x)
      local id = resolve(x)
      if not id then return nil end
      if not cached[id] then request(id) return nil end
      return DB[id][field]
    end
  end

  GetItemInfo = info
  GetItemInfoInstant = instant
  function GetItemIcon(x) local id = resolve(x) return id and DB[id].icon end
  function GetItemCount(x) return __BagItemCount and __BagItemCount((resolve(x))) or 0 end
  function GetDetailedItemLevelInfo(x) local id = resolve(x) if id then return DB[id].ilvl, false, DB[id].ilvl end end
  function IsEquippableItem(x) local id = resolve(x) return id ~= nil and DB[id].equip ~= nil end
  function GetItemSpell() return nil end

  C_Item = C_Item or {}
  C_Item.GetItemInfo = info
  C_Item.GetItemInfoInstant = instant
  C_Item.GetItemNameByID = cachedField("name")
  C_Item.GetItemQualityByID = cachedField("quality")
  C_Item.GetItemIconByID = function(x) return GetItemIcon(x) end
  C_Item.GetItemCount = function(...) return GetItemCount(...) end
  C_Item.GetItemMaxStackSizeByID = function(x) local id = resolve(x) return id and DB[id].stack end
  C_Item.GetDetailedItemLevelInfo = GetDetailedItemLevelInfo
  C_Item.GetItemClassInfo = GetItemClassInfo
  C_Item.GetItemSubClassInfo = GetItemSubClassInfo
  C_Item.GetItemQualityColor = GetItemQualityColor
  C_Item.IsEquippableItem = IsEquippableItem
  C_Item.GetItemSpell = GetItemSpell
  C_Item.DoesItemExistByID = function(x) return (resolve(x)) ~= nil end
  C_Item.IsItemDataCachedByID = function(x) local id = resolve(x) return id ~= nil and cached[id] == true end
  C_Item.RequestLoadItemDataByID = function(x)
    local id, wanted = resolve(x)
    request(id or wanted) -- an unknown ID still answers, with success = false
  end
  C_Item.GetItemLink = function() return nil end

  -- ------------------------------------------------------------ Item mixin
  ItemMixin = {}
  function ItemMixin:SetItemID(id) self.itemID = id end
  function ItemMixin:SetItemLink(l) self.itemLink = l self.itemID = tonumber(string.match(l or "", "item:(%d+)")) end
  function ItemMixin:GetItemID() return self.itemID end
  function ItemMixin:IsItemEmpty() return self.itemID == nil or DB[self.itemID] == nil end
  function ItemMixin:IsItemDataCached() return self.itemID ~= nil and cached[self.itemID] == true end
  function ItemMixin:GetItemLink() return self.itemLink or (cached[self.itemID] and link(self.itemID)) or nil end
  function ItemMixin:GetItemName() return cached[self.itemID] and DB[self.itemID].name or nil end
  function ItemMixin:GetItemIcon() return DB[self.itemID] and DB[self.itemID].icon end
  function ItemMixin:GetItemQuality() return cached[self.itemID] and DB[self.itemID].quality or nil end
  function ItemMixin:GetItemQualityColor() local q = self:GetItemQuality() return q and ITEM_QUALITY_COLORS[q] end
  function ItemMixin:GetCurrentItemLevel() return DB[self.itemID] and DB[self.itemID].ilvl end
  function ItemMixin:ContinueOnItemLoad(fn)
    if self:IsItemEmpty() then return end
    onLoad(self.itemID, fn)
  end
  function ItemMixin:ContinueWithCancelOnItemLoad(fn)
    local cancelled = false
    self:ContinueOnItemLoad(function() if not cancelled then fn() end end)
    return function() cancelled = true end
  end

  Item = Item or {}
  function Item:CreateFromItemID(id) local o = CreateFromMixins(ItemMixin) o:SetItemID(id) return o end
  function Item:CreateFromItemLink(l) local o = CreateFromMixins(ItemMixin) o:SetItemLink(l) return o end
  function Item:CreateFromBagAndSlot(bag, slot)
    local o = CreateFromMixins(ItemMixin)
    o:SetItemID(C_Container and C_Container.GetContainerItemID(bag, slot))
    return o
  end
end
