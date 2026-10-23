-- Frame / Region object model, layout, and the render snapshot.

local floor, abs, max, min = math.floor, math.abs, math.max, math.min

local S = setmetatable({}, { __mode = "k" }) -- object -> private state
local allObjs = {}
local nextId = 0
local ver, lver = 0, 0
local SW, SH = 1280, 720

local function dirty() ver = ver + 1 end
local function ldirty() ver = ver + 1; lver = lver + 1 end
function __Ver() return ver end
function __Screen() return SW, SH end

---------------------------------------------------------------------------
-- Class scaffolding
---------------------------------------------------------------------------
local warned = {}
local noopPrefixes = { "Set", "Get", "Is", "Has", "Enable", "Disable", "Register", "Unregister", "Can", "Clear", "Add", "Remove",
  "Update", "Start", "Stop", "Freeze", "Lock", "Unlock", "Raise", "Lower", "Show", "Hide", "Create", "Click", "Pause", "Resume" }
local function looksLikeMethod(k)
  if type(k) ~= "string" then return false end
  for _, p in ipairs(noopPrefixes) do
    if string.sub(k, 1, #p) == p and string.find(string.sub(k, #p + 1, #p + 1), "%u") then return true end
  end
  return false
end

local Object = {}
setmetatable(Object, { __index = function(_, k)
  if looksLikeMethod(k) then
    if not warned[k] then
      warned[k] = true
      __log("warn", "Unimplemented widget API ignored: :" .. k .. "()")
    end
    return function() end
  end
end })

local function newClass(parent)
  local c = {}
  c.__index = c
  setmetatable(c, { __index = parent or Object })
  return c
end

local Region = newClass()
local Texture = newClass(Region)
local FontString = newClass(Region)
local Frame = newClass(Region)
local Button = newClass(Frame)
local CheckButton = newClass(Button)
local EditBox = newClass(Frame)
local Slider = newClass(Frame)
local StatusBar = newClass(Frame)
local ScrollFrame = newClass(Frame)
local Tooltip = newClass(Frame)
local MessageFrame = newClass(Frame)
local FontObj = newClass()
local AnimGroup = newClass()
local Anim = newClass()

local frameClasses = {
  Frame = Frame, Button = Button, CheckButton = CheckButton, EditBox = EditBox, Slider = Slider, StatusBar = StatusBar,
  ScrollFrame = ScrollFrame, GameTooltip = Tooltip, ScrollingMessageFrame = MessageFrame, MessageFrame = MessageFrame,
}
local strataOrder = { BACKGROUND = 0, LOW = 1, MEDIUM = 2, HIGH = 3, DIALOG = 4, FULLSCREEN = 5, FULLSCREEN_DIALOG = 6, TOOLTIP = 7 }
local layerOrder = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local function newState(o, kind, typeName, parent)
  nextId = nextId + 1
  local s = {
    id = nextId, kind = kind, type = typeName, parent = parent, points = {}, alpha = 1, shown = true, scale = 1,
    children = {}, regions = {}, scripts = {}, hooks = {}, events = {}, attrs = {},
  }
  S[o] = s
  allObjs[#allObjs + 1] = o
  return s
end

local function resolveRel(r)
  if type(r) == "string" then return _G[r] end
  return r
end

local function nameOf(o) return S[o].name end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local pointFactors = {
  TOPLEFT = { 0, 1 }, TOP = { .5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, .5 }, CENTER = { .5, .5 }, RIGHT = { 1, .5 },
  BOTTOMLEFT = { 0, 0 }, BOTTOM = { .5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local function effScale(o)
  local s = S[o]
  local sc = s.scale * (s.ascale or 1)
  if s.parent and not s.ignoreScale then sc = sc * effScale(s.parent) end
  return sc
end

local function fontOf(s)
  local f = s.font
  local obj = s.fontObj
  local path, size, flags = f and f[1], f and f[2], f and f[3]
  if obj then
    local os = S[obj]
    if not path then path = os.font[1] end
    if not size then size = os.font[2] end
    if not flags then flags = os.font[3] end
  end
  return path or "Fonts\\FRIZQT__.TTF", size or 12, flags or ""
end

local getRect

local function textMetrics(o, s, es, fixedW)
  local path, size, flags = fontOf(s)
  local text = s.text or ""
  local w = __measureW(text, path, size, flags) * es
  local wrapW = fixedW and (fixedW / es) or nil
  local h = __measureH(text, path, size, flags, (s.wrap ~= false and wrapW) or 0) * es
  if s.maxLines and s.maxLines > 0 then h = min(h, s.maxLines * size * 1.2 * es) end
  return w, h
end

function getRect(o)
  local s = S[o]
  if s.isRoot then return { 0, 0, SW, SH } end
  if s.rcv == lver then return s.rc end
  if s.busy then return nil end
  s.busy = true
  local es = effScale(o)
  local pts = s.points
  local result
  if #pts > 0 then
    local l, r, cx, b, t, cy
    local ok = true
    for _, pt in ipairs(pts) do
      local rel = pt.rel or s.parent or UIParent
      local rr = getRect(rel)
      if not rr then ok = false break end
      local rf = pointFactors[pt.relPoint]
      local ax, ay = rr[1] + rr[3] * rf[1], rr[2] + rr[4] * rf[2]
      local x, y = ax + pt.x * es, ay + pt.y * es
      local f = pointFactors[pt.point]
      if f[1] == 0 then l = x elseif f[1] == 1 then r = x else cx = x end
      if f[2] == 0 then b = y elseif f[2] == 1 then t = y else cy = y end
    end
    if ok then
      local w, h
      local mw, mh
      if s.kind == "fs" then
        local fw = (l and r) and (r - l) or (s.w and s.w * es) or nil
        mw, mh = textMetrics(o, s, es, fw)
      end
      if l and r then w = r - l elseif s.w then w = s.w * es else w = mw or 0 end
      if b and t then h = t - b elseif s.h then h = s.h * es else h = mh or 0 end
      local left = l or (r and r - w) or (cx and cx - w / 2) or 0
      local bottom = b or (t and t - h) or (cy and cy - h / 2) or 0
      result = { left + (s.adx or 0) * es, bottom + (s.ady or 0) * es, w, h }
    end
  end
  s.busy = false
  s.rc, s.rcv = result, lver
  return result
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------
local function roleVisible(s)
  local role = s.role
  if not role then return true end
  local ps = S[s.parent]
  local bt = ps.btex or {}
  if role == "normal" then
    if ps.disabled and bt.disabled then return false end
    if ps.down and bt.pushed then return false end
    return true
  elseif role == "pushed" then return (ps.down and not ps.disabled) and true or false
  elseif role == "disabled" then return ps.disabled and true or false
  elseif role == "highlight" then return ((ps.hover or ps.lockHL) and not ps.disabled) and true or false
  elseif role == "checked" then return ps.checked and true or false
  end
  return true
end

local function isShown(o) return S[o].shown end
local function isVisible(o)
  local s = S[o]
  if not s.shown then return false end
  if s.parent then return isVisible(s.parent) end
  return true
end

local fire

local function propagateShow(o, show)
  local s = S[o]
  if s.kind == "frame" then
    fire(o, show and "OnShow" or "OnHide")
    for _, c in ipairs(s.children) do
      if S[c].shown then propagateShow(c, show) end
    end
  end
end

---------------------------------------------------------------------------
-- Scripts & events
---------------------------------------------------------------------------
local eventRegs = {} -- event -> { objects }

function fire(o, name, ...)
  local s = S[o]
  local f = s.scripts[name]
  if f then __safecall(f, o, ...) end
  local hs = s.hooks[name]
  if hs then for _, h in ipairs(hs) do __safecall(h, o, ...) end end
end

function __FireEvent(event, ...)
  local list = eventRegs[event]
  if list then
    local copy = {}
    for i, o in ipairs(list) do copy[i] = o end
    for _, o in ipairs(copy) do
      local s = S[o]
      if s.events[event] then
        local filter = s.unitFilter and s.unitFilter[event]
        local pass = true
        if filter then
          pass = false
          local u = ...
          for _, fu in ipairs(filter) do if fu == u then pass = true end end
        end
        if pass then fire(o, "OnEvent", event, ...) end
      end
    end
  end
  local all = eventRegs["*"]
  if all then for _, o in ipairs(all) do fire(o, "OnEvent", event, ...) end end
  if EventRegistry and EventRegistry.TriggerEvent then EventRegistry:TriggerEvent(event, ...) end
end

local function regEvent(o, ev)
  local s = S[o]
  s.events[ev] = true
  local list = eventRegs[ev]
  if not list then list = {}; eventRegs[ev] = list end
  for _, x in ipairs(list) do if x == o then return end end
  list[#list + 1] = o
end
local function unregEvent(o, ev)
  S[o].events[ev] = nil
  local list = eventRegs[ev]
  if list then for i, x in ipairs(list) do if x == o then table.remove(list, i) break end end end
end

---------------------------------------------------------------------------
-- Region (shared by frames, textures, fontstrings)
---------------------------------------------------------------------------
function Region:GetName() return S[self].name end
function Region:GetObjectType() return S[self].type end
function Region:IsObjectType(t)
  local ty = S[self].type
  if ty == t then return true end
  local chain = {
    CheckButton = { Button = 1, Frame = 1, Region = 1 }, Button = { Frame = 1, Region = 1 }, Frame = { Region = 1 },
    EditBox = { Frame = 1, Region = 1 }, Slider = { Frame = 1, Region = 1 }, StatusBar = { Frame = 1, Region = 1 },
    ScrollFrame = { Frame = 1, Region = 1 }, GameTooltip = { Frame = 1, Region = 1 }, Texture = { Region = 1 }, FontString = { Region = 1 },
  }
  return chain[ty] and chain[ty][t] and true or false
end
function Region:GetParent() return S[self].parent end
function Region:GetDebugName() return S[self].name or tostring(self) end
function Region:IsForbidden() return false end
function Region:IsProtected() return false, false end

function Region:SetParent(p)
  local s = S[self]
  local old = s.parent
  if old == p then return end
  if old then
    local list = (s.kind == "frame") and S[old].children or S[old].regions
    for i, x in ipairs(list) do if x == self then table.remove(list, i) break end end
  end
  s.parent = p
  if p then
    local list = (s.kind == "frame") and S[p].children or S[p].regions
    list[#list + 1] = self
  end
  ldirty()
end

function Region:SetPoint(point, rel, relPoint, x, y)
  local s = S[self]
  point = point and string.upper(point) or "TOPLEFT"
  if not pointFactors[point] then error("Unknown anchor point: " .. tostring(point), 2) end
  if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil
  elseif type(relPoint) == "number" then x, y, relPoint = relPoint, x, nil end
  rel = resolveRel(rel)
  relPoint = relPoint and string.upper(relPoint) or point
  if not pointFactors[relPoint] then error("Unknown anchor point: " .. tostring(relPoint), 2) end
  local entry = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
  for i, p in ipairs(s.points) do
    if p.point == point then s.points[i] = entry ldirty() return end
  end
  s.points[#s.points + 1] = entry
  ldirty()
end
function Region:SetAllPoints(rel)
  if rel == true or rel == nil then rel = nil else rel = resolveRel(rel) end
  self:ClearAllPoints()
  self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
  self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end
function Region:ClearAllPoints() S[self].points = {} ldirty() end
function Region:ClearPoint(p) local pts = S[self].points for i, v in ipairs(pts) do if v.point == p then table.remove(pts, i) break end end ldirty() end
function Region:GetNumPoints() return #S[self].points end
function Region:GetPoint(i)
  local p = S[self].points[i or 1]
  if not p then return end
  return p.point, p.rel or S[self].parent, p.relPoint, p.x, p.y
end
function Region:SetSize(w, h) local s = S[self] s.w, s.h = w, h ldirty() end
function Region:SetWidth(w) S[self].w = w ldirty() end
function Region:SetHeight(h) S[self].h = h ldirty() end
function Region:GetWidth()
  local s = S[self]
  if s.w and #s.points < 2 then return s.w end
  local r = getRect(self)
  return r and r[3] / effScale(self) or (s.w or 0)
end
function Region:GetHeight()
  local s = S[self]
  if s.h and #s.points < 2 then return s.h end
  local r = getRect(self)
  return r and r[4] / effScale(self) or (s.h or 0)
end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetLeft() local r = getRect(self) return r and r[1] / effScale(self) end
function Region:GetBottom() local r = getRect(self) return r and r[2] / effScale(self) end
function Region:GetRight() local r = getRect(self) return r and (r[1] + r[3]) / effScale(self) end
function Region:GetTop() local r = getRect(self) return r and (r[2] + r[4]) / effScale(self) end
function Region:GetCenter() local r = getRect(self) if not r then return end local es = effScale(self) return (r[1] + r[3] / 2) / es, (r[2] + r[4] / 2) / es end
function Region:GetRect() local r = getRect(self) if not r then return end local es = effScale(self) return r[1] / es, r[2] / es, r[3] / es, r[4] / es end
function Region:GetScaledRect() local r = getRect(self) if not r then return end return r[1], r[2], r[3], r[4] end
function Region:IsRectValid() return getRect(self) ~= nil end

function Region:SetAlpha(a) S[self].alpha = a dirty() end
function Region:GetAlpha() return S[self].alpha end
function Region:GetEffectiveAlpha()
  local a, o = 1, self
  while o do local s = S[o] a = a * s.alpha o = (not s.ignoreAlpha) and s.parent or nil end
  return a
end
function Region:SetIgnoreParentAlpha(b) S[self].ignoreAlpha = b dirty() end
function Region:SetIgnoreParentScale(b) S[self].ignoreScale = b ldirty() end
function Region:SetScale(sc) S[self].scale = sc ldirty() end
function Region:GetScale() return S[self].scale end
function Region:GetEffectiveScale() return effScale(self) end

function Region:Show()
  local s = S[self]
  if s.shown then return end
  s.shown = true
  dirty()
  if s.kind == "frame" and (not s.parent or isVisible(s.parent)) then propagateShow(self, true) end
end
function Region:Hide()
  local s = S[self]
  if not s.shown then return end
  local wasVisible = isVisible(self)
  s.shown = false
  dirty()
  if s.kind == "frame" and wasVisible then propagateShow(self, false) end
end
function Region:SetShown(b) if b then self:Show() else self:Hide() end end
function Region:IsShown() return S[self].shown end
function Region:IsVisible() return isVisible(self) end
function Region:SetHitRectInsets(l, r, t, b) S[self].hit = { l or 0, r or 0, t or 0, b or 0 } end
function Region:GetHitRectInsets() local h = S[self].hit or { 0, 0, 0, 0 } return h[1], h[2], h[3], h[4] end
function Region:IsMouseOver()
  local r = getRect(self)
  if not r then return false end
  local cx, cy = __cursor.x, __cursor.y
  return cx >= r[1] and cx <= r[1] + r[3] and cy >= r[2] and cy <= r[2] + r[4]
end
function Region:SetDrawLayer(layer, sub) local s = S[self] s.layer = layer or s.layer s.sub = sub or 0 dirty() end
function Region:GetDrawLayer() local s = S[self] return s.layer or "ARTWORK", s.sub or 0 end
function Region:SetFrameStrata() end

__cursor = { x = 0, y = 0 }

---------------------------------------------------------------------------
-- Animations (Alpha / Translation / Scale)
---------------------------------------------------------------------------
local playing = {}
local function smooth(kind, p)
  if kind == "IN" then return p * p
  elseif kind == "OUT" then return 1 - (1 - p) * (1 - p)
  elseif kind == "IN_OUT" then return p < .5 and 2 * p * p or 1 - 2 * (1 - p) * (1 - p) end
  return p
end

function Region:CreateAnimationGroup(name)
  local g = setmetatable({}, AnimGroup)
  g._ = { owner = self, anims = {}, scripts = {}, loop = "NONE", t = 0, playing = false, name = name }
  if name then _G[name] = g end
  return g
end
function AnimGroup:CreateAnimation(typ, name)
  local a = setmetatable({}, Anim)
  a._ = { group = self, type = string.upper(typ or "ALPHA"), dur = 0, order = 1, delay = 0, endDelay = 0, scripts = {} }
  table.insert(self._.anims, a)
  if name then _G[name] = a end
  return a
end
function AnimGroup:GetAnimations() return unpack(self._.anims) end
function AnimGroup:GetParent() return self._.owner end
function AnimGroup:SetLooping(l) self._.loop = l end
function AnimGroup:GetLooping() return self._.loop end
function AnimGroup:SetToFinalAlpha(b) self._.finalAlpha = b end
function AnimGroup:SetScript(n, f) self._.scripts[n] = f end
function AnimGroup:GetScript(n) return self._.scripts[n] end
function AnimGroup:HookScript(n, f)
  local old = self._.scripts[n]
  self._.scripts[n] = function(...) if old then old(...) end f(...) end
end
function AnimGroup:IsPlaying() return self._.playing end
function AnimGroup:IsDone() return not self._.playing end
function AnimGroup:IsPaused() return false end
local function resetEffects(g)
  for _, a in ipairs(g._.anims) do
    local tgt = a._.target or g._.owner
    local ts = S[tgt]
    if ts then
      if a._.type == "ALPHA" then ts.animAlpha = nil elseif a._.type == "TRANSLATION" then ts.adx, ts.ady = nil, nil ldirty() elseif a._.type == "SCALE" then ts.ascale = nil ldirty() end
    end
  end
end
function AnimGroup:Play()
  local g = self._
  if g.playing then return end
  g.playing, g.t = true, 0
  g.baseAlpha = {}
  for i, a in ipairs(g.anims) do
    local tgt = a._.target or g.owner
    g.baseAlpha[i] = S[tgt] and S[tgt].alpha
  end
  playing[#playing + 1] = self
  if g.scripts.OnPlay then __safecall(g.scripts.OnPlay, self) end
end
function AnimGroup:Stop()
  local g = self._
  if not g.playing then return end
  g.playing = false
  resetEffects(self)
  dirty()
  if g.scripts.OnStop then __safecall(g.scripts.OnStop, self) end
end
AnimGroup.Pause = AnimGroup.Stop
function AnimGroup:Finish()
  local g = self._
  g.t = 1e9
end
for _, n in ipairs({ "SetDuration", "SetOrder", "SetSmoothing", "SetStartDelay", "SetEndDelay" }) do
  local key = ({ SetDuration = "dur", SetOrder = "order", SetSmoothing = "smooth", SetStartDelay = "delay", SetEndDelay = "endDelay" })[n]
  Anim[n] = function(self, v) self._[key] = v end
  Anim["Get" .. string.sub(n, 4)] = function(self) return self._[key] end
end
function Anim:SetFromAlpha(v) self._.from = v end
function Anim:SetToAlpha(v) self._.to = v end
function Anim:SetChange(v) self._.change = v end
function Anim:SetOffset(x, y) self._.ox, self._.oy = x, y end
function Anim:SetScaleFrom(x, y) self._.sfx, self._.sfy = x, y end
function Anim:SetScaleTo(x, y) self._.stx, self._.sty = x, y end
function Anim:SetScale(x, y) self._.stx, self._.sty = x, y end
function Anim:SetTarget(t) self._.target = resolveRel(t) end
function Anim:SetScript(n, f) self._.scripts[n] = f end
function Anim:GetScript(n) return self._.scripts[n] end
function Anim:GetParent() return self._.group end
function Anim:GetRegionParent() return self._.group._.owner end
function Anim:GetOrder() return self._.order end

local function applyAnim(g, i, a, p)
  local am = a._
  local tgt = am.target or g._.owner
  local ts = S[tgt]
  if not ts then return end
  p = smooth(am.smooth, p)
  if am.type == "ALPHA" then
    local base = g._.baseAlpha[i] or 1
    local v
    if am.to ~= nil then v = (am.from or base) + (am.to - (am.from or base)) * p
    else v = base + (am.change or 0) * p end
    ts.animAlpha = max(0, min(1, v))
    dirty()
  elseif am.type == "TRANSLATION" then
    ts.adx, ts.ady = (am.ox or 0) * p, (am.oy or 0) * p
    ldirty()
  elseif am.type == "SCALE" then
    local fx, tx = am.sfx or 1, am.stx or 1
    ts.ascale = fx + (tx - fx) * p
    ldirty()
  end
end

local function runAnimations(dt)
  local i = 1
  while i <= #playing do
    local grp = playing[i]
    local g = grp._
    if not g.playing then
      table.remove(playing, i)
    else
      g.t = g.t + dt
      -- group by order
      local orders, maxOrder = {}, 0
      for idx, a in ipairs(g.anims) do
        local o = a._.order
        orders[o] = orders[o] or { dur = 0, items = {} }
        local total = a._.delay + a._.dur + a._.endDelay
        orders[o].dur = max(orders[o].dur, total)
        orders[o].items[#orders[o].items + 1] = { idx, a }
        maxOrder = max(maxOrder, o)
      end
      local start, finished = 0, true
      for o = 1, maxOrder do
        local od = orders[o]
        if od then
          local local_t = g.t - start
          if local_t < 0 then finished = false break end
          for _, it in ipairs(od.items) do
            local a = it[2]
            local p = a._.dur > 0 and (local_t - a._.delay) / a._.dur or 1
            applyAnim(grp, it[1], a, max(0, min(1, p)))
          end
          if local_t < od.dur then finished = false break end
          start = start + od.dur
        end
      end
      if finished then
        if g.loop == "REPEAT" then
          g.t = g.t - start
          if g.scripts.OnLoop then __safecall(g.scripts.OnLoop, grp) end
        else
          g.playing = false
          local finalA = g.finalAlpha
          local ownerS = S[g.owner]
          local lastAlpha = ownerS and ownerS.animAlpha
          resetEffects(grp)
          if finalA and lastAlpha then ownerS.alpha = lastAlpha end
          dirty()
          if g.scripts.OnFinished then __safecall(g.scripts.OnFinished, grp, false) end
          table.remove(playing, i)
          i = i - 1
        end
      end
      i = i + 1
    end
  end
end

---------------------------------------------------------------------------
-- Texture
---------------------------------------------------------------------------
function Texture:SetTexture(a, b, c, d)
  local s = S[self]
  if type(a) == "number" and type(b) == "number" then
    s.col = { a, b, c or 0, d or 1 }
    s.tex = nil
  else
    s.tex = a
    s.col = nil
    s.atlas = nil
  end
  dirty()
end
function Texture:GetTexture() return S[self].tex end
function Texture:SetColorTexture(r, g, b, a) local s = S[self] s.col = { r, g, b, a or 1 } s.tex = nil s.atlas = nil dirty() end
function Texture:SetAtlas(name) local s = S[self] s.atlas = name s.tex = nil s.col = nil dirty() end
function Texture:GetAtlas() return S[self].atlas end
function Texture:SetVertexColor(r, g, b, a) S[self].vc = { r, g, b, a or 1 } dirty() end
function Texture:GetVertexColor() local c = S[self].vc or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function Texture:SetTexCoord(a, b, c, d, e, f, g, h)
  if e then S[self].tc = { a, b, c, d, e, f, g, h } else S[self].tc = { a, b, c, d } end
  dirty()
end
function Texture:GetTexCoord() local t = S[self].tc or { 0, 1, 0, 1 } return unpack(t) end
function Texture:SetBlendMode(m) S[self].blend = m dirty() end
function Texture:GetBlendMode() return S[self].blend or "BLEND" end
function Texture:SetDesaturated(b) S[self].desat = b dirty() end
function Texture:IsDesaturated() return S[self].desat or false end
function Texture:SetRotation(r) S[self].rot = r dirty() end
function Texture:SetHorizTile(b) S[self].htile = b dirty() end
function Texture:SetVertTile(b) S[self].vtile = b dirty() end
function Texture:SetGradient(orient, a, b, c, d, e, f)
  local mn, mx
  if type(a) == "table" then mn, mx = { a.r, a.g, a.b, a.a or 1 }, { b.r, b.g, b.b, b.a or 1 }
  else mn, mx = { a, b, c, 1 }, { d, e, f, 1 } end
  S[self].grad = { string.upper(orient), mn, mx }
  dirty()
end
function Texture:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
  S[self].grad = { string.upper(orient), { r1, g1, b1, a1 }, { r2, g2, b2, a2 } }
  dirty()
end
function Texture:GetNumMaskTextures() return 0 end

---------------------------------------------------------------------------
-- Fonts / FontString
---------------------------------------------------------------------------
function CreateFont(name)
  local o = setmetatable({}, FontObj)
  local s = { font = { "Fonts\\FRIZQT__.TTF", 12, "" }, color = { 1, 1, 1, 1 }, jh = "CENTER", jv = "MIDDLE" }
  S[o] = s
  if name then _G[name] = o end
  return o
end
function FontObj:SetFont(path, size, flags) local s = S[self] s.font = { path, size, flags or "" } dirty() end
function FontObj:GetFont() local f = S[self].font return f[1], f[2], f[3] end
function FontObj:SetTextColor(r, g, b, a) S[self].color = { r, g, b, a or 1 } dirty() end
function FontObj:GetTextColor() local c = S[self].color return c[1], c[2], c[3], c[4] end
function FontObj:SetFontObject(o) local os = S[resolveRel(o)] if os then S[self].font = { os.font[1], os.font[2], os.font[3] } S[self].color = os.color end end
function FontObj:SetJustifyH(j) S[self].jh = j end
function FontObj:SetJustifyV(j) S[self].jv = j end
function FontObj:SetShadowColor(r, g, b, a) S[self].shadowColor = { r, g, b, a or 1 } end
function FontObj:SetShadowOffset(x, y) S[self].shadowOffset = { x, y } end
function FontObj:SetSpacing() end
function FontObj:GetName() return S[self].name end

local function fontDef(name, size, r, g, b, flags, path)
  local f = CreateFont(name)
  S[f].name = name
  f:SetFont(path or "Fonts\\FRIZQT__.TTF", size, flags or "")
  f:SetTextColor(r, g, b, 1)
  S[f].shadowOffset = { 1, -1 }
  S[f].shadowColor = { 0, 0, 0, 1 }
end
local gold, white, red, green, grey = { 1, .82, 0 }, { 1, 1, 1 }, { 1, .1, .1 }, { .1, 1, .1 }, { .5, .5, .5 }
for _, d in ipairs({
  { "GameFontNormal", 12, gold }, { "GameFontNormalSmall", 10, gold }, { "GameFontNormalLarge", 16, gold }, { "GameFontNormalHuge", 20, gold },
  { "GameFontNormalMed3", 14, gold }, { "GameFontNormalMed2", 13, gold }, { "GameFontNormalOutline", 12, gold, "OUTLINE" },
  { "GameFontHighlight", 12, white }, { "GameFontHighlightSmall", 10, white }, { "GameFontHighlightLarge", 16, white },
  { "GameFontHighlightMedium", 14, white }, { "GameFontHighlightHuge", 20, white }, { "GameFontHighlightOutline", 12, white, "OUTLINE" },
  { "GameFontDisable", 12, grey }, { "GameFontDisableSmall", 10, grey }, { "GameFontDisableLarge", 16, grey },
  { "GameFontRed", 12, red }, { "GameFontRedSmall", 10, red }, { "GameFontGreen", 12, green }, { "GameFontGreenSmall", 10, green },
  { "GameFontWhite", 12, white }, { "GameFontBlack", 12, { 0, 0, 0 } },
  { "SystemFont_Small", 10, white }, { "SystemFont_Med1", 12, white }, { "SystemFont_Med2", 13, white }, { "SystemFont_Med3", 14, white },
  { "SystemFont_Large", 16, white }, { "SystemFont_Huge1", 20, white }, { "SystemFont_Shadow_Small", 10, white },
  { "SystemFont_Shadow_Med1", 12, white }, { "SystemFont_Shadow_Med2", 14, white }, { "SystemFont_Shadow_Med3", 14, white },
  { "SystemFont_Shadow_Large", 16, white }, { "SystemFont_Shadow_Huge1", 20, white }, { "SystemFont_Outline_Small", 10, white, "OUTLINE" },
  { "SystemFont_Tiny", 9, white }, { "SystemFont_OutlineThick_WTF", 32, white, "THICKOUTLINE" },
  { "ChatFontNormal", 14, white }, { "ChatFontSmall", 12, white }, { "NumberFontNormal", 14, white, "OUTLINE", "Fonts\\ARIALN.TTF" },
  { "NumberFontNormalSmall", 12, white, "OUTLINE", "Fonts\\ARIALN.TTF" }, { "NumberFontNormalLarge", 16, white, "OUTLINE", "Fonts\\ARIALN.TTF" },
  { "NumberFontNormalYellow", 14, gold, "OUTLINE", "Fonts\\ARIALN.TTF" }, { "NumberFontNormalRight", 14, white, "OUTLINE", "Fonts\\ARIALN.TTF" },
  { "GameTooltipText", 12, white }, { "GameTooltipTextSmall", 10, white }, { "GameTooltipHeaderText", 14, white },
  { "QuestFont", 13, white }, { "QuestTitleFont", 18, gold }, { "ItemTextFontNormal", 14, white }, { "FriendsFont_Normal", 12, white },
  { "FriendsFont_Small", 11, white }, { "FriendsFont_Large", 14, white }, { "Tooltip_Med", 12, white }, { "Tooltip_Small", 10, white },
}) do
  fontDef(d[1], d[2], d[3][1], d[3][2], d[3][3], d[4], d[5])
end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UNIT_NAME_FONT = "Fonts\\FRIZQT__.TTF"
DAMAGE_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

function FontString:SetText(t)
  local s = S[self]
  t = (t == nil) and "" or tostring(t)
  if s.text ~= t then s.text = t ldirty() end
end
function FontString:SetFormattedText(f, ...) self:SetText(string.format(f, ...)) end
function FontString:GetText() return S[self].text or "" end
function FontString:SetFont(path, size, flags) S[self].font = { path, size, flags or "" } ldirty() return true end
function FontString:GetFont() return fontOf(S[self]) end
function FontString:SetFontObject(o) S[self].fontObj = resolveRel(o) S[self].font = nil ldirty() end
function FontString:GetFontObject() return S[self].fontObj end
function FontString:SetTextColor(r, g, b, a) S[self].color = { r, g, b, a or 1 } dirty() end
function FontString:GetTextColor() local c = S[self].color or (S[self].fontObj and S[S[self].fontObj].color) or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function FontString:SetJustifyH(j) S[self].jh = j dirty() end
function FontString:SetJustifyV(j) S[self].jv = j dirty() end
function FontString:GetJustifyH() return S[self].jh or "CENTER" end
function FontString:GetJustifyV() return S[self].jv or "MIDDLE" end
function FontString:SetShadowColor(r, g, b, a) S[self].shadowColor = { r, g, b, a or 1 } dirty() end
function FontString:SetShadowOffset(x, y) S[self].shadowOffset = { x, y } dirty() end
function FontString:SetWordWrap(b) S[self].wrap = b ldirty() end
function FontString:CanWordWrap() return S[self].wrap ~= false end
function FontString:SetMaxLines(n) S[self].maxLines = n ldirty() end
function FontString:SetSpacing(n) S[self].spacing = n dirty() end
function FontString:SetTextHeight(h) local s = S[self] local p, _, f = fontOf(s) s.font = { p, h, f } ldirty() end
function FontString:GetStringWidth()
  local s = S[self]
  local p, sz, f = fontOf(s)
  return __measureW(s.text or "", p, sz, f)
end
function FontString:GetUnboundedStringWidth() return self:GetStringWidth() end
function FontString:GetStringHeight()
  local s = S[self]
  local p, sz, f = fontOf(s)
  local r = getRect(self)
  local wrapW = (s.wrap ~= false and (s.w or (#s.points > 1 and r and r[3] / effScale(self)))) or 0
  return __measureH(s.text or "", p, sz, f, wrapW or 0)
end
function FontString:GetLineHeight() local _, sz = fontOf(S[self]) return sz * 1.2 end
function FontString:IsTruncated() return false end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
function Frame:SetFrameStrata(st) S[self].strata = string.upper(st) dirty() end
function Frame:GetFrameStrata()
  local s = S[self]
  return s.strata or (s.parent and S[s.parent].strata) or "MEDIUM"
end
function Frame:SetFrameLevel(l) local s = S[self] s.level = l s.levelSet = true dirty() end
function Frame:GetFrameLevel() return S[self].level or 1 end
function Frame:SetFixedFrameStrata() end
function Frame:SetFixedFrameLevel() end
function Frame:Raise()
  local s = S[self]
  local top = 0
  if s.parent then for _, c in ipairs(S[s.parent].children) do top = max(top, S[c].level or 0) end end
  s.level = top + 1 s.levelSet = true dirty()
end
function Frame:Lower() S[self].level = 0 S[self].levelSet = true dirty() end
function Frame:SetToplevel(b) S[self].toplevel = b end
function Frame:IsToplevel() return S[self].toplevel or false end
function Frame:SetMovable(b) S[self].movable = b end
function Frame:IsMovable() return S[self].movable or false end
function Frame:SetResizable(b) S[self].resizable = b end
function Frame:IsResizable() return S[self].resizable or false end
function Frame:EnableMouse(b) S[self].mouse = b dirty() end
function Frame:IsMouseEnabled() return S[self].mouse or false end
function Frame:SetMouseClickEnabled(b) S[self].mouseClick = b end
function Frame:SetMouseMotionEnabled(b) S[self].mouseMotion = b end
function Frame:EnableMouseWheel(b) S[self].wheel = b dirty() end
function Frame:EnableKeyboard(b) S[self].keyboard = b end
function Frame:SetClampedToScreen(b) S[self].clamped = b end
function Frame:SetClipsChildren(b) S[self].clip = b dirty() end
function Frame:DoesClipChildren() return S[self].clip or false end
function Frame:GetClampedToScreen() return S[self].clamped or false end
function Frame:SetUserPlaced(b) S[self].userPlaced = b end
function Frame:IsUserPlaced() return S[self].userPlaced or false end
function Frame:SetID(id) S[self].frameId = id end
function Frame:GetID() return S[self].frameId or 0 end
function Frame:RegisterForDrag(...) S[self].drag = { ... } end
function Frame:SetPropagateKeyboardInput(b) S[self].propagateKeys = b end
function Frame:GetChildren() return unpack(S[self].children) end
function Frame:GetRegions() return unpack(S[self].regions) end
function Frame:GetNumChildren() return #S[self].children end
function Frame:GetNumRegions() return #S[self].regions end
function Frame:SetAttribute(k, v)
  local s = S[self]
  local old = s.attrs[k]
  s.attrs[k] = v
  if old ~= v then fire(self, "OnAttributeChanged", k, v) end
end
function Frame:GetAttribute(k) return S[self].attrs[k] end

function Frame:SetScript(name, fn) S[self].scripts[name] = fn end
function Frame:GetScript(name) return S[self].scripts[name] end
function Frame:HookScript(name, fn)
  local h = S[self].hooks
  h[name] = h[name] or {}
  table.insert(h[name], fn)
end
function Frame:HasScript(name) return true end
function Frame:RegisterEvent(ev) regEvent(self, ev) end
function Frame:UnregisterEvent(ev) unregEvent(self, ev) end
function Frame:RegisterAllEvents() regEvent(self, "*") end
function Frame:UnregisterAllEvents() for ev in pairs(S[self].events) do unregEvent(self, ev) end end
function Frame:IsEventRegistered(ev) return S[self].events[ev] or false end
function Frame:RegisterUnitEvent(ev, ...)
  local s = S[self]
  s.unitFilter = s.unitFilter or {}
  s.unitFilter[ev] = { ... }
  regEvent(self, ev)
end

function Frame:SetBackdrop(t)
  local s = S[self]
  if not t then s.backdrop = nil dirty() return end
  s.backdrop = t
  s.bdColor = s.bdColor or { 1, 1, 1, 1 }
  s.bdBorder = s.bdBorder or { 1, 1, 1, 1 }
  dirty()
end
function Frame:GetBackdrop() return S[self].backdrop end
function Frame:SetBackdropColor(r, g, b, a)
  if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
  S[self].bdColor = { r, g, b, a or 1 } dirty()
end
function Frame:SetBackdropBorderColor(r, g, b, a)
  if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
  S[self].bdBorder = { r, g, b, a or 1 } dirty()
end
function Frame:GetBackdropColor() local c = S[self].bdColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function Frame:GetBackdropBorderColor() local c = S[self].bdBorder or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function Frame:ApplyBackdrop() end
function Frame:OnBackdropLoaded() end

function Frame:CreateTexture(name, layer, template, sublevel)
  local o = setmetatable({}, Texture)
  local s = newState(o, "tex", "Texture", self)
  s.layer, s.sub = layer or "ARTWORK", sublevel or 0
  if name then
    if string.find(name, "$parent", 1, true) then name = string.gsub(name, "%$parent", S[self].name or "") end
    s.name = name
    _G[name] = o
  end
  table.insert(S[self].regions, o)
  ldirty()
  return o
end
function Frame:CreateFontString(name, layer, template)
  local o = setmetatable({}, FontString)
  local s = newState(o, "fs", "FontString", self)
  s.layer, s.sub = layer or "OVERLAY", 0
  s.text = ""
  if name then
    if string.find(name, "$parent", 1, true) then name = string.gsub(name, "%$parent", S[self].name or "") end
    s.name = name
    _G[name] = o
  end
  if template and _G[template] then s.fontObj = _G[template] end
  table.insert(S[self].regions, o)
  ldirty()
  return o
end

-- Moving
function Frame:StartMoving()
  local s = S[self]
  local r = getRect(self)
  if not r then return end
  s.moving = { dx = __cursor.x - r[1], dy = __cursor.y - r[2] }
  __moving = self
end
function Frame:StopMovingOrSizing()
  S[self].moving = nil
  S[self].sizing = nil
  if __moving == self then __moving = nil end
end
function Frame:StartSizing(point)
  local s = S[self]
  local r = getRect(self)
  if not r then return end
  s.sizing = { x = __cursor.x, y = __cursor.y, w = r[3], h = r[4] }
  __moving = self
end

local function applyMove()
  local o = __moving
  if not o then return end
  local s = S[o]
  local es = effScale(o)
  if s.moving then
    local x, y = (__cursor.x - s.moving.dx), (__cursor.y - s.moving.dy)
    if s.clamped then
      local r = getRect(o)
      x = max(0, min(SW - r[3], x))
      y = max(0, min(SH - r[4], y))
    end
    s.points = { { point = "BOTTOMLEFT", rel = UIParent, relPoint = "BOTTOMLEFT", x = x / es, y = y / es } }
    ldirty()
  elseif s.sizing then
    local w = s.sizing.w + (__cursor.x - s.sizing.x)
    local h = s.sizing.h - (__cursor.y - s.sizing.y)
    s.w, s.h = max(20, w / es), max(20, h / es)
    ldirty()
  end
end

---------------------------------------------------------------------------
-- Button / CheckButton
---------------------------------------------------------------------------
local function ensureFS(self)
  local s = S[self]
  if not s.fs then
    local fs = self:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontNormal)
    fs:SetPoint("CENTER", self, "CENTER", 0, 0)
    s.fs = fs
    s.btex = s.btex or {}
  end
  return s.fs
end

local function buttonTexture(self, role, tex, layer)
  local s = S[self]
  s.btex = s.btex or {}
  local old = s.btex[role]
  if tex == nil then
    if old then S[old].shown = false s.btex[role] = nil dirty() end
    return
  end
  local t
  if type(tex) == "table" then
    t = tex
  else
    t = old or self:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(tex)
  end
  if old and old ~= t then S[old].shown = false end
  local ts = S[t]
  ts.role = role
  if #ts.points == 0 then t:SetAllPoints(self) end
  if role == "highlight" then ts.blend = ts.blend or "ADD" end
  s.btex[role] = t
  dirty()
  return t
end

function Button:SetText(t) ensureFS(self):SetText(t) end
function Button:GetText() local fs = S[self].fs return fs and fs:GetText() or "" end
function Button:GetFontString() return ensureFS(self) end
function Button:SetFontString(fs) S[self].fs = fs end
function Button:GetTextWidth() return ensureFS(self):GetStringWidth() end
function Button:GetTextHeight() return ensureFS(self):GetStringHeight() end
function Button:SetNormalFontObject(fo) ensureFS(self):SetFontObject(fo) S[self].normalFont = fo end
function Button:SetHighlightFontObject(fo) S[self].hlFont = fo end
function Button:SetDisabledFontObject(fo) S[self].disFont = fo; if S[self].disabled then ensureFS(self):SetFontObject(fo) end end
function Button:GetNormalFontObject() return S[self].normalFont end
function Button:SetNormalTexture(t) return buttonTexture(self, "normal", t, "BORDER") end
function Button:SetPushedTexture(t) return buttonTexture(self, "pushed", t, "ARTWORK") end
function Button:SetHighlightTexture(t, mode) local r = buttonTexture(self, "highlight", t, "HIGHLIGHT") if r and mode then r:SetBlendMode(mode) end return r end
function Button:SetDisabledTexture(t) return buttonTexture(self, "disabled", t, "ARTWORK") end
function Button:GetNormalTexture() return (S[self].btex or {}).normal end
function Button:GetPushedTexture() return (S[self].btex or {}).pushed end
function Button:GetHighlightTexture() return (S[self].btex or {}).highlight end
function Button:GetDisabledTexture() return (S[self].btex or {}).disabled end
function Button:SetNormalAtlas(a) local t = buttonTexture(self, "normal", "", "BORDER") if t then t:SetAtlas(a) end end
function Button:SetPushedAtlas(a) local t = buttonTexture(self, "pushed", "", "ARTWORK") if t then t:SetAtlas(a) end end
function Button:SetHighlightAtlas(a) local t = buttonTexture(self, "highlight", "", "HIGHLIGHT") if t then t:SetAtlas(a) end end
function Button:SetDisabledAtlas(a) local t = buttonTexture(self, "disabled", "", "ARTWORK") if t then t:SetAtlas(a) end end
function Button:Enable()
  local s = S[self]
  s.disabled = false
  if s.fs and s.normalFont then s.fs:SetFontObject(s.normalFont) end
  dirty()
end
function Button:Disable()
  local s = S[self]
  s.disabled = true
  if s.fs and s.disFont then s.fs:SetFontObject(s.disFont) end
  dirty()
end
function Button:SetEnabled(b) if b then self:Enable() else self:Disable() end end
function Button:IsEnabled() return not S[self].disabled end
function Button:RegisterForClicks(...) S[self].clicks = { ... } end
function Button:LockHighlight() S[self].lockHL = true dirty() end
function Button:UnlockHighlight() S[self].lockHL = nil dirty() end
function Button:GetButtonState() return S[self].down and "PUSHED" or "NORMAL" end
function Button:SetButtonState(st) S[self].down = (st == "PUSHED") dirty() end
function Button:SetPushedTextOffset() end
function Button:Click(btn)
  local s = S[self]
  if s.disabled then return end
  btn = btn or "LeftButton"
  if s.type == "CheckButton" then s.checked = not s.checked end
  fire(self, "PreClick", btn, false)
  fire(self, "OnClick", btn, false)
  fire(self, "PostClick", btn, false)
  dirty()
end

function CheckButton:SetChecked(b) S[self].checked = b and true or false dirty() end
function CheckButton:GetChecked() return S[self].checked or false end
function CheckButton:SetCheckedTexture(t) return buttonTexture(self, "checked", t, "ARTWORK") end
function CheckButton:GetCheckedTexture() return (S[self].btex or {}).checked end
function CheckButton:SetDisabledCheckedTexture() end

---------------------------------------------------------------------------
-- EditBox
---------------------------------------------------------------------------
function EditBox:SetText(t)
  local s = S[self]
  t = (t == nil) and "" or tostring(t)
  if s.etext == t then return end
  s.etext = t
  dirty()
  fire(self, "OnTextChanged", false)
end
function EditBox:GetText() return S[self].etext or "" end
function EditBox:GetNumber() return tonumber(S[self].etext) or 0 end
function EditBox:SetNumber(n) self:SetText(tostring(n or 0)) end
function EditBox:Insert(t) self:SetText((S[self].etext or "") .. t) end
function EditBox:SetMultiLine(b) S[self].multi = b dirty() end
function EditBox:IsMultiLine() return S[self].multi or false end
function EditBox:SetPassword(b) S[self].password = b dirty() end
function EditBox:SetNumeric(b) S[self].numeric = b end
function EditBox:SetMaxLetters(n) S[self].maxLetters = n end
function EditBox:SetAutoFocus(b) S[self].autoFocus = b end
function EditBox:SetFont(path, size, flags) S[self].font = { path, size, flags or "" } dirty() end
function EditBox:SetFontObject(fo) S[self].fontObj = resolveRel(fo) dirty() end
function EditBox:SetTextColor(r, g, b, a) S[self].color = { r, g, b, a or 1 } dirty() end
function EditBox:SetTextInsets(l, r, t, b) S[self].insets = { l or 0, r or 0, t or 0, b or 0 } dirty() end
function EditBox:SetJustifyH(j) S[self].jh = j dirty() end
function EditBox:SetFocus() S[self].wantFocus = true __focus = self dirty() fire(self, "OnEditFocusGained") end
function EditBox:ClearFocus()
  if __focus == self then __focus = nil fire(self, "OnEditFocusLost") end
  S[self].wantFocus = false dirty()
end
function EditBox:HasFocus() return __focus == self end
function EditBox:HighlightText() end
function EditBox:SetCursorPosition() end
function EditBox:GetCursorPosition() return #(S[self].etext or "") end
function EditBox:AddHistoryLine() end

---------------------------------------------------------------------------
-- Slider
---------------------------------------------------------------------------
function Slider:SetMinMaxValues(mn, mx)
  local s = S[self]
  s.min, s.max = mn, mx
  if s.val then self:SetValue(s.val) end
  dirty()
end
function Slider:GetMinMaxValues() local s = S[self] return s.min or 0, s.max or 100 end
function Slider:SetValueStep(st) S[self].step = st end
function Slider:GetValueStep() return S[self].step or 0 end
function Slider:SetStepsPerPage() end
function Slider:SetObeyStepOnDrag() end
function Slider:SetOrientation(o) S[self].orient = o dirty() end
function Slider:GetOrientation() return S[self].orient or "VERTICAL" end
function Slider:SetThumbTexture(t) return buttonTexture(self, "thumb", t, "OVERLAY") end
function Slider:GetThumbTexture() return (S[self].btex or {}).thumb end
function Slider:SetValue(v)
  local s = S[self]
  local mn, mx = s.min or 0, s.max or 100
  if s.step and s.step > 0 then v = floor((v - mn) / s.step + 0.5) * s.step + mn end
  v = max(mn, min(mx, v))
  if s.val ~= v then
    s.val = v
    dirty()
    fire(self, "OnValueChanged", v, false)
  end
end
function Slider:GetValue() return S[self].val or S[self].min or 0 end
function Slider:Enable() S[self].disabled = false dirty() end
function Slider:Disable() S[self].disabled = true dirty() end
function Slider:IsEnabled() return not S[self].disabled end

---------------------------------------------------------------------------
-- StatusBar
---------------------------------------------------------------------------
function StatusBar:SetMinMaxValues(mn, mx) local s = S[self] s.min, s.max = mn, mx dirty() end
function StatusBar:GetMinMaxValues() local s = S[self] return s.min or 0, s.max or 1 end
function StatusBar:SetValue(v) S[self].val = v dirty() end
function StatusBar:GetValue() return S[self].val or 0 end
function StatusBar:SetStatusBarColor(r, g, b, a) S[self].sbColor = { r, g, b, a or 1 } dirty() end
function StatusBar:GetStatusBarColor() local c = S[self].sbColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function StatusBar:SetStatusBarTexture(t)
  local s = S[self]
  if type(t) == "table" then s.sbTex = t else s.sbTexPath = t end
  dirty()
  return s.sbTex
end
function StatusBar:GetStatusBarTexture()
  local s = S[self]
  if not s.sbTex then
    s.sbTex = self:CreateTexture(nil, "ARTWORK")
    S[s.sbTex].sbFill = true
    if s.sbTexPath then s.sbTex:SetTexture(s.sbTexPath) end
  end
  return s.sbTex
end
function StatusBar:SetOrientation(o) S[self].orient = o dirty() end
function StatusBar:SetReverseFill(b) S[self].reverse = b dirty() end
function StatusBar:SetFillStyle() end
function StatusBar:SetRotatesTexture() end

---------------------------------------------------------------------------
-- ScrollFrame
---------------------------------------------------------------------------
local function positionScrollChild(self)
  local s = S[self]
  if not s.child then return end
  local c = s.child
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", self, "TOPLEFT", -(s.hscroll or 0), s.vscroll or 0)
end
function ScrollFrame:SetScrollChild(child)
  local s = S[self]
  child = resolveRel(child)
  s.child = child
  s.clip = true
  child:SetParent(self)
  positionScrollChild(self)
end
function ScrollFrame:GetScrollChild() return S[self].child end
function ScrollFrame:SetVerticalScroll(v)
  local s = S[self]
  s.vscroll = max(0, v)
  positionScrollChild(self)
  fire(self, "OnVerticalScroll", s.vscroll)
end
function ScrollFrame:SetHorizontalScroll(v) S[self].hscroll = max(0, v) positionScrollChild(self) fire(self, "OnHorizontalScroll", S[self].hscroll) end
function ScrollFrame:GetVerticalScroll() return S[self].vscroll or 0 end
function ScrollFrame:GetHorizontalScroll() return S[self].hscroll or 0 end
function ScrollFrame:GetVerticalScrollRange()
  local c = S[self].child
  return c and max(0, c:GetHeight() - self:GetHeight()) or 0
end
function ScrollFrame:GetHorizontalScrollRange()
  local c = S[self].child
  return c and max(0, c:GetWidth() - self:GetWidth()) or 0
end
function ScrollFrame:UpdateScrollChildRect() end

---------------------------------------------------------------------------
-- ScrollingMessageFrame
---------------------------------------------------------------------------
function MessageFrame:AddMessage(text, r, g, b)
  local s = S[self]
  s.lines = s.lines or {}
  table.insert(s.lines, { tostring(text), r or 1, g or 1, b or 1 })
  local maxl = s.maxLines or 120
  while #s.lines > maxl do table.remove(s.lines, 1) end
  dirty()
end
MessageFrame.AddMsg = MessageFrame.AddMessage
function MessageFrame:Clear() S[self].lines = {} dirty() end
function MessageFrame:SetMaxLines(n) S[self].maxLines = n end
function MessageFrame:SetFading() end
function MessageFrame:SetJustifyH(j) S[self].jh = j end
function MessageFrame:SetFont(p, sz, f) S[self].font = { p, sz, f or "" } dirty() end
function MessageFrame:SetFontObject(fo) S[self].fontObj = resolveRel(fo) dirty() end

---------------------------------------------------------------------------
-- GameTooltip
---------------------------------------------------------------------------
local function tipRelayout(self)
  local s = S[self]
  local lines = s.tipLines
  local w, h = 0, 12
  for i, ln in ipairs(lines) do
    local fsL = ln.left
    local fsR = ln.right
    local lw = fsL:GetStringWidth()
    local rw = (ln.rtext and fsR:GetStringWidth() + 20) or 0
    w = max(w, lw + rw)
    fsL:ClearAllPoints()
    fsL:SetPoint("TOPLEFT", self, "TOPLEFT", 10, -h)
    fsL:SetJustifyH("LEFT")
    fsR:ClearAllPoints()
    fsR:SetPoint("TOPRIGHT", self, "TOPRIGHT", -10, -h)
    fsR:SetJustifyH("RIGHT")
    h = h + fsL:GetStringHeight() + 2
  end
  s.w, s.h = max(w + 20, 40), h + 10
  ldirty()
end
local function tipEnsure(self)
  local s = S[self]
  if not s.tipLines then s.tipLines = {} s.tipUsed = 0 end
end
function Tooltip:SetOwner(owner, anchor, x, y)
  local s = S[self]
  tipEnsure(self)
  s.owner = owner
  self:ClearLines()
  self:ClearAllPoints()
  anchor = anchor or "ANCHOR_RIGHT"
  x, y = x or 0, y or 0
  local map = {
    ANCHOR_RIGHT = { "BOTTOMLEFT", "TOPRIGHT" }, ANCHOR_LEFT = { "BOTTOMRIGHT", "TOPLEFT" }, ANCHOR_TOP = { "BOTTOM", "TOP" },
    ANCHOR_BOTTOM = { "TOP", "BOTTOM" }, ANCHOR_TOPRIGHT = { "BOTTOMRIGHT", "TOPRIGHT" }, ANCHOR_TOPLEFT = { "BOTTOMLEFT", "TOPLEFT" },
    ANCHOR_BOTTOMRIGHT = { "TOPRIGHT", "BOTTOMRIGHT" }, ANCHOR_BOTTOMLEFT = { "TOPLEFT", "BOTTOMLEFT" },
  }
  local m = map[anchor]
  if m and owner then self:SetPoint(m[1], owner, m[2], x, y)
  elseif anchor == "ANCHOR_CURSOR" then self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", __cursor.x + 12, __cursor.y + 12)
  else self:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 100) end
end
function Tooltip:ClearLines()
  local s = S[self]
  tipEnsure(self)
  for _, ln in ipairs(s.tipLines) do ln.left:SetText("") ln.right:SetText("") ln.rtext = nil end
  s.tipUsed = 0
  tipRelayout(self)
end
function Tooltip:NumLines() return S[self].tipUsed or 0 end
function Tooltip:AddLine(text, r, g, b, wrap)
  local s = S[self]
  tipEnsure(self)
  s.tipUsed = s.tipUsed + 1
  local i = s.tipUsed
  local ln = s.tipLines[i]
  if not ln then
    local nm = (s.name or "GameTooltip")
    ln = {
      left = self:CreateFontString(nm .. "TextLeft" .. i, "ARTWORK"),
      right = self:CreateFontString(nm .. "TextRight" .. i, "ARTWORK"),
    }
    s.tipLines[i] = ln
  end
  ln.left:SetFontObject(i == 1 and GameTooltipHeaderText or GameTooltipText)
  ln.right:SetFontObject(GameTooltipText)
  ln.left:SetTextColor(r or 1, g or 1, b or 1)
  ln.left:SetText(text)
  ln.right:SetText("")
  ln.rtext = nil
  tipRelayout(self)
end
function Tooltip:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
  self:AddLine(l, lr, lg, lb)
  local ln = S[self].tipLines[S[self].tipUsed]
  ln.rtext = r
  ln.right:SetText(r)
  ln.right:SetTextColor(rr or 1, rg or 1, rb or 1)
  tipRelayout(self)
end
function Tooltip:SetText(text, r, g, b)
  self:ClearLines()
  self:AddLine(text, r or 1, g or 1, b or 1)
end
function Tooltip:SetUnit(unit) self:SetText(UnitName(unit) or unit) end
function Tooltip:SetHyperlink(link) self:SetText(tostring(link)) end
function Tooltip:SetSpellByID(id) self:SetText((GetSpellInfo and GetSpellInfo(id)) or ("Spell " .. tostring(id))) end
function Tooltip:SetItemByID(id) self:SetText("Item " .. tostring(id)) end
function Tooltip:GetOwner() return S[self].owner end
function Tooltip:FadeOut() self:Hide() end
function Tooltip:IsOwned(o) return S[self].owner == o end
function Tooltip:SetPadding() end
function Tooltip:AppendText(t) end

---------------------------------------------------------------------------
-- CreateFrame & templates
---------------------------------------------------------------------------
Templates = {}
local xmlTemplates = {}
__xmlTemplates = xmlTemplates

local function applyTemplate(frame, tname)
  tname = string.gsub(tname, "^%s+", "")
  tname = string.gsub(tname, "%s+$", "")
  if tname == "" then return end
  local b = Templates[tname]
  if b then b(frame) return end
  local x = xmlTemplates[tname]
  if x then __ApplyXMLTemplate(frame, x) return end
  if not warned["tpl:" .. tname] then
    warned["tpl:" .. tname] = true
    __log("warn", "Unknown frame template ignored: " .. tname)
  end
end
__applyTemplate = applyTemplate

local function applyTemplates(frame, list)
  if not list or list == "" then return end
  for t in string.gmatch(list, "[^,]+") do applyTemplate(frame, t) end
end
__applyTemplates = applyTemplates

function CreateFrame(typ, name, parent, template, id, noLoad)
  local class = frameClasses[typ]
  if not class then
    if not warned["type:" .. tostring(typ)] then
      warned["type:" .. tostring(typ)] = true
      __log("warn", "Unsupported frame type '" .. tostring(typ) .. "' created as plain Frame")
    end
    class = Frame
  end
  parent = resolveRel(parent) or UIParent
  local o = setmetatable({}, class)
  local s = newState(o, "frame", typ, parent)
  if typ == "Button" or typ == "CheckButton" or typ == "EditBox" or typ == "Slider" then s.mouse = true end
  if typ == "CheckButton" then s.checked = false end
  if typ == "GameTooltip" then s.strata = "TOOLTIP" s.shown = false end
  if typ == "ScrollFrame" then s.clip = true end
  if name then
    if string.find(name, "$parent", 1, true) then name = string.gsub(name, "%$parent", S[parent].name or "") end
    s.name = name
    _G[name] = o
  end
  table.insert(S[parent].children, o)
  s.level = (S[parent].level or 0) + 1
  if id then s.frameId = id end
  ldirty()
  applyTemplates(o, template)
  if not noLoad then fire(o, "OnLoad") end
  return o
end

-- Built-in template implementations. Visual look comes from the renderer's known-texture table.
local function panelButton(f)
  local s = S[f]
  f:SetSize(40, 22)
  f:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
  f:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
  f:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
  f:SetDisabledTexture("Interface\\Buttons\\UI-Panel-Button-Disabled")
  f:SetNormalFontObject(GameFontNormal)
  f:SetHighlightFontObject(GameFontHighlight)
  f:SetDisabledFontObject(GameFontDisable)
end
Templates.UIPanelButtonTemplate = panelButton
Templates.UIPanelDynamicResizeButtonTemplate = panelButton
Templates.SharedButtonTemplate = panelButton
Templates.GameMenuButtonTemplate = panelButton
Templates.UIMenuButtonStretchTemplate = panelButton
Templates.MagicButtonTemplate = panelButton
Templates.UIPanelButtonGrayTemplate = panelButton

Templates.UIPanelCloseButton = function(f)
  f:SetSize(32, 32)
  f:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  f:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
  f:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
  f:SetScript("OnClick", function(self) local p = self:GetParent() if p then p:Hide() end end)
end
Templates.UIPanelCloseButtonNoScripts = function(f) Templates.UIPanelCloseButton(f) f:SetScript("OnClick", nil) end

local function dialogBackdrop(f)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
end
Templates.DialogBorderTemplate = dialogBackdrop
Templates.DialogBorderDarkTemplate = dialogBackdrop
Templates.BackdropTemplate = function() end
Templates.TooltipBackdropTemplate = function(f)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0.09, 0.09, 0.19, 1)
  f:SetBackdropBorderColor(1, 1, 1, 1)
end
Templates.TooltipBorderBackdropTemplate = Templates.TooltipBackdropTemplate
Templates.InsetFrameTemplate = function(f)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  f:SetBackdropColor(0, 0, 0, 0.45)
  f:SetBackdropBorderColor(0.3, 0.25, 0.1, 1)
end

local function basicFrame(withInset)
  return function(f)
    local name = S[f].name
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local title = f:CreateFontString(name and (name .. "TitleText"), "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -9)
    f.TitleText = title
    local close = CreateFrame("Button", name and (name .. "CloseButton"), f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 1)
    f.CloseButton = close
    function f:SetTitle(t) self.TitleText:SetText(t) end
    if withInset then
      local inset = CreateFrame("Frame", name and (name .. "Inset"), f, "InsetFrameTemplate")
      inset:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)
      inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
      f.Inset = inset
    end
  end
end
Templates.BasicFrameTemplate = basicFrame(false)
Templates.BasicFrameTemplateWithInset = basicFrame(true)
Templates.ButtonFrameTemplate = basicFrame(true)
Templates.PortraitFrameTemplate = basicFrame(true)
Templates.DefaultPanelTemplate = basicFrame(false)
Templates.SimplePanelTemplate = basicFrame(false)

Templates.InputBoxTemplate = function(f)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  f:SetBackdropColor(0, 0, 0, 0.6)
  f:SetBackdropBorderColor(0.6, 0.55, 0.35, 1)
  f:SetFontObject(ChatFontNormal)
  f:SetTextInsets(6, 6, 0, 0)
  f:SetHeight(20)
end
Templates.SearchBoxTemplate = Templates.InputBoxTemplate

local function checkTemplate(f)
  local name = S[f].name
  f:SetSize(26, 26)
  f:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  f:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  f:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
  f:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  local text = f:CreateFontString(name and (name .. "Text"), "ARTWORK", "GameFontNormal")
  text:SetPoint("LEFT", f, "RIGHT", 2, 1)
  text:SetJustifyH("LEFT")
  f.Text = text
  f.text = text
end
Templates.UICheckButtonTemplate = checkTemplate
Templates.ChatConfigCheckButtonTemplate = checkTemplate
Templates.InterfaceOptionsCheckButtonTemplate = checkTemplate
Templates.OptionsBaseCheckButtonTemplate = checkTemplate
Templates.UIRadioButtonTemplate = checkTemplate

local function sliderTemplate(f)
  local name = S[f].name
  f:SetOrientation("HORIZONTAL")
  f:SetSize(144, 17)
  local thumb = f:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  S[thumb].w, S[thumb].h = 12, 22
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", edgeSize = 8 })
  local text = f:CreateFontString(name and (name .. "Text"), "ARTWORK", "GameFontNormal")
  text:SetPoint("BOTTOM", f, "TOP", 0, 2)
  local low = f:CreateFontString(name and (name .. "Low"), "ARTWORK", "GameFontHighlightSmall")
  low:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, -1)
  local high = f:CreateFontString(name and (name .. "High"), "ARTWORK", "GameFontHighlightSmall")
  high:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -2, -1)
  f.Text, f.Low, f.High = text, low, high
end
Templates.OptionsSliderTemplate = sliderTemplate
Templates.HorizontalSliderTemplate = sliderTemplate
Templates.MinimalSliderTemplate = sliderTemplate

local function scrollTemplate(f)
  local name = S[f].name
  local bar = CreateFrame("Slider", name and (name .. "ScrollBar"), f)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(16)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 20, -16)
  bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 20, 16)
  bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  bar:SetBackdropColor(0, 0, 0, 0.4)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  S[bar.GetThumbTexture(bar)].w = 14
  S[bar.GetThumbTexture(bar)].h = 24
  bar:SetScript("OnValueChanged", function(self, v) if S[f].vscroll ~= v then f:SetVerticalScroll(v) end end)
  f.ScrollBar = bar
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    self:SetVerticalScroll(max(0, min(range, self:GetVerticalScroll() - delta * 20)))
  end)
  f:HookScript("OnVerticalScroll", function(self, v)
    local range = self:GetVerticalScrollRange()
    bar:SetMinMaxValues(0, range)
    bar:SetValue(v)
  end)
end
Templates.UIPanelScrollFrameTemplate = scrollTemplate
Templates.FauxScrollFrameTemplate = function(f)
  scrollTemplate(f)
  -- Faux scrolling is driven by FauxScrollFrame_* helpers, not by the real scroll range
  S[f].hooks.OnVerticalScroll = nil
  f:SetScript("OnMouseWheel", nil)
end
Templates.ScrollFrameTemplate = scrollTemplate
Templates.MinimalScrollFrameTemplate = scrollTemplate

for _, n in ipairs({ "SecureActionButtonTemplate", "SecureUnitButtonTemplate", "SecureHandlerBaseTemplate", "SecureHandlerClickTemplate",
  "SecureHandlerStateTemplate", "SecureHandlerAttributeTemplate", "SecureHandlerEnterLeaveTemplate", "SecureHandlerShowHideTemplate",
  "SecureFrameTemplate", "SecureHandlerDragTemplate", "GameTooltipTemplate", "ActionButtonTemplate", "PingableType_UnitFrameTemplate" }) do
  Templates[n] = function() end
end

---------------------------------------------------------------------------
-- Root frames
---------------------------------------------------------------------------
do
  local function root(name)
    local o = setmetatable({}, Frame)
    local s = newState(o, "frame", "Frame", nil)
    s.isRoot = true
    s.name = name
    s.level = 0
    s.strata = "MEDIUM"
    _G[name] = o
    return o
  end
  WorldFrame = root("WorldFrame")
  UIParent = root("UIParent")
  S[UIParent].parent = nil
  S[UIParent].isRoot = true
  S[UIParent].noRender = true
  S[WorldFrame].noRender = true
  S[WorldFrame].strata = "BACKGROUND"
  S[UIParent].children = {}
  S[UIParent].strata = "MEDIUM"

  GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
  Templates.TooltipBackdropTemplate(GameTooltip)
  ItemRefTooltip = nil
  GameTooltip:SetBackdropColor(0.05, 0.05, 0.12, 0.95)
  S[GameTooltip].shown = false

  Minimap = CreateFrame("Frame", "Minimap", UIParent)
  Minimap:SetSize(140, 140)
  Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -30)
  S[Minimap].round = true
  S[Minimap].strata = "LOW"
  MinimapCluster = Minimap

  UISpecialFrames = {}
  UIParentLoaded = true
end

function GetScreenWidth() return SW end
function GetScreenHeight() return SH end
function UIParent_GetEffectiveScale() return 1 end
function GetCursorPosition() return __cursor.x, __cursor.y end
function GetMouseFocus() return __hoverObj end
function GetMouseFoci() return { __hoverObj } end
function GetFramesRegisteredForEvent(ev) return unpack(eventRegs[ev] or {}) end
function EnumerateFrames(prev)
  local idx = 0
  if prev then for i, o in ipairs(allObjs) do if o == prev then idx = i break end end end
  for i = idx + 1, #allObjs do if S[allObjs[i]].kind == "frame" then return allObjs[i] end end
end

function __SetScreen(w, h)
  SW, SH = w, h
  ldirty()
end

---------------------------------------------------------------------------
-- Host input
---------------------------------------------------------------------------
local byId = {}
local function objById(id)
  local o = byId[id]
  if o then return o end
  for _, x in ipairs(allObjs) do byId[S[x].id] = x end
  return byId[id]
end

function __MouseMove(x, y)
  __cursor.x, __cursor.y = x, y
  if __moving then applyMove() end
end

function __Mouse(id, ev, btn, extra)
  local o = objById(id)
  if not o then return end
  local s = S[o]
  btn = btn or "LeftButton"
  if ev == "enter" then
    s.hover = true
    __hoverObj = o
    dirty()
    fire(o, "OnEnter", true)
  elseif ev == "leave" then
    s.hover = false
    if __hoverObj == o then __hoverObj = nil end
    s.down = false
    dirty()
    fire(o, "OnLeave", true)
  elseif ev == "down" then
    s.down = true
    dirty()
    fire(o, "OnMouseDown", btn)
    if s.type == "Button" or s.type == "CheckButton" then
      if not s.disabled then
        local clicks = s.clicks
        local wantsDown = false
        if clicks then for _, c in ipairs(clicks) do if string.find(c, "Down") then wantsDown = true end end end
        if wantsDown then
          if s.type == "CheckButton" then s.checked = not s.checked end
          fire(o, "PreClick", btn, true) fire(o, "OnClick", btn, true) fire(o, "PostClick", btn, true)
        end
      end
    end
  elseif ev == "up" then
    local wasDown = s.down
    s.down = false
    dirty()
    fire(o, "OnMouseUp", btn)
    if wasDown and (s.type == "Button" or s.type == "CheckButton") and not s.disabled then
      local clicks = s.clicks
      local wantsUp = true
      if clicks then
        wantsUp = false
        for _, c in ipairs(clicks) do if string.find(c, "Up") or c == "AnyUp" then wantsUp = true end end
      end
      if wantsUp then
        if s.type == "CheckButton" then s.checked = not s.checked end
        fire(o, "PreClick", btn, false) fire(o, "OnClick", btn, false) fire(o, "PostClick", btn, false)
      end
    end
  elseif ev == "dragstart" then
    fire(o, "OnDragStart", btn)
  elseif ev == "dragstop" then
    fire(o, "OnDragStop")
  elseif ev == "wheel" then
    fire(o, "OnMouseWheel", extra)
  elseif ev == "slider" then
    local v = extra
    local mn, mx = s.min or 0, s.max or 100
    if s.step and s.step > 0 then v = floor((v - mn) / s.step + 0.5) * s.step + mn end
    v = max(mn, min(mx, v))
    if s.val ~= v then s.val = v dirty() fire(o, "OnValueChanged", v, true) end
  end
end

function __EditInput(id, ev, text)
  local o = objById(id)
  if not o then return end
  local s = S[o]
  if ev == "text" then
    s.etext = text
    fire(o, "OnTextChanged", true)
    fire(o, "OnChar", string.sub(text, -1))
  elseif ev == "enter" then fire(o, "OnEnterPressed")
  elseif ev == "escape" then fire(o, "OnEscapePressed")
  elseif ev == "tab" then fire(o, "OnTabPressed")
  elseif ev == "focus" then __focus = o fire(o, "OnEditFocusGained")
  elseif ev == "blur" then if __focus == o then __focus = nil end fire(o, "OnEditFocusLost")
  end
end

function __Key(key, down)
  if down and key == "ESCAPE" and not __focus then
    for _, name in ipairs(UISpecialFrames) do
      local f = _G[name]
      if f and f.IsShown and f:IsShown() then f:Hide() end
    end
  end
  for _, o in ipairs(allObjs) do
    local s = S[o]
    if s.keyboard and s.shown and isVisible(o) then
      fire(o, down and "OnKeyDown" or "OnKeyUp", key)
    end
  end
end

function __Tick(dt)
  __now_t = __now_t + dt
  __RunTimers()
  runAnimations(dt)
  local n = #allObjs
  for i = 1, n do
    local o = allObjs[i]
    local s = S[o]
    if s.kind == "frame" and (s.scripts.OnUpdate or s.hooks.OnUpdate) and isVisible(o) then
      fire(o, "OnUpdate", dt)
    end
  end
end

---------------------------------------------------------------------------
-- Snapshot for the renderer
---------------------------------------------------------------------------
local function rgba(c) if c then return { c[1], c[2], c[3], c[4] or 1 } end end

local function effAlpha(o)
  local s = S[o]
  local a = s.alpha * (s.animAlpha or 1)
  if s.parent and not s.ignoreAlpha then a = a * effAlpha(s.parent) end
  return a
end

function __Snapshot()
  local items = {}
  local clipOf = {}
  local function clipFor(o)
    -- nearest clipping ancestor rect (intersection of all clipping ancestors)
    local s = S[o]
    local p = s.parent
    if not p then return nil end
    local pc = clipOf[p]
    if pc == nil then pc = clipFor(p) or false clipOf[p] = pc end
    local ps = S[p]
    if ps.clip then
      local r = getRect(p)
      if r then
        local rect = { r[1], r[2], r[3], r[4] }
        if pc then
          local l, b = max(pc[1], rect[1]), max(pc[2], rect[2])
          local rr, tt = min(pc[1] + pc[3], rect[1] + rect[3]), min(pc[2] + pc[4], rect[2] + rect[4])
          rect = { l, b, max(0, rr - l), max(0, tt - b) }
        end
        return rect
      end
    end
    return pc or nil
  end

  for _, o in ipairs(allObjs) do
    local s = S[o]
    if not s.noRender and s.shown and isVisible(o) and (s.kind == "frame" or roleVisible(s)) then
      local r = getRect(o)
      if r and s.role == "thumb" then
        local ps = S[s.parent]
        local pr = getRect(s.parent)
        local es = effScale(o)
        local tw, th = (s.w or 32) * es, (s.h or 32) * es
        local mn, mx = ps.min or 0, ps.max or 100
        local frac = mx > mn and ((ps.val or mn) - mn) / (mx - mn) or 0
        if (ps.orient or "VERTICAL") == "HORIZONTAL" then
          r = { pr[1] + (pr[3] - tw) * frac, pr[2] + (pr[4] - th) / 2, tw, th }
        else
          r = { pr[1] + (pr[3] - tw) / 2, pr[2] + (pr[4] - th) * (1 - frac), tw, th }
        end
      end
      if r then
        local frameObj = (s.kind == "frame") and o or s.parent
        local fs = S[frameObj]
        local strataName = (function()
          local x = frameObj
          while x do local xs = S[x] if xs.strata then return xs.strata end x = xs.parent end
          return "MEDIUM"
        end)()
        local lvl = fs.level or 1
        local z = (strataOrder[strataName] or 2) * 200000000 + min(max(lvl, 0), 9999) * 20000
        local it = {
          id = s.id, k = s.kind, x = r[1], y = SH - (r[2] + r[4]), w = r[3], h = r[4], a = effAlpha(o), p = s.parent and S[s.parent].id or 0,
        }
        local clip = clipFor(o)
        if clip then it.clip = { clip[1], SH - (clip[2] + clip[4]), clip[3], clip[4] } end
        if s.kind == "frame" then
          it.z = z
          it.ft = s.type
          it.name = s.name
          local mouseOn = s.mouse
          if s.type == "Button" or s.type == "CheckButton" then mouseOn = s.mouse and not s.disabled or s.mouse end
          it.pe = (mouseOn or s.wheel or s.drag) and true or false
          if s.hit then it.hit = s.hit end
          if s.round then it.round = true end
          if s.backdrop then
            local b = s.backdrop
            local ins = b.insets or {}
            it.bd = {
              bg = b.bgFile, edge = b.edgeFile, tile = b.tile, edgeSize = b.edgeSize or 0, tileSize = b.tileSize,
              ins = { ins.left or 0, ins.right or 0, ins.top or 0, ins.bottom or 0 },
              bgc = rgba(s.bdColor), edgec = rgba(s.bdBorder),
            }
          end
          if s.clip then it.cl = true end
          if s.type == "EditBox" then
            local p, sz, fl = fontOf(s)
            local col = s.color or (s.fontObj and S[s.fontObj].color) or { 1, 1, 1, 1 }
            it.ed = { text = s.etext or "", multi = s.multi, pw = s.password, num = s.numeric, font = p, size = sz, flags = fl, col = col, ins = s.insets, jh = s.jh, focus = s.wantFocus, max = s.maxLetters }
          elseif s.type == "Slider" then
            local mn, mx = s.min or 0, s.max or 100
            it.sl = { min = mn, max = mx, val = s.val or mn, step = s.step or 0, orient = s.orient or "VERTICAL", dis = s.disabled }
          elseif s.type == "StatusBar" then
            local mn, mx = s.min or 0, s.max or 1
            local fillTex = s.sbTex and S[s.sbTex]
            it.sb = { min = mn, max = mx, val = s.val or 0, col = rgba(s.sbColor), orient = s.orient or "HORIZONTAL", rev = s.reverse,
              tex = (fillTex and fillTex.tex) or s.sbTexPath, vc = fillTex and rgba(fillTex.vc) }
          elseif s.type == "ScrollingMessageFrame" or s.type == "MessageFrame" then
            local p, sz, fl = fontOf(s)
            it.msgs = s.lines or {}
            it.mf = { font = p, size = sz, flags = fl, jh = s.jh }
          end
          if s.type == "CheckButton" then it.chk = s.checked end
          if s.disabled then it.dis = true end
          items[#items + 1] = it
        else
          local lay = layerOrder[s.layer or "ARTWORK"] or 3
          it.z = z + lay * 1000 + ((s.sub or 0) + 8) * 10
          if s.kind == "tex" then
            if s.sbFill then
              -- statusbar fill is drawn by the owning StatusBar item
              it = nil
            else
              it.tex = s.tex
              it.atlas = s.atlas
              it.col = rgba(s.col)
              it.vc = rgba(s.vc)
              it.tc = s.tc
              it.blend = s.blend
              it.desat = s.desat
              it.rot = s.rot
              it.grad = s.grad
              it.htile = s.htile
              it.vtile = s.vtile
              it.label = s.name
            end
          else
            local p, sz, fl = fontOf(s)
            local col = s.color or (s.fontObj and S[s.fontObj].color) or { 1, 1, 1, 1 }
            local sh = s.shadowOffset or (s.fontObj and S[s.fontObj].shadowOffset)
            local shc = s.shadowColor or (s.fontObj and S[s.fontObj].shadowColor) or { 0, 0, 0, 1 }
            it.txt = s.text or ""
            it.font, it.size, it.flags = p, sz, fl
            it.col = rgba(col)
            it.jh = s.jh or (s.fontObj and S[s.fontObj].jh) or "CENTER"
            it.jv = s.jv or (s.fontObj and S[s.fontObj].jv) or "MIDDLE"
            if sh and (sh[1] ~= 0 or sh[2] ~= 0) then it.sh = { sh[1], sh[2], shc[1], shc[2], shc[3], shc[4] } end
            it.wrap = s.wrap ~= false
            it.ml = s.maxLines
            it.sp = s.spacing
            if it.txt == "" then it = nil end
          end
          if it then items[#items + 1] = it end
        end
      end
    end
  end
  return __json({ ver = ver, w = SW, h = SH, items = items })
end

---------------------------------------------------------------------------
-- Introspection used by the inspector panel
---------------------------------------------------------------------------
function __FrameInfo(id)
  local o = objById(id)
  if not o then return "null" end
  local s = S[o]
  local r = getRect(o)
  local pts = {}
  for _, p in ipairs(s.points) do
    pts[#pts + 1] = { p.point, p.rel and S[p.rel] and (S[p.rel].name or ("#" .. S[p.rel].id)) or "parent", p.relPoint, p.x, p.y }
  end
  local scripts = {}
  for k in pairs(s.scripts) do scripts[#scripts + 1] = k end
  table.sort(scripts)
  local events = {}
  for k in pairs(s.events) do events[#events + 1] = k end
  table.sort(events)
  return __json({
    id = s.id, type = s.type, name = s.name, parent = s.parent and (S[s.parent].name or ("#" .. S[s.parent].id)),
    rect = r and { r[1], r[2], r[3], r[4] }, points = pts, scripts = scripts, events = events, shown = s.shown, visible = isVisible(o),
    alpha = s.alpha, scale = s.scale, strata = s.strata, level = s.level, mouse = s.mouse, children = #s.children, regions = #s.regions,
  })
end

function __FrameTree()
  local function walk(o)
    local s = S[o]
    local node = { id = s.id, type = s.type, name = s.name, shown = s.shown, kids = {} }
    for _, c in ipairs(s.children) do node.kids[#node.kids + 1] = walk(c) end
    for _, rg in ipairs(s.regions) do
      local rs = S[rg]
      node.kids[#node.kids + 1] = { id = rs.id, type = rs.type, name = rs.name, shown = rs.shown, kids = {}, text = rs.text }
    end
    return node
  end
  return __json(walk(UIParent))
end

function __ResetUI()
  -- drop every frame created by addons, keep the built-ins
  for i = #allObjs, 1, -1 do
    local o = allObjs[i]
    local s = S[o]
    local keep = o == UIParent or o == WorldFrame or o == GameTooltip or o == Minimap or s.parent == GameTooltip
    if not keep then
      if s.name and _G[s.name] == o then _G[s.name] = nil end
      S[o] = nil
      table.remove(allObjs, i)
    end
  end
  S[UIParent].children = {}
  S[GameTooltip].parent = UIParent
  S[UIParent].children = { GameTooltip, Minimap }
  for ev in pairs(eventRegs) do eventRegs[ev] = nil end
  playing = {}
  byId = {}
  UISpecialFrames = {}
  __moving, __focus, __hoverObj = nil, nil, nil
  GameTooltip:Hide()
  GameTooltip:ClearLines()
  ldirty()
end
