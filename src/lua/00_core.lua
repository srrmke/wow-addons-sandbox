-- Core: Lua 5.1 compatibility, WoW utility globals, JSON, error handling, timers.
-- The host (src/runtime.ts) provides: __log(kind, text), __measureW, __measureH, __readFile, __readXml.

local mfloor, mabs = math.floor, math.abs

---------------------------------------------------------------------------
-- Lua 5.1 compat (the engine is Lua 5.4)
---------------------------------------------------------------------------
unpack = table.unpack
loadstring = function(s, name) return load(s, name) end
table.getn = function(t) return #t end
table.maxn = function(t) local m = 0 for k in pairs(t) do if type(k) == "number" and k > m then m = k end end return m end
math.mod = math.fmod
math.pow = function(a, b) return a ^ b end
math.atan2 = math.atan
string.gfind = string.gmatch
table.foreach = function(t, f) for k, v in pairs(t) do local r = f(k, v) if r ~= nil then return r end end end
table.foreachi = function(t, f) for i, v in ipairs(t) do local r = f(i, v) if r ~= nil then return r end end end

function setfenv(fn, env)
  local i = 1
  while true do
    local name = debug.getupvalue(fn, i)
    if name == "_ENV" then
      debug.upvaluejoin(fn, i, function() return env end, 1)
      break
    elseif not name then
      break
    end
    i = i + 1
  end
  return fn
end

function getfenv(fn)
  if type(fn) ~= "function" then return _G end
  local i = 1
  while true do
    local name, val = debug.getupvalue(fn, i)
    if name == "_ENV" then return val elseif not name then break end
    i = i + 1
  end
  return _G
end

-- Lua 5.4 prints 5.0 where 5.1 printed 5. Patch what can be patched.
local function intify(v)
  if math.type(v) == "float" and v == mfloor(v) and mabs(v) < 1e15 then return math.tointeger(v) end
  return v
end
local _tostring = tostring
function tostring(v)
  return _tostring(intify(v))
end
local _sformat = string.format
function string.format(f, ...)
  local n = select("#", ...)
  if n == 0 then return _sformat(f) end
  local args = { ... }
  for i = 1, n do args[i] = intify(args[i]) end
  return _sformat(f, unpack(args, 1, n))
end

bit = {
  band = function(a, b) return a & b end,
  bor = function(a, b) return a | b end,
  bxor = function(a, b) return a ~ b end,
  bnot = function(a) return ~a end,
  lshift = function(a, n) return a << n end,
  rshift = function(a, n) return a >> n end,
}
bit32 = bit

---------------------------------------------------------------------------
-- WoW utility globals
---------------------------------------------------------------------------
strlen, strlower, strupper, strsub, strfind, strrep, strbyte, strchar, strrev =
  string.len, string.lower, string.upper, string.sub, string.find, string.rep, string.byte, string.char, string.reverse
gsub, strmatch, gmatch, format = string.gsub, string.match, string.gmatch, string.format
tinsert, tremove, sort = table.insert, table.remove, table.sort
floor, ceil, abs, min, max, sqrt, sin, cos, tan, rad, deg, random, fmod, mod =
  math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt, math.sin, math.cos, math.tan, math.rad, math.deg, math.random, math.fmod, math.fmod
huge = math.huge
date, time = os.date, os.time
tconcat = table.concat
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe

function strsplit(delim, str, pieces)
  if not str then return end
  local res, start = {}, 1
  for i = 1, #str do
    if pieces and #res >= pieces - 1 then break end
    if string.find(delim, string.sub(str, i, i), 1, true) then
      res[#res + 1] = string.sub(str, start, i - 1)
      start = i + 1
    end
  end
  res[#res + 1] = string.sub(str, start)
  return unpack(res)
end
function strjoin(delim, ...) return table.concat({ ... }, delim) end
function strtrim(s, chars)
  chars = chars or "%s"
  return (string.gsub(string.gsub(s, "^[" .. chars .. "]+", ""), "[" .. chars .. "]+$", ""))
end
function strsplittable(delim, str)
  return { strsplit(delim, str) }
end
function tContains(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function tIndexOf(t, v) for i, x in ipairs(t) do if x == v then return i end end end
function tDeleteItem(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end
function CopyTable(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local c = {}
  seen[t] = c
  for k, v in pairs(t) do c[CopyTable(k, seen)] = CopyTable(v, seen) end
  return setmetatable(c, getmetatable(t))
end
function tCount(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function Round(v) return floor(v + 0.5) end
function Clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
function Lerp(a, b, t) return a + (b - a) * t end
function PercentageBetween(v, lo, hi) if hi == lo then return 0 end return (v - lo) / (hi - lo) end
function Saturate(v) return Clamp(v, 0, 1) end
function issecure() return false end
function issecurevariable() return false end
function forceinsecure() end
function securecall(f, ...) if type(f) == "string" then f = _G[f] end return f(...) end
function debugstack() return debug.traceback() end
function debugprofilestop() return __now() * 1000 end
function geterrorhandler() return __errorHandler end
function seterrorhandler(f) __errorHandler = f end
function getglobal(n) return _G[n] end
function setglobal(n, v) _G[n] = v end
function nop() end
function IsLoggedIn() return true end
function GetBuildInfo() return "11.0.7", "58238", "Oct 23 2026", 110007 end
function GetLocale() return "enUS" end
function GetRealmName() return "Sandbox" end
function GetNormalizedRealmName() return "Sandbox" end
function GetCVar() return "1" end
function GetCVarBool() return true end
function SetCVar() end
function IsMacClient() return false end
function IsWindowsClient() return true end
function InCombatLockdown() return __mock.combat and true or false end
function IsInInstance() return false, "none" end
function IsInGroup() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 1 end
function GetNumAddOns() return #__addonList end
function PlaySound() end
function PlaySoundFile() end
function StopSound() end
function FlashClientIcon() end

function hooksecurefunc(a, b, c)
  local tbl, name, hook
  if type(a) == "table" then tbl, name, hook = a, b, c else tbl, name, hook = _G, a, b end
  local orig = tbl[name]
  if type(orig) ~= "function" then return end
  tbl[name] = function(...)
    local r = table.pack(orig(...))
    hook(...)
    return table.unpack(r, 1, r.n)
  end
end

function Mixin(obj, ...)
  for i = 1, select("#", ...) do
    local m = select(i, ...)
    if m then for k, v in pairs(m) do obj[k] = v end end
  end
  return obj
end
function CreateFromMixins(...) return Mixin({}, ...) end
function CreateAndInitFromMixin(mixin, ...)
  local o = CreateFromMixins(mixin)
  if o.Init then o:Init(...) end
  return o
end

function CreateColor(r, g, b, a)
  local c = { r = r, g = g, b = b, a = a or 1 }
  function c:GetRGB() return self.r, self.g, self.b end
  function c:GetRGBA() return self.r, self.g, self.b, self.a end
  function c:SetRGBA(r2, g2, b2, a2) self.r, self.g, self.b, self.a = r2, g2, b2, a2 or 1 end
  function c:GenerateHexColor() return string.format("ff%02x%02x%02x", floor(self.r * 255 + .5), floor(self.g * 255 + .5), floor(self.b * 255 + .5)) end
  function c:WrapTextInColorCode(text) return "|c" .. self:GenerateHexColor() .. text .. "|r" end
  function c:IsEqualTo(o) return self.r == o.r and self.g == o.g and self.b == o.b and self.a == o.a end
  return c
end
function CreateColorFromHexString(hex)
  hex = hex:gsub("^#", "")
  local a, r, g, b = 255, 255, 255, 255
  if #hex == 8 then a, r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), tonumber(hex:sub(7, 8), 16)
  elseif #hex == 6 then r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) end
  return CreateColor(r / 255, g / 255, b / 255, a / 255)
end
NORMAL_FONT_COLOR = CreateColor(1, 0.82, 0)
HIGHLIGHT_FONT_COLOR = CreateColor(1, 1, 1)
RED_FONT_COLOR = CreateColor(1, 0.1, 0.1)
GREEN_FONT_COLOR = CreateColor(0.1, 1, 0.1)
GRAY_FONT_COLOR = CreateColor(0.5, 0.5, 0.5)
YELLOW_FONT_COLOR = CreateColor(1, 1, 0)
WHITE_FONT_COLOR = CreateColor(1, 1, 1)
LIGHTGRAY_FONT_COLOR = CreateColor(0.75, 0.75, 0.75)
RAID_CLASS_COLORS = {
  WARRIOR = CreateColor(0.78, 0.61, 0.43), PALADIN = CreateColor(0.96, 0.55, 0.73), HUNTER = CreateColor(0.67, 0.83, 0.45),
  ROGUE = CreateColor(1, 0.96, 0.41), PRIEST = CreateColor(1, 1, 1), DEATHKNIGHT = CreateColor(0.77, 0.12, 0.23),
  SHAMAN = CreateColor(0, 0.44, 0.87), MAGE = CreateColor(0.25, 0.78, 0.92), WARLOCK = CreateColor(0.53, 0.53, 0.93),
  MONK = CreateColor(0, 1, 0.6), DRUID = CreateColor(1, 0.49, 0.04), DEMONHUNTER = CreateColor(0.64, 0.19, 0.79),
  EVOKER = CreateColor(0.2, 0.58, 0.5),
}
CUSTOM_CLASS_COLORS = nil
for k, v in pairs(RAID_CLASS_COLORS) do v.colorStr = v:GenerateHexColor() end

---------------------------------------------------------------------------
-- JSON (used for snapshots to the renderer and for SavedVariables)
---------------------------------------------------------------------------
local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
local function jstr(s)
  return '"' .. string.gsub(s, '[%c"\\]', function(c) return escapes[c] or string.format("\\u%04x", string.byte(c)) end) .. '"'
end

local function encode(v, buf, sv, depth, seen)
  local t = type(v)
  if t == "string" then buf[#buf + 1] = jstr(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then buf[#buf + 1] = "null"
    elseif math.type(v) == "integer" then buf[#buf + 1] = string.format("%d", v)
    elseif v == mfloor(v) and mabs(v) < 1e15 then buf[#buf + 1] = string.format("%d", v)
    else buf[#buf + 1] = string.format("%.14g", v) end
  elseif t == "boolean" then buf[#buf + 1] = v and "true" or "false"
  elseif t == "table" then
    if depth > 24 or seen[v] then buf[#buf + 1] = "null" return end
    seen[v] = true
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n == 0 then buf[#buf + 1] = "[]"
    elseif #v == n then
      buf[#buf + 1] = "["
      for i = 1, n do
        if i > 1 then buf[#buf + 1] = "," end
        encode(v[i], buf, sv, depth + 1, seen)
      end
      buf[#buf + 1] = "]"
    else
      buf[#buf + 1] = "{"
      local first = true
      for k, val in pairs(v) do
        local tv = type(val)
        if tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
          local key
          if type(k) == "string" then key = k
          elseif type(k) == "number" and sv then key = "#n:" .. tostring(k) end
          if key then
            if not first then buf[#buf + 1] = "," end
            first = false
            buf[#buf + 1] = jstr(key) .. ":"
            encode(val, buf, sv, depth + 1, seen)
          end
        end
      end
      buf[#buf + 1] = "}"
    end
    seen[v] = nil
  else buf[#buf + 1] = "null" end
end

function __json(v, sv)
  local buf = {}
  encode(v, buf, sv, 0, {})
  return table.concat(buf)
end

function __unjson(s, sv)
  local pos = 1
  local function ws() pos = string.find(s, "[^ \t\r\n]", pos) or #s + 1 end
  local value
  local function str()
    local out = {}
    pos = pos + 1
    while true do
      local c = string.sub(s, pos, pos)
      if c == '"' then pos = pos + 1 break
      elseif c == "\\" then
        local n = string.sub(s, pos + 1, pos + 1)
        if n == "u" then
          out[#out + 1] = utf8.char(tonumber(string.sub(s, pos + 2, pos + 5), 16))
          pos = pos + 6
        else
          out[#out + 1] = ({ n = "\n", r = "\r", t = "\t", b = "\b", f = "\f" })[n] or n
          pos = pos + 2
        end
      elseif c == "" then error("unterminated string")
      else
        local e = string.find(s, '["\\]', pos) or #s + 1
        out[#out + 1] = string.sub(s, pos, e - 1)
        pos = e
      end
    end
    return table.concat(out)
  end
  function value()
    ws()
    local c = string.sub(s, pos, pos)
    if c == "{" then
      local t = {}
      pos = pos + 1
      ws()
      if string.sub(s, pos, pos) == "}" then pos = pos + 1 return t end
      while true do
        ws()
        local k = str()
        ws()
        pos = pos + 1 -- :
        local v = value()
        if sv and string.sub(k, 1, 3) == "#n:" then k = tonumber(string.sub(k, 4)) end
        t[k] = v
        ws()
        local d = string.sub(s, pos, pos)
        pos = pos + 1
        if d == "}" then break end
      end
      return t
    elseif c == "[" then
      local t = {}
      pos = pos + 1
      ws()
      if string.sub(s, pos, pos) == "]" then pos = pos + 1 return t end
      while true do
        t[#t + 1] = value()
        ws()
        local d = string.sub(s, pos, pos)
        pos = pos + 1
        if d == "]" then break end
      end
      return t
    elseif c == '"' then return str()
    elseif string.sub(s, pos, pos + 3) == "true" then pos = pos + 4 return true
    elseif string.sub(s, pos, pos + 4) == "false" then pos = pos + 5 return false
    elseif string.sub(s, pos, pos + 3) == "null" then pos = pos + 4 return nil
    else
      local num = string.match(s, "^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
      pos = pos + #num
      return math.tointeger(tonumber(num)) or tonumber(num)
    end
  end
  return value()
end

---------------------------------------------------------------------------
-- Logging, errors, time
---------------------------------------------------------------------------
__mock = { combat = false }
__addonList = {}
__now_t = 0
function __now() return __now_t end
function GetTime() return __now_t end
GetTimePreciseSec = GetTime
function GetServerTime() return os.time() end

local function defaultErrorHandler(msg)
  __log("error", tostring(msg))
  return msg
end
__errorHandler = defaultErrorHandler

local function traceback(msg)
  if type(msg) ~= "string" then return msg end
  local tb = debug.traceback("", 2)
  -- trim internal sandbox frames
  tb = string.gsub(tb, "\n[^\n]*%[C%]: in [^\n]*", "")
  tb = string.gsub(tb, '\n[^\n]*%[string "%-%- [^\n]*', "")
  return msg .. tb
end

function __safecall(fn, ...)
  local ok, err = xpcall(fn, function(m) return __errorHandler(traceback(m)) end, ...)
  return ok, err
end

local function sandboxPrint(...)
  local n = select("#", ...)
  local parts = {}
  for i = 1, n do parts[i] = tostring((select(i, ...))) end
  __log("chat", table.concat(parts, " "))
end
print = sandboxPrint

DEFAULT_CHAT_FRAME = { name = "ChatFrame1" }
function DEFAULT_CHAT_FRAME:AddMessage(text, r, g, b)
  __log("chat", tostring(text), r, g, b)
end
function DEFAULT_CHAT_FRAME:GetName() return "ChatFrame1" end
function DEFAULT_CHAT_FRAME:IsShown() return true end
ChatFrame1 = DEFAULT_CHAT_FRAME
function SendChatMessage(msg, chatType) __log("chat", "[" .. tostring(chatType or "SAY") .. "] " .. tostring(msg)) end
function GetChatWindowInfo() return "General" end
UIErrorsFrame = { AddMessage = function(_, text) __log("ui", tostring(text)) end, Clear = function() end }

---------------------------------------------------------------------------
-- Timers (C_Timer) — driven by __Tick
---------------------------------------------------------------------------
local timers = {}
local function addTimer(delay, fn, iterations)
  local timer = { at = __now_t + delay, delay = delay, fn = fn, left = iterations }
  function timer:Cancel() self.cancelled = true end
  function timer:IsCancelled() return self.cancelled or false end
  timers[#timers + 1] = timer
  return timer
end
C_Timer = {
  After = function(d, fn) addTimer(d, fn, 1) end,
  NewTimer = function(d, fn) return addTimer(d, fn, 1) end,
  NewTicker = function(d, fn, n) return addTimer(d, fn, n or math.huge) end,
}

function __RunTimers()
  for i = #timers, 1, -1 do
    if timers[i].cancelled then table.remove(timers, i) end
  end
  local due = {}
  for _, t in ipairs(timers) do
    if not t.cancelled and t.at <= __now_t then due[#due + 1] = t end
  end
  for _, t in ipairs(due) do
    if not t.cancelled then
      t.left = t.left - 1
      if t.left <= 0 then t.cancelled = true else t.at = t.at + t.delay end
      __safecall(t.fn, t)
    end
  end
end
function __ClearTimers() timers = {} end
