import { LuaFactory, type LuaEngine } from "wasmoon"
import wasmUrl from "wasmoon/dist/glue.wasm?url"
import core from "./lua/00_core.lua?raw"
import frames from "./lua/10_frames.lua?raw"
import xml from "./lua/20_xml.lua?raw"
import api from "./lua/30_api.lua?raw"
import type { Addon } from "./addons"
import { normKey } from "./addons"
import { measureHeight, measureWidth } from "./fonts"
import type { Snapshot } from "./render"

const PRELUDE = [core, frames, xml, api].join("\n")

export type LogKind = "chat" | "error" | "warn" | "info" | "ui"

export interface RuntimeHost {
  log(kind: LogKind, text: string, r?: number, g?: number, b?: number): void
  requestReload(): void
}

interface XmlNode { t: string; a: Record<string, string>; c: XmlNode[]; x?: string }

function toTree(el: Element): XmlNode {
  const a: Record<string, string> = {}
  for (const at of Array.from(el.attributes)) a[at.name] = at.value
  const c: XmlNode[] = []
  let text = ""
  for (const n of Array.from(el.childNodes)) {
    if (n.nodeType === 1) c.push(toTree(n as Element))
    else if (n.nodeType === 3 || n.nodeType === 4) text += n.nodeValue ?? ""
  }
  const node: XmlNode = { t: el.localName, a, c }
  if (text.trim()) node.x = text
  return node
}

export function xmlToJson(text: string): string | undefined {
  const doc = new DOMParser().parseFromString(text, "application/xml")
  const err = doc.querySelector("parsererror")
  if (err) throw new Error(err.textContent?.split("\n")[0] ?? "XML parse error")
  return JSON.stringify(toTree(doc.documentElement))
}

type LuaFn = (...args: unknown[]) => unknown

export class Runtime {
  private lua: LuaEngine | null = null
  private fn: Record<string, LuaFn> = {}
  private factory = new LuaFactory(wasmUrl)
  addons: Addon[] = []
  ready = false

  constructor(private host: RuntimeHost) {}

  /** Build a fresh Lua state and run every addon through its TOC. */
  async boot(addons: Addon[], opts: { w: number; h: number; mock?: string; sv: Record<string, string> }) {
    this.ready = false
    if (this.lua) { try { this.lua.global.close() } catch { /* already closed */ } }
    this.addons = addons
    const lua = await this.factory.createEngine()
    this.lua = lua
    const byName = new Map(addons.map((a) => [a.name, a]))

    lua.global.set("__log", (kind: string, text: string, r?: number, g?: number, b?: number) => this.host.log(kind as LogKind, String(text), r, g, b))
    lua.global.set("__measureW", (t: string, p: string, s: number, f: string) => measureWidth(String(t), p, s, f))
    lua.global.set("__measureH", (t: string, p: string, s: number, f: string, w: number) => measureHeight(String(t), p, s, f, w))
    lua.global.set("__reload", () => this.host.requestReload())
    lua.global.set("__readFile", (addon: string, path: string) => byName.get(addon)?.text.get(normKey(path)))
    lua.global.set("__readXml", (addon: string, path: string) => {
      const src = byName.get(addon)?.text.get(normKey(path))
      if (src === undefined) return undefined
      try { return xmlToJson(src) } catch (e) {
        this.host.log("error", `${path}: ${(e as Error).message}`)
        return undefined
      }
    })

    await lua.doString(PRELUDE)
    for (const name of ["__Tick", "__Snapshot", "__Ver", "__FireEvent", "__Mouse", "__MouseMove", "__EditInput", "__Key", "__Slash", "__SetMock",
      "__GetMock", "__DumpSV", "__FrameInfo", "__FrameTree", "__SetScreen", "__BeginAddon", "__RunFile", "__EndAddon"]) {
      this.fn[name] = lua.global.get(name) as LuaFn
    }
    this.call("__SetScreen", opts.w, opts.h)
    if (opts.mock) this.call("__SetMock", opts.mock)

    for (const a of addons) {
      this.call("__BeginAddon", a.name, JSON.stringify(a.meta), opts.sv[a.name])
      for (const f of a.files) this.call("__RunFile", a.name, f)
      this.call("__EndAddon", a.name)
    }
    this.fire("VARIABLES_LOADED")
    this.fire("PLAYER_LOGIN")
    this.fire("PLAYER_ENTERING_WORLD", true, false)
    this.ready = true
  }

  private call(name: string, ...args: unknown[]): unknown {
    const f = this.fn[name]
    if (!f) return undefined
    try { return f(...args) } catch (e) {
      this.host.log("error", `[sandbox] ${name}: ${(e as Error).message}`)
      return undefined
    }
  }

  tick(dt: number) { if (this.ready) this.call("__Tick", dt) }
  version(): number { return this.ready ? (this.call("__Ver") as number) : -1 }
  snapshot(): Snapshot | null {
    if (!this.ready) return null
    const json = this.call("__Snapshot") as string | undefined
    return json ? (JSON.parse(json) as Snapshot) : null
  }
  fire(event: string, ...args: unknown[]) { this.call("__FireEvent", event, ...args) }
  mouse(id: number, ev: string, btn?: string, extra?: number) { this.call("__Mouse", id, ev, btn ?? "LeftButton", extra) }
  mouseMove(x: number, y: number) { this.call("__MouseMove", x, y) }
  edit(id: number, ev: string, text?: string) { this.call("__EditInput", id, ev, text ?? "") }
  key(key: string, down: boolean) { this.call("__Key", key, down) }
  slash(line: string) { this.call("__Slash", line) }
  setMock(patch: unknown) { this.call("__SetMock", JSON.stringify(patch)) }
  getMock(): any { return JSON.parse((this.call("__GetMock") as string) ?? "{}") }
  setScreen(w: number, h: number) { this.call("__SetScreen", w, h) }
  frameInfo(id: number): any { const j = this.call("__FrameInfo", id) as string; return j ? JSON.parse(j) : null }
  frameTree(): any { const j = this.call("__FrameTree") as string; return j ? JSON.parse(j) : null }
  dumpSavedVariables(): Record<string, Record<string, unknown>> {
    const j = this.call("__DumpSV") as string | undefined
    return j ? JSON.parse(j) : {}
  }
  /** Raw SV JSON strings per addon, in the Lua-side encoding (keeps numeric keys). */
  dumpSavedVariablesRaw(): Record<string, string> {
    const out: Record<string, string> = {}
    for (const [k, v] of Object.entries(this.dumpSavedVariables())) out[k] = JSON.stringify(v)
    return out
  }
}
