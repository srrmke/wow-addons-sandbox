import "./style.css"
import { filesFromInput, loadFromFiles, signature, textFile, walkDirectory, type Addon, type RawFile } from "./addons"
import { Renderer, rich, type InputSink } from "./render"
import { Runtime, type LogKind } from "./runtime"
import { normalizePath } from "./textures"

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T

// ------------------------------------------------------------------ state
type Source =
  | { kind: "sample" }
  | { kind: "dir"; handle: FileSystemDirectoryHandle }
  | { kind: "files"; root: string; files: RawFile[] }

let source: Source | null = null
let addons: Addon[] = []
let sigCache = ""
let screen = { w: 1280, h: 720 }
let svCache: Record<string, string> = readJson("wowsb:sv", {})
let errorCount = 0
let reloading = false

function readJson<T>(key: string, fallback: T): T {
  try { const v = localStorage.getItem(key); return v ? (JSON.parse(v) as T) : fallback } catch { return fallback }
}
function writeJson(key: string, value: unknown) {
  try { localStorage.setItem(key, JSON.stringify(value)) } catch { /* storage unavailable */ }
}

// ---------------------------------------------------------------- console
const logEl = $("log")
function stamp(): string {
  const d = new Date()
  return d.toTimeString().slice(0, 8)
}
function addLog(kind: LogKind, text: string, r?: number, g?: number, b?: number) {
  if (kind === "error") { errorCount++; const badge = $("err-count"); badge.textContent = String(errorCount); badge.classList.remove("hidden") }
  const line = document.createElement("div")
  line.className = `l ${kind}`
  line.dataset.kind = kind
  const t = document.createElement("span")
  t.className = "t"
  t.textContent = stamp()
  const body = document.createElement("span")
  if (kind === "chat" && r !== undefined) body.style.color = `rgb(${r * 255},${g! * 255},${b! * 255})`
  rich(body, kind === "ui" ? `[UI] ${text}` : text)
  line.append(t, body)
  const stick = logEl.scrollTop + logEl.clientHeight >= logEl.scrollHeight - 30
  logEl.appendChild(line)
  while (logEl.childElementCount > 600) logEl.firstElementChild!.remove()
  applyFilters()
  if (stick) logEl.scrollTop = logEl.scrollHeight
}
function applyFilters() {
  const show: Record<string, boolean> = {
    chat: $<HTMLInputElement>("f-chat").checked, ui: $<HTMLInputElement>("f-chat").checked, info: true,
    warn: $<HTMLInputElement>("f-warn").checked, error: $<HTMLInputElement>("f-err").checked,
  }
  for (const l of Array.from(logEl.children) as HTMLElement[]) l.style.display = show[l.dataset.kind ?? "chat"] ? "" : "none"
}
for (const id of ["f-chat", "f-warn", "f-err"]) $(id).addEventListener("change", applyFilters)
$("btn-clear").addEventListener("click", () => { logEl.replaceChildren(); errorCount = 0; $("err-count").classList.add("hidden") })

function setStatus(text: string, kind: "" | "ok" | "bad" = "") {
  const s = $("status")
  s.textContent = text
  s.className = "hint " + kind
}

// ---------------------------------------------------------------- runtime
const runtime = new Runtime({
  log: addLog,
  requestReload: () => setTimeout(() => void reload("ReloadUI"), 0),
})

const stage = $("stage")
const imageIndex = () => {
  const map = new Map<string, string>()
  for (const a of addons) for (const [k, v] of a.images) map.set(k, v)
  return map
}
let images = new Map<string, string>()

const sink: InputSink = {
  mouse: (id, ev, btn, extra) => runtime.mouse(id, ev, btn, extra),
  edit: (id, ev, text) => runtime.edit(id, ev, text),
  cursor: (x, y) => runtime.mouseMove(x, y),
}

const renderer = new Renderer(stage, sink, (path) => {
  // Interface\AddOns\<Addon>\sub\file[.ext] -> <addon>/sub/file keyed lookups
  const n = normalizePath(path).replace(/\\/g, "/")
  const m = n.match(/^interface\/addons\/([^/]+)\/(.+)$/)
  if (m) {
    for (const a of addons) if (a.name.toLowerCase() === m[1]) { const url = a.images.get(m[2]); if (url) return url }
    return images.get(`${m[1]}/${m[2]}`)
  }
  return undefined
})

function applyZoom() {
  const area = $("stage-area")
  const mode = $<HTMLSelectElement>("zoom").value
  let k = 1
  if (mode === "fit") k = Math.min((area.clientWidth - 32) / screen.w, (area.clientHeight - 32) / screen.h)
  else k = parseFloat(mode)
  k = Math.max(0.1, k)
  const sizer = $("stage-sizer")
  sizer.style.width = screen.w * k + "px"
  sizer.style.height = screen.h * k + "px"
  stage.style.width = screen.w + "px"
  stage.style.height = screen.h + "px"
  stage.style.transform = `scale(${k})`
  zoomK = k
}
let zoomK = 1
new ResizeObserver(applyZoom).observe($("stage-area"))
$("zoom").addEventListener("change", applyZoom)
$("grid").addEventListener("change", (e) => stage.classList.toggle("grid", (e.target as HTMLInputElement).checked))

$<HTMLSelectElement>("res").value = localStorage.getItem("wowsb:res") ?? "1280x720"
function readRes() {
  const [w, h] = $<HTMLSelectElement>("res").value.split("x").map(Number)
  screen = { w, h }
}
readRes()
$("res").addEventListener("change", () => {
  readRes()
  try { localStorage.setItem("wowsb:res", `${screen.w}x${screen.h}`) } catch { /* ignore */ }
  runtime.setScreen(screen.w, screen.h)
  applyZoom()
})

stage.addEventListener("pointermove", (e) => {
  const r = stage.getBoundingClientRect()
  runtime.mouseMove((e.clientX - r.left) / zoomK, screen.h - (e.clientY - r.top) / zoomK)
})

// ------------------------------------------------------------ source I/O
async function collect(src: Source): Promise<{ addons: Addon[]; files: RawFile[] }> {
  if (src.kind === "sample") {
    const mods = import.meta.glob("./samples/**/*", { query: "?raw", import: "default", eager: true }) as Record<string, string>
    const files = Object.entries(mods).map(([p, c]) => textFile(p.replace("./samples/", ""), c))
    const out = await loadFromFiles("", files)
    return { addons: out, files }
  }
  const files = src.kind === "dir" ? await walkDirectory(src.handle) : src.files
  const root = src.kind === "dir" ? src.handle.name : src.root
  return { addons: await loadFromFiles(root, files), files }
}

function persistSaved() {
  if (!runtime.ready) return
  const raw = runtime.dumpSavedVariablesRaw()
  let changed = false
  for (const [name, json] of Object.entries(raw)) {
    if (svCache[name] !== json) { svCache[name] = json; changed = true }
  }
  if (changed) writeJson("wowsb:sv", svCache)
}
setInterval(persistSaved, 2000)
window.addEventListener("beforeunload", persistSaved)

async function reload(reason: string, opts: { rescan?: boolean } = {}) {
  if (!source || reloading) return
  reloading = true
  try {
    persistSaved()
    setStatus("loading…")
    const mock = runtime.ready ? JSON.stringify({ units: runtime.getMock().units, combat: runtime.getMock().combat }) : readJson<string | undefined>("wowsb:mock", undefined)
    if (opts.rescan !== false || !addons.length) {
      const res = await collect(source)
      for (const a of addons) for (const url of a.images.values()) if (url.startsWith("blob:")) URL.revokeObjectURL(url)
      addons = res.addons
      sigCache = signature(res.files)
      images = imageIndex()
    }
    renderer.clear()
    if (!addons.length) {
      setStatus("no .toc file found in that folder", "bad")
      addLog("error", "No addon found: the folder needs a <AddonName>.toc file.")
      refreshAddonList()
      return
    }
    $("empty").classList.add("hidden")
    errorCount = 0
    $("err-count").classList.add("hidden")
    addLog("info", `${reason}: loading ${addons.map((a) => a.name).join(", ")}`)
    const t0 = performance.now()
    await runtime.boot(addons, { w: screen.w, h: screen.h, mock: typeof mock === "string" ? mock : undefined, sv: svCache })
    setStatus(`loaded in ${Math.round(performance.now() - t0)} ms`, "ok")
    refreshAddonList()
    buildGameForm()
    refreshTree()
  } catch (e) {
    addLog("error", `[sandbox] ${(e as Error).message}`)
    setStatus("load failed", "bad")
  } finally {
    reloading = false
  }
}

function sourceLabel() {
  $("source-label").textContent = !source ? "no addon loaded" : source.kind === "sample" ? "sample addon" : source.kind === "dir" ? source.handle.name : source.root
}

async function useSource(src: Source) {
  source = src
  sourceLabel()
  await reload("Load")
}

// open folder
const fsApi = "showDirectoryPicker" in window
$("btn-open").addEventListener("click", async () => {
  if (fsApi) {
    try {
      const handle = await window.showDirectoryPicker({ mode: "read", id: "wow-addons" })
      await rememberHandle(handle)
      await useSource({ kind: "dir", handle })
    } catch (e) {
      if ((e as Error).name === "AbortError") return
      addLog("warn", "Chrome refused that folder (protected location). Falling back to the plain folder picker — no live reload. Tip: develop in a folder outside /Applications and symlink it into AddOns for live reload.")
      $<HTMLInputElement>("file-input").click()
    }
  } else $<HTMLInputElement>("file-input").click()
})
$<HTMLInputElement>("file-input").addEventListener("change", async (e) => {
  const list = (e.target as HTMLInputElement).files
  if (!list?.length) return
  const { root, files } = filesFromInput(list)
  addLog("info", "This browser can't watch folders — use ↻ Reload after re-picking, or open the page in Chrome/Edge for live reload.")
  await useSource({ kind: "files", root, files })
})
for (const id of ["btn-sample", "btn-sample-2"]) $(id).addEventListener("click", () => void useSource({ kind: "sample" }))
$("btn-reload").addEventListener("click", () => void reload("Manual reload"))

// remember last directory handle
function idb(): Promise<IDBDatabase> {
  return new Promise((res, rej) => {
    const rq = indexedDB.open("wowsb", 1)
    rq.onupgradeneeded = () => rq.result.createObjectStore("h")
    rq.onsuccess = () => res(rq.result)
    rq.onerror = () => rej(rq.error)
  })
}
async function rememberHandle(h: FileSystemDirectoryHandle) {
  try { const db = await idb(); db.transaction("h", "readwrite").objectStore("h").put(h, "last") } catch { /* private mode */ }
}
async function recallHandle(): Promise<FileSystemDirectoryHandle | undefined> {
  try {
    const db = await idb()
    return await new Promise((res) => {
      const rq = db.transaction("h").objectStore("h").get("last")
      rq.onsuccess = () => res(rq.result as FileSystemDirectoryHandle | undefined)
      rq.onerror = () => res(undefined)
    })
  } catch { return undefined }
}
void recallHandle().then((h) => {
  if (!h) return
  const b = $("btn-last")
  b.textContent = `↺ ${h.name}`
  b.classList.remove("hidden")
  b.addEventListener("click", async () => {
    try {
      if ((await h.requestPermission({ mode: "read" })) !== "granted") return
      await useSource({ kind: "dir", handle: h })
    } catch (e) { addLog("error", (e as Error).message) }
  })
})

// drag & drop
window.addEventListener("dragover", (e) => { e.preventDefault(); document.body.classList.add("drag") })
window.addEventListener("dragleave", (e) => { if (!e.relatedTarget) document.body.classList.remove("drag") })
window.addEventListener("drop", async (e) => {
  e.preventDefault()
  document.body.classList.remove("drag")
  const item = e.dataTransfer?.items[0] as (DataTransferItem & { getAsFileSystemHandle?: () => Promise<FileSystemHandle | null> }) | undefined
  const handle = await item?.getAsFileSystemHandle?.()
  if (handle?.kind === "directory") {
    await rememberHandle(handle as FileSystemDirectoryHandle)
    await useSource({ kind: "dir", handle: handle as FileSystemDirectoryHandle })
  } else addLog("warn", "Drop a folder (Chromium) or use “Open folder…”.")
})

// live reload on file changes
let watchBusy = false
setInterval(async () => {
  if (!$<HTMLInputElement>("watch").checked || source?.kind !== "dir" || watchBusy || reloading) return
  watchBusy = true
  try {
    const files = await walkDirectory(source.handle)
    const sig = signature(files)
    if (sig !== sigCache) {
      sigCache = sig
      await reload("Files changed")
    }
  } catch { /* folder temporarily unavailable */ } finally { watchBusy = false }
}, 900)

// ---------------------------------------------------------- command line
const cmd = $<HTMLInputElement>("cmd")
const history: string[] = readJson("wowsb:hist", [])
let hIdx = history.length
$("cmd-form").addEventListener("submit", (e) => {
  e.preventDefault()
  let line = cmd.value.trim()
  if (!line) return
  history.push(line)
  writeJson("wowsb:hist", history.slice(-50))
  hIdx = history.length
  addLog("chat", `> ${line}`)
  if (!line.startsWith("/")) line = "/" + line
  runtime.slash(line)
  cmd.value = ""
})
cmd.addEventListener("keydown", (e) => {
  if (e.key === "ArrowUp") { hIdx = Math.max(0, hIdx - 1); cmd.value = history[hIdx] ?? "" ; e.preventDefault() }
  else if (e.key === "ArrowDown") { hIdx = Math.min(history.length, hIdx + 1); cmd.value = history[hIdx] ?? ""; e.preventDefault() }
  e.stopPropagation()
})

// -------------------------------------------------------------- keyboard
const keyName = (e: KeyboardEvent) => (e.key.length === 1 ? e.key.toUpperCase() : e.key === "Escape" ? "ESCAPE" : e.key.toUpperCase())
window.addEventListener("keydown", (e) => {
  const t = e.target as HTMLElement
  if (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT") return
  runtime.setMock({ mods: { shift: e.shiftKey, ctrl: e.ctrlKey, alt: e.altKey } })
  runtime.key(keyName(e), true)
})
window.addEventListener("keyup", (e) => {
  runtime.setMock({ mods: { shift: e.shiftKey, ctrl: e.ctrlKey, alt: e.altKey } })
  runtime.key(keyName(e), false)
})

// ------------------------------------------------------------------ tabs
$("tabs").addEventListener("click", (e) => {
  const b = (e.target as HTMLElement).closest<HTMLElement>("button[data-tab]")
  if (!b) return
  for (const x of Array.from($("tabs").children)) x.classList.toggle("on", x === b)
  for (const p of Array.from(document.querySelectorAll<HTMLElement>(".pane"))) p.classList.toggle("on", p.id === `pane-${b.dataset.tab}`)
  if (b.dataset.tab === "inspect") refreshTree()
  if (b.dataset.tab === "console") { logEl.scrollTop = logEl.scrollHeight }
})

// ---------------------------------------------------------------- events
const EVENTS: { name: string; args?: unknown[]; mock?: unknown }[] = [
  { name: "PLAYER_ENTERING_WORLD", args: [false, true] },
  { name: "PLAYER_REGEN_DISABLED", mock: { combat: true } },
  { name: "PLAYER_REGEN_ENABLED", mock: { combat: false } },
  { name: "PLAYER_TARGET_CHANGED" },
  { name: "PLAYER_LEVEL_UP", args: [81] },
  { name: "PLAYER_DEAD" },
  { name: "PLAYER_ALIVE" },
  { name: "UNIT_HEALTH", args: ["player"] },
  { name: "UNIT_MAXHEALTH", args: ["player"] },
  { name: "UNIT_POWER_UPDATE", args: ["player", "MANA"] },
  { name: "UNIT_AURA", args: ["player"] },
  { name: "ZONE_CHANGED_NEW_AREA" },
  { name: "BAG_UPDATE", args: [0] },
  { name: "GROUP_ROSTER_UPDATE" },
  { name: "COMBAT_LOG_EVENT_UNFILTERED" },
  { name: "PLAYER_LOGOUT" },
]
const eventLog = $("event-log")
function fireEvent(name: string, args: unknown[] = [], mock?: unknown) {
  if (mock) runtime.setMock(mock)
  runtime.fire(name, ...args)
  const d = document.createElement("div")
  d.className = "l"
  d.textContent = `${stamp()}  ${name}(${args.map((a) => JSON.stringify(a)).join(", ")})`
  eventLog.appendChild(d)
  eventLog.scrollTop = eventLog.scrollHeight
}
$("event-chips").replaceChildren(...EVENTS.map((ev) => {
  const b = document.createElement("button")
  b.textContent = ev.name
  b.addEventListener("click", () => fireEvent(ev.name, ev.args, ev.mock))
  return b
}))
$("event-form").addEventListener("submit", (e) => {
  e.preventDefault()
  const name = $<HTMLInputElement>("event-name").value.trim()
  if (!name) return
  const raw = $<HTMLInputElement>("event-args").value.trim()
  const args = raw ? raw.split(",").map((s) => {
    const v = s.trim()
    if (v === "true") return true
    if (v === "false") return false
    if (v !== "" && !isNaN(Number(v))) return Number(v)
    return v.replace(/^["']|["']$/g, "")
  }) : []
  fireEvent(name, args)
})

// ------------------------------------------------------------ game state
const CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER"]
const CLASS_LOC: Record<string, string> = Object.fromEntries(CLASSES.map((c) => [c, c[0] + c.slice(1).toLowerCase()]))

function buildGameForm() {
  const mock = runtime.getMock()
  const p = mock.units?.player ?? {}
  const t = mock.units?.target
  const root = $("game-form")
  root.replaceChildren()
  const grp = (title: string) => { const g = document.createElement("div"); g.className = "grp"; g.innerHTML = `<b>${title}</b>`; root.appendChild(g); return g }

  const gp = grp("Player")
  gp.insertAdjacentHTML("beforeend", `
    <label class="plain">Name <input id="g-name" value="${p.name ?? ""}" /></label>
    <label class="plain">Class <select id="g-class">${CLASSES.map((c) => `<option ${c === p.class ? "selected" : ""}>${c}</option>`).join("")}</select></label>
    <label>Level <input type="range" id="g-level" min="1" max="90" value="${p.level ?? 80}" /><span class="val" id="g-level-v"></span></label>
    <label>Health <input type="range" id="g-hp" min="0" max="100" value="${Math.round(((p.hp ?? 1) / (p.hpMax || 1)) * 100)}" /><span class="val" id="g-hp-v"></span></label>
    <label>Power <input type="range" id="g-pw" min="0" max="100" value="${Math.round(((p.power ?? 1) / (p.powerMax || 1)) * 100)}" /><span class="val" id="g-pw-v"></span></label>`)
  const gt = grp("Target")
  gt.insertAdjacentHTML("beforeend", `
    <label class="plain">Has target <input type="checkbox" id="g-has-t" ${t ? "checked" : ""} /></label>
    <label class="plain">Name <input id="g-t-name" value="${t?.name ?? "Training Dummy"}" /></label>
    <label>Health <input type="range" id="g-t-hp" min="0" max="100" value="${t ? Math.round((t.hp / (t.hpMax || 1)) * 100) : 100}" /><span class="val" id="g-t-hp-v"></span></label>`)
  const gc = grp("Context")
  gc.insertAdjacentHTML("beforeend", `<label class="plain">In combat <input type="checkbox" id="g-combat" ${mock.combat ? "checked" : ""} /></label>
    <p class="muted">Hold Shift / Ctrl / Alt over the stage to drive <code>IsShiftKeyDown()</code> and friends.</p>`)

  const num = (id: string) => Number(($(id) as HTMLInputElement).value)
  const label = (id: string, text: string) => { $(id).textContent = text }
  const sync = () => {
    label("g-level-v", String(num("g-level")))
    label("g-hp-v", num("g-hp") + "%")
    label("g-pw-v", num("g-pw") + "%")
    label("g-t-hp-v", num("g-t-hp") + "%")
  }
  sync()
  const pushPlayer = (event?: string) => {
    sync()
    const cur = runtime.getMock().units.player
    runtime.setMock({ units: { player: {
      name: $<HTMLInputElement>("g-name").value, class: $<HTMLSelectElement>("g-class").value, classLoc: CLASS_LOC[$<HTMLSelectElement>("g-class").value],
      level: num("g-level"), hp: Math.round((num("g-hp") / 100) * cur.hpMax), power: Math.round((num("g-pw") / 100) * cur.powerMax),
    } } })
    if (event) runtime.fire(event, "player")
  }
  $("g-name").addEventListener("change", () => pushPlayer())
  $("g-class").addEventListener("change", () => pushPlayer())
  $("g-level").addEventListener("input", () => { pushPlayer(); runtime.fire("PLAYER_LEVEL_UP", num("g-level")) })
  $("g-hp").addEventListener("input", () => pushPlayer("UNIT_HEALTH"))
  $("g-pw").addEventListener("input", () => { pushPlayer(); runtime.fire("UNIT_POWER_UPDATE", "player", "MANA") })
  const pushTarget = () => {
    sync()
    if (!($("g-has-t") as HTMLInputElement).checked) return
    const cur = runtime.getMock().units.target
    runtime.setMock({ units: { target: { name: $<HTMLInputElement>("g-t-name").value, hp: Math.round((num("g-t-hp") / 100) * (cur?.hpMax ?? 1000000)) } } })
  }
  $("g-has-t").addEventListener("change", () => {
    const on = ($("g-has-t") as HTMLInputElement).checked
    if (on) {
      runtime.setMock({ units: { target: { name: $<HTMLInputElement>("g-t-name").value, class: "WARRIOR", classLoc: "Warrior", race: "Human", level: 82, hp: 1000000, hpMax: 1000000,
        power: 0, powerMax: 100, powerType: 1, powerToken: "RAGE", sex: 2, faction: "Horde", hostile: true, guid: "Creature-0-1-1-1-1-00000001" } } })
      pushTarget()
    } else runtime.setMock({ units: { target: false } })
    runtime.fire("PLAYER_TARGET_CHANGED")
  })
  $("g-t-name").addEventListener("change", () => { pushTarget(); runtime.fire("UNIT_NAME_UPDATE", "target") })
  $("g-t-hp").addEventListener("input", () => { pushTarget(); runtime.fire("UNIT_HEALTH", "target") })
  $("g-combat").addEventListener("change", () => {
    const on = ($("g-combat") as HTMLInputElement).checked
    runtime.setMock({ combat: on })
    runtime.fire(on ? "PLAYER_REGEN_DISABLED" : "PLAYER_REGEN_ENABLED")
  })
  writeJson("wowsb:mock", undefined)
}

// -------------------------------------------------------------- inspector
let selected: number | null = null
interface TreeNode { id: number; type: string; name?: string; shown: boolean; kids: TreeNode[]; text?: string }

function renderNode(n: TreeNode): HTMLElement {
  const wrap = document.createElement("div")
  const row = document.createElement("div")
  row.className = "n" + (n.shown ? "" : " hid") + (n.id === selected ? " sel" : "")
  const label = n.name ? `<span class="nm">${n.name}</span>` : `<i>anonymous</i>`
  row.innerHTML = `<span class="ty">${n.type}</span> ${label}${n.text ? ` <span class="muted">“${n.text.slice(0, 24).replace(/[<>&]/g, "")}”</span>` : ""}`
  row.addEventListener("click", () => select(n.id))
  wrap.appendChild(row)
  if (n.kids.length) {
    const k = document.createElement("div")
    k.className = "kids"
    for (const c of n.kids) k.appendChild(renderNode(c))
    wrap.appendChild(k)
  }
  return wrap
}
function refreshTree() {
  if (!runtime.ready) return
  const tree = runtime.frameTree() as TreeNode | null
  const holder = $("tree")
  holder.replaceChildren()
  if (tree) for (const k of tree.kids) holder.appendChild(renderNode(k))
}
function select(id: number) {
  selected = id
  renderer.highlight(id)
  const info = runtime.frameInfo(id)
  const box = $("info")
  if (!info) { box.textContent = ""; return }
  const r = info.rect ? info.rect.map((v: number) => Math.round(v * 10) / 10) : null
  box.innerHTML = `<dl>
    <dt>type</dt><dd>${info.type}</dd>
    <dt>name</dt><dd>${info.name ?? "—"}</dd>
    <dt>parent</dt><dd>${info.parent ?? "—"}</dd>
    <dt>rect</dt><dd>${r ? `x ${r[0]}  y ${r[1]}  ${r[2]} × ${r[3]}` : "unanchored"}</dd>
    <dt>points</dt><dd>${info.points.map((p: unknown[]) => `${p[0]} → ${p[1]}:${p[2]} (${p[3]}, ${p[4]})`).join("<br>") || "—"}</dd>
    <dt>shown</dt><dd>${info.shown} · visible ${info.visible} · α ${info.alpha}</dd>
    <dt>strata</dt><dd>${info.strata ?? "inherited"} · level ${info.level ?? "—"}</dd>
    <dt>scripts</dt><dd>${info.scripts.join(", ") || "—"}</dd>
    <dt>events</dt><dd>${info.events.join(", ") || "—"}</dd>
  </dl>`
  refreshTree()
}
$("btn-tree").addEventListener("click", () => { refreshTree(); if (selected) select(selected) })

// ------------------------------------------------------------- addon list
function refreshAddonList() {
  const list = $("addon-list")
  list.replaceChildren(...addons.map((a) => {
    const d = document.createElement("div")
    d.className = "addon"
    const title = (a.meta.Title ?? a.name).replace(/\|c[0-9a-fA-F]{8}|\|r/g, "")
    d.innerHTML = `<b></b> <span class="meta"></span><div class="meta"></div><div class="files"></div>`
    d.querySelector("b")!.textContent = title
    d.querySelector(".meta")!.textContent = [a.meta.Version && `v${a.meta.Version}`, a.meta.Author && `by ${a.meta.Author}`].filter(Boolean).join(" · ")
    ;(d.querySelectorAll(".meta")[1] as HTMLElement).textContent = a.meta.Notes ?? ""
    d.querySelector(".files")!.textContent = a.files.join("\n")
    d.querySelector<HTMLElement>(".files")!.style.whiteSpace = "pre-wrap"
    return d
  }))
}
$("btn-reset-sv").addEventListener("click", () => {
  svCache = {}
  writeJson("wowsb:sv", svCache)
  addLog("info", "SavedVariables cleared — reloading")
  void reload("Reset SavedVariables", { rescan: false })
})

// -------------------------------------------------------------- main loop
let last = performance.now()
let lastVer = -2
let lastTreeAt = 0
function frame(now: number) {
  const dt = Math.min(0.1, (now - last) / 1000)
  last = now
  if (runtime.ready) {
    runtime.tick(dt)
    const v = runtime.version()
    if (v !== lastVer) {
      lastVer = v
      const snap = runtime.snapshot()
      if (snap) renderer.update(snap)
      if (now - lastTreeAt > 600 && $("pane-inspect").classList.contains("on")) { lastTreeAt = now; refreshTree() }
    }
  } else lastVer = -2
  requestAnimationFrame(frame)
}
requestAnimationFrame(frame)
applyZoom()
setStatus("ready")
addLog("info", "Open an addon folder or load the sample to begin.")
if (new URLSearchParams(location.search).has("sample")) void useSource({ kind: "sample" })
