-- XML (FrameXML-style) loader. Nodes come from the host as { t = tag, a = attrs, c = children, x = text }.

local frameTags = {
  Frame = true, Button = true, CheckButton = true, EditBox = true, Slider = true, StatusBar = true, ScrollFrame = true,
  GameTooltip = true, Cooldown = true, Model = true, PlayerModel = true, DressUpModel = true, ColorSelect = true,
  MessageFrame = true, ScrollingMessageFrame = true, SimpleHTML = true, Minimap = true, MovieFrame = true, TabardModel = true,
  CinematicModel = true, ModelScene = true, OffScreenFrame = true, Browser = true, Checkout = true, FogOfWar = true, QuestPOI = true,
}

local scriptArgs = {
  OnEvent = "self, event", OnClick = "self, button, down", OnUpdate = "self, elapsed", OnValueChanged = "self, value, userInput",
  OnEnter = "self, motion", OnLeave = "self, motion", OnMouseDown = "self, button", OnMouseUp = "self, button",
  OnMouseWheel = "self, delta", OnTextChanged = "self, userInput", OnAttributeChanged = "self, name, value",
  OnKeyDown = "self, key", OnKeyUp = "self, key", OnChar = "self, text", OnDragStart = "self, button", PreClick = "self, button, down",
  PostClick = "self, button, down", OnVerticalScroll = "self, offset", OnHorizontalScroll = "self, offset", OnEditFocusGained = "self",
}

local function dirOf(path) return string.match(path, "^(.*)/[^/]*$") or "" end
local function joinPath(dir, rel)
  rel = string.gsub(rel, "\\", "/")
  local parts = {}
  local full = (dir ~= "" and (dir .. "/") or "") .. rel
  for seg in string.gmatch(full, "[^/]+") do
    if seg == ".." then parts[#parts] = nil elseif seg ~= "." then parts[#parts + 1] = seg end
  end
  return table.concat(parts, "/")
end

local function child(n, tag)
  for _, c in ipairs(n.c or {}) do if c.t == tag then return c end end
end

local function sizeOf(n)
  local a = n.a or {}
  local x, y = tonumber(a.x), tonumber(a.y)
  local d = child(n, "AbsDimension")
  if d then x = tonumber(d.a.x) or x y = tonumber(d.a.y) or y end
  return x, y
end

local function colorOf(n)
  local a = n.a or {}
  return tonumber(a.r) or 0, tonumber(a.g) or 0, tonumber(a.b) or 0, tonumber(a.a) or 1
end

local function parentName(obj)
  local p = S[obj].parent
  return p and S[p].name or ""
end

local function resolveRelName(obj, name)
  if name == "$parent" then return S[obj].parent end
  if string.find(name, "$parent", 1, true) then name = string.gsub(name, "%$parent", parentName(obj)) end
  return _G[name]
end

local function resolveKey(obj, key)
  -- relativeKey="$parent.Foo.Bar"
  local cur = obj
  for seg in string.gmatch(key, "[^.]+") do
    if seg == "$parent" then cur = S[cur] and S[cur].parent else cur = cur and cur[seg] end
  end
  return cur
end

local deferred = {}

local function applyAnchors(obj, n)
  for _, an in ipairs(n.c or {}) do
    if an.t == "Anchor" then
      local a = an.a
      local x, y = tonumber(a.x) or 0, tonumber(a.y) or 0
      local off = child(an, "Offset")
      if off then local ox, oy = sizeOf(off) x, y = ox or x, oy or y end
      local rel
      local pending = false
      if a.relativeKey then rel = resolveKey(obj, a.relativeKey) if not rel then pending = true end
      elseif a.relativeTo then rel = resolveRelName(obj, a.relativeTo) if not rel then pending = true end end
      local function put()
        if a.relativeKey then rel = resolveKey(obj, a.relativeKey) elseif a.relativeTo then rel = resolveRelName(obj, a.relativeTo) end
        obj:SetPoint(a.point or "TOPLEFT", rel, a.relativePoint or a.point or "TOPLEFT", x, y)
      end
      if pending then deferred[#deferred + 1] = put else put() end
    end
  end
end

local function compileScript(handler, text, ctx)
  local args = scriptArgs[handler] or "self"
  local names = {}
  for nm in string.gmatch(args, "[%w_]+") do names[#names + 1] = nm end
  local chunk = "local " .. args .. " = ...\n" .. text
  local fn, err = load(chunk, "@" .. (ctx.file or "xml") .. ":" .. handler)
  if not fn then __log("error", tostring(err)) return nil end
  return fn
end

local function applyScripts(f, n, ctx)
  for _, sc in ipairs(n.c or {}) do
    local h = sc.t
    local a = sc.a or {}
    local fn
    if a["function"] then
      local name = a["function"]
      fn = function(...) local g = _G[name] if g then return g(...) end __log("error", "Missing script function: " .. name) end
    elseif a.method then
      local m = a.method
      fn = function(self, ...) return self[m](self, ...) end
    elseif sc.x and string.find(sc.x, "%S") then
      fn = compileScript(h, sc.x, ctx)
    end
    if fn then
      if a.inherit == "prepend" or a.inherit == "append" then f:HookScript(h, fn) else f:SetScript(h, fn) end
    end
  end
end

local applyRegionContent, applyFrameContent, createFromNode

local function backdropFrom(n)
  local a = n.a or {}
  local t = { bgFile = a.bgFile, edgeFile = a.edgeFile, tile = a.tile == "true", insets = {} }
  for _, c in ipairs(n.c or {}) do
    if c.t == "EdgeSize" then t.edgeSize = tonumber(c.a.val) or tonumber((child(c, "AbsValue") or { a = {} }).a.val)
    elseif c.t == "TileSize" then t.tileSize = tonumber(c.a.val) or tonumber((child(c, "AbsValue") or { a = {} }).a.val)
    elseif c.t == "BackgroundInsets" then
      local ins = child(c, "AbsInset") or c
      t.insets = { left = tonumber(ins.a.left) or 0, right = tonumber(ins.a.right) or 0, top = tonumber(ins.a.top) or 0, bottom = tonumber(ins.a.bottom) or 0 }
    end
  end
  return t
end

function applyRegionContent(r, n, ctx)
  local a = n.a or {}
  local s = S[r]
  if a.inherits then
    for nm in string.gmatch(a.inherits, "[^,%s]+") do
      local fo = _G[nm]
      if s.kind == "fs" and fo and S[fo] and S[fo].font and not xmlTemplates[nm] then r:SetFontObject(fo)
      elseif xmlTemplates[nm] then applyRegionContent(r, xmlTemplates[nm], ctx) end
    end
  end
  if a.file then r:SetTexture(a.file) end
  if a.atlas then r:SetAtlas(a.atlas) end
  if a.alpha then r:SetAlpha(tonumber(a.alpha)) end
  if a.alphaMode then r:SetBlendMode(a.alphaMode) end
  if a.hidden == "true" then s.shown = false end
  if a.desaturated == "true" then r:SetDesaturated(true) end
  if a.text and r.SetText then r:SetText(_G[a.text] or a.text) end
  if a.justifyH then r:SetJustifyH(a.justifyH) end
  if a.justifyV then r:SetJustifyV(a.justifyV) end
  if a.wordwrap == "false" then r:SetWordWrap(false) end
  if a.maxLines then r:SetMaxLines(tonumber(a.maxLines)) end
  if a.parentKey then
    local pf = s.parent
    pf[a.parentKey] = r
  end
  if a.setAllPoints == "true" then r:SetAllPoints() end
  for _, c in ipairs(n.c or {}) do
    local t = c.t
    if t == "Size" then
      local x, y = sizeOf(c)
      if x then r:SetWidth(x) end
      if y then r:SetHeight(y) end
    elseif t == "Color" then
      local cr, cg, cb, ca = colorOf(c)
      if s.kind == "fs" then r:SetTextColor(cr, cg, cb, ca) else r:SetColorTexture(cr, cg, cb, ca) end
    elseif t == "TexCoords" then
      local rect = child(c, "Rect")
      if rect then
        local ra = rect.a
        r:SetTexCoord(tonumber(ra.ULx) or 0, tonumber(ra.ULy) or 0, tonumber(ra.LLx) or 0, tonumber(ra.LLy) or 1,
          tonumber(ra.URx) or 1, tonumber(ra.URy) or 0, tonumber(ra.LRx) or 1, tonumber(ra.LRy) or 1)
      else
        local ca = c.a
        r:SetTexCoord(tonumber(ca.left) or 0, tonumber(ca.right) or 1, tonumber(ca.top) or 0, tonumber(ca.bottom) or 1)
      end
    elseif t == "Shadow" then
      local off = child(c, "Offset")
      if off then local ox, oy = sizeOf(off) r:SetShadowOffset(ox or 0, oy or 0) end
      local col = child(c, "Color")
      if col then r:SetShadowColor(colorOf(col)) end
    elseif t == "FontHeight" then
      local p, _, f = r:GetFont()
      r:SetFont(p, tonumber(c.a.val) or 12, f)
    elseif t == "Gradient" then
      local mn, mx = child(c, "MinColor"), child(c, "MaxColor")
      if mn and mx and r.SetGradient then
        local r1, g1, b1, a1 = colorOf(mn)
        local r2, g2, b2, a2 = colorOf(mx)
        r:SetGradientAlpha(c.a.orientation or "VERTICAL", r1, g1, b1, a1, r2, g2, b2, a2)
      end
    elseif t == "Anchors" then
      applyAnchors(r, c)
    end
  end
end

local function createRegion(n, frame, layer, ctx)
  local a = n.a or {}
  if a.virtual == "true" then
    xmlTemplates[a.name] = n
    return
  end
  local r
  if n.t == "Texture" then r = frame:CreateTexture(a.name, layer, nil, tonumber(a.textureSubLevel) or 0)
  else r = frame:CreateFontString(a.name, layer) end
  applyRegionContent(r, n, ctx)
  return r
end

local function applyLayers(f, n, ctx)
  for _, layers in ipairs(n.c or {}) do
    if layers.t == "Layer" then
      local lvl = layers.a and layers.a.level or "ARTWORK"
      for _, rn in ipairs(layers.c or {}) do
        if rn.t == "Texture" or rn.t == "FontString" then createRegion(rn, f, lvl, ctx) end
      end
    end
  end
end

local buttonTexTags = {
  NormalTexture = "SetNormalTexture", PushedTexture = "SetPushedTexture", HighlightTexture = "SetHighlightTexture",
  DisabledTexture = "SetDisabledTexture", CheckedTexture = "SetCheckedTexture", ThumbTexture = "SetThumbTexture",
}

function applyFrameContent(f, n, ctx)
  local a = n.a or {}
  local s = S[f]
  if a.mixin then for nm in string.gmatch(a.mixin, "[^,%s]+") do if _G[nm] then Mixin(f, _G[nm]) end end end
  if a.secureMixin then for nm in string.gmatch(a.secureMixin, "[^,%s]+") do if _G[nm] then Mixin(f, _G[nm]) end end end
  if a.parentKey then local p = s.parent if p then p[a.parentKey] = f end end
  if a.enableMouse then s.mouse = a.enableMouse == "true" end
  if a.enableMouseWheel then s.wheel = a.enableMouseWheel == "true" end
  if a.enableKeyboard then s.keyboard = a.enableKeyboard == "true" end
  if a.movable then s.movable = a.movable == "true" end
  if a.resizable then s.resizable = a.resizable == "true" end
  if a.toplevel then s.toplevel = a.toplevel == "true" end
  if a.clampedToScreen then s.clamped = a.clampedToScreen == "true" end
  if a.clipChildren then s.clip = a.clipChildren == "true" end
  if a.frameStrata then f:SetFrameStrata(a.frameStrata) end
  if a.frameLevel then f:SetFrameLevel(tonumber(a.frameLevel)) end
  if a.alpha then f:SetAlpha(tonumber(a.alpha)) end
  if a.scale then f:SetScale(tonumber(a.scale)) end
  if a.id then s.frameId = tonumber(a.id) end
  if a.hidden then s.shown = a.hidden ~= "true" end
  if a.setAllPoints == "true" then f:SetAllPoints() end
  if a.text and f.SetText then f:SetText(_G[a.text] or a.text) end
  if a.autoFocus and f.SetAutoFocus then f:SetAutoFocus(a.autoFocus == "true") end
  if a.multiLine and f.SetMultiLine then f:SetMultiLine(a.multiLine == "true") end
  if a.orientation and f.SetOrientation then f:SetOrientation(a.orientation) end
  if a.minValue and f.SetMinMaxValues then f:SetMinMaxValues(tonumber(a.minValue), tonumber(a.maxValue or 100)) end
  if a.valueStep and f.SetValueStep then f:SetValueStep(tonumber(a.valueStep)) end
  if a.defaultValue and f.SetValue then f:SetValue(tonumber(a.defaultValue)) end
  if a.letters and f.SetMaxLetters then f:SetMaxLetters(tonumber(a.letters)) end

  for _, c in ipairs(n.c or {}) do
    local t = c.t
    if t == "Size" then
      local x, y = sizeOf(c)
      if x then f:SetWidth(x) end
      if y then f:SetHeight(y) end
    elseif t == "Anchors" then applyAnchors(f, c)
    elseif t == "Layers" then applyLayers(f, c, ctx)
    elseif t == "Frames" then
      for _, fn in ipairs(c.c or {}) do createFromNode(fn, f, ctx) end
    elseif t == "Scripts" then applyScripts(f, c, ctx)
    elseif t == "Attributes" then
      for _, at in ipairs(c.c or {}) do
        if at.t == "Attribute" then
          local v = at.a.value
          if at.a.type == "number" then v = tonumber(v) elseif at.a.type == "boolean" then v = v == "true" end
          f:SetAttribute(at.a.name, v)
        end
      end
    elseif t == "KeyValues" then
      for _, kv in ipairs(c.c or {}) do
        if kv.t == "KeyValue" then
          local v = kv.a.value
          local ty = kv.a.type
          if ty == "number" then v = tonumber(v) elseif ty == "boolean" then v = v == "true" elseif ty == "global" then v = _G[v] end
          f[kv.a.key] = v
        end
      end
    elseif t == "Backdrop" then
      f:SetBackdrop(backdropFrom(c))
      local col, bcol = child(c, "Color"), child(c, "BorderColor")
      if col then f:SetBackdropColor(colorOf(col)) end
      if bcol then f:SetBackdropBorderColor(colorOf(bcol)) end
    elseif t == "HitRectInsets" then
      f:SetHitRectInsets(tonumber(c.a.left) or 0, tonumber(c.a.right) or 0, tonumber(c.a.top) or 0, tonumber(c.a.bottom) or 0)
    elseif buttonTexTags[t] then
      local tex = f[buttonTexTags[t]](f, c.a.file or "")
      if tex then applyRegionContent(tex, c, ctx) end
    elseif t == "ButtonText" then
      local fs = f:GetFontString()
      applyRegionContent(fs, c, ctx)
      if c.a.name then _G[string.gsub(c.a.name, "%$parent", S[f].name or "")] = fs end
      if #S[fs].points == 1 and c.c then S[fs].points = S[fs].points end
    elseif t == "NormalFont" then f:SetNormalFontObject(_G[c.a.style])
    elseif t == "HighlightFont" then f:SetHighlightFontObject(_G[c.a.style])
    elseif t == "DisabledFont" then f:SetDisabledFontObject(_G[c.a.style])
    elseif t == "BarTexture" then f:SetStatusBarTexture(c.a.file)
    elseif t == "BarColor" then f:SetStatusBarColor(colorOf(c))
    elseif t == "ScrollChild" then
      local cn = c.c and c.c[1]
      if cn then
        local ch = createFromNode(cn, f, ctx)
        if ch and f.SetScrollChild then f:SetScrollChild(ch) end
      end
    elseif t == "Animations" or t == "TitleRegion" or t == "ResizeBounds" or t == "Frames" then
      -- not supported in XML yet
    end
  end
end

function __ApplyXMLTemplate(frame, node, ctx)
  ctx = ctx or { file = "template" }
  local a = node.a or {}
  if a.inherits then __applyTemplates(frame, a.inherits) end
  applyFrameContent(frame, node, ctx)
end

function createFromNode(n, parent, ctx)
  local a = n.a or {}
  if a.virtual == "true" then
    xmlTemplates[a.name] = n
    return nil
  end
  local typ = n.t
  local pr = parent
  if a.parent then pr = _G[a.parent] or parent end
  local f = CreateFrame(typ, a.name, pr, nil, nil, true)
  if a.inherits then __applyTemplates(f, a.inherits) end
  applyFrameContent(f, n, ctx)
  fire(f, "OnLoad")
  return f
end

local function applyFontNode(n)
  local a = n.a or {}
  local f = a.name and CreateFont(a.name) or CreateFont()
  S[f].name = a.name
  if a.inherits and _G[a.inherits] then f:SetFontObject(_G[a.inherits]) end
  local flags = ""
  if a.outline == "NORMAL" then flags = "OUTLINE" elseif a.outline == "THICK" then flags = "THICKOUTLINE" end
  if a.font or a.height or a.outline then
    local p, sz, fl = f:GetFont()
    f:SetFont(a.font or p, tonumber(a.height) or sz, (a.outline and flags) or fl)
  end
  for _, c in ipairs(n.c or {}) do
    if c.t == "FontHeight" then local p, _, fl = f:GetFont() f:SetFont(p, tonumber(c.a.val) or 12, fl)
    elseif c.t == "Color" then f:SetTextColor(colorOf(c))
    elseif c.t == "Shadow" then
      local off, col = child(c, "Offset"), child(c, "Color")
      if off then local ox, oy = sizeOf(off) f:SetShadowOffset(ox or 0, oy or 0) end
      if col then f:SetShadowColor(colorOf(col)) end
    end
  end
  if a.virtual == "true" then xmlTemplates[a.name] = nil end
end

local function processNodes(nodes, ctx)
  for _, n in ipairs(nodes or {}) do
    local t = n.t
    if t == "Script" then
      local file = n.a and n.a.file
      if file then
        local path = joinPath(dirOf(ctx.file), file)
        __RunFile(ctx.addon, path)
      elseif n.x then
        local fn, err = load(n.x, "@" .. ctx.file .. ":Script")
        if fn then __safecall(fn, ctx.addon, __addons[ctx.addon].ns) else __log("error", tostring(err)) end
      end
    elseif t == "Include" then
      local path = joinPath(dirOf(ctx.file), n.a.file)
      __RunFile(ctx.addon, path)
    elseif t == "Font" then applyFontNode(n)
    elseif t == "Texture" or t == "FontString" then
      if n.a and n.a.virtual == "true" and n.a.name then xmlTemplates[n.a.name] = n end
    elseif frameTags[t] then
      local parent = UIParent
      local ok, err = pcall(createFromNode, n, parent, ctx)
      if not ok then __log("error", ctx.file .. ": " .. tostring(err)) end
    elseif t == "Ui" then processNodes(n.c, ctx)
    end
  end
end

function __RunXML(addon, path, json)
  local root = __unjson(json)
  if not root then __log("error", "Could not parse XML: " .. path) return end
  local ctx = { addon = addon, file = path }
  processNodes(root.t == "Ui" and root.c or { root }, ctx)
  local list = deferred
  deferred = {}
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn)
    if not ok then __log("warn", path .. ": unresolved anchor target (" .. tostring(err) .. ")") end
  end
end
