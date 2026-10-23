import { fontFamily, stripEscapes } from "./fonts"
import { lookupEdge, lookupTexture, rgba, solidOf, type AssetLookup } from "./textures"

export interface Item {
  id: number
  k: "frame" | "tex" | "fs"
  x: number; y: number; w: number; h: number; z: number; a: number; p: number
  clip?: [number, number, number, number]
  // frame
  ft?: string; name?: string; pe?: boolean; hit?: number[]; round?: boolean; cl?: boolean; chk?: boolean; dis?: boolean
  bd?: { bg?: string; edge?: string; tile?: boolean; edgeSize: number; tileSize?: number; ins: number[]; bgc?: number[]; edgec?: number[] }
  ed?: { text: string; multi?: boolean; pw?: boolean; num?: boolean; font: string; size: number; flags: string; col: number[]; ins?: number[]; jh?: string; focus?: boolean; max?: number }
  sl?: { min: number; max: number; val: number; step: number; orient: string; dis?: boolean }
  sb?: { min: number; max: number; val: number; col?: number[]; orient: string; rev?: boolean; tex?: string | number; vc?: number[] }
  msgs?: [string, number, number, number][]
  mf?: { font: string; size: number; flags: string; jh?: string }
  // texture
  tex?: string | number; atlas?: string; col?: number[]; vc?: number[]; tc?: number[]; blend?: string; desat?: boolean; rot?: number
  grad?: [string, number[], number[]]; htile?: boolean; vtile?: boolean; label?: string
  // fontstring
  txt?: string; font?: string; size?: number; flags?: string; jh?: string; jv?: string; sh?: number[]; wrap?: boolean; ml?: number; sp?: number
}

export interface Snapshot { ver: number; w: number; h: number; items: Item[] }

export interface InputSink {
  mouse(id: number, ev: string, button?: string, extra?: number): void
  edit(id: number, ev: string, text?: string): void
  cursor(x: number, y: number): void
}

const BUTTONS = ["LeftButton", "MiddleButton", "RightButton"]

function mapBtn(b: number): string { return BUTTONS[b] ?? `Button${b + 1}` }

function parseHex(hex: string): [number, number, number, number] {
  const h = hex.replace("#", "")
  const full = h.length === 3 ? h.split("").map((c) => c + c).join("") : h
  return [parseInt(full.slice(0, 2), 16) / 255, parseInt(full.slice(2, 4), 16) / 255, parseInt(full.slice(4, 6), 16) / 255, 1]
}

export class Renderer {
  private els = new Map<number, HTMLElement>()
  private sigs = new Map<number, string>()
  private overlay: HTMLElement
  private lastVer = -1
  items: Item[] = []
  screenH = 720

  constructor(private stage: HTMLElement, private input: InputSink, private assets: AssetLookup) {
    this.overlay = document.createElement("div")
    this.overlay.className = "inspect-overlay"
    stage.appendChild(this.overlay)
  }

  clear() {
    for (const el of this.els.values()) el.remove()
    this.els.clear()
    this.sigs.clear()
    this.lastVer = -1
  }

  highlight(id: number | null) {
    const it = id == null ? undefined : this.items.find((i) => i.id === id)
    if (!it) { this.overlay.style.display = "none"; return }
    Object.assign(this.overlay.style, { display: "block", left: it.x + "px", top: it.y + "px", width: it.w + "px", height: it.h + "px" })
  }

  update(snap: Snapshot) {
    if (snap.ver === this.lastVer) return
    this.lastVer = snap.ver
    this.items = snap.items
    this.screenH = snap.h
    const seen = new Set<number>()
    let structural = false
    for (const it of snap.items) {
      seen.add(it.id)
      let el = this.els.get(it.id)
      if (!el) {
        el = this.create(it)
        this.els.set(it.id, el)
        this.stage.appendChild(el)
        structural = true
      }
      const sig = JSON.stringify(it)
      if (this.sigs.get(it.id) !== sig) {
        this.sigs.set(it.id, sig)
        if (it.k === "frame") this.fillFrame(el, it)
        else if (it.k === "tex") this.fillTexture(el, it)
        else this.fillText(el, it)
      }
    }
    for (const [id, el] of this.els) {
      if (!seen.has(id)) { el.remove(); this.els.delete(id); this.sigs.delete(id); structural = true }
    }
    if (structural) {
      for (const it of snap.items) this.stage.appendChild(this.els.get(it.id)!)
      this.stage.appendChild(this.overlay)
    }
  }

  private create(it: Item): HTMLElement {
    const el = document.createElement("div")
    el.className = it.k === "frame" ? "f" : it.k === "tex" ? "t" : "s"
    if (it.k === "frame") this.bind(el, it.id)
    return el
  }

  private bind(el: HTMLElement, id: number) {
    let down: { x: number; y: number; btn: string; dragged: boolean } | null = null
    el.addEventListener("pointerenter", () => this.input.mouse(id, "enter"))
    el.addEventListener("pointerleave", () => this.input.mouse(id, "leave"))
    el.addEventListener("pointerdown", (e) => {
      const btn = mapBtn(e.button)
      down = { x: e.clientX, y: e.clientY, btn, dragged: false }
      this.input.mouse(id, "down", btn)
      const move = (m: PointerEvent) => {
        if (!down || down.dragged) return
        if (Math.hypot(m.clientX - down.x, m.clientY - down.y) > 4) {
          down.dragged = true
          this.input.mouse(id, "dragstart", down.btn)
        }
      }
      const up = (u: PointerEvent) => {
        window.removeEventListener("pointermove", move)
        window.removeEventListener("pointerup", up)
        if (!down) return
        const dragged = down.dragged
        const b = down.btn
        down = null
        if (dragged) this.input.mouse(id, "dragstop", b)
        this.input.mouse(id, "up", mapBtn(u.button))
      }
      window.addEventListener("pointermove", move)
      window.addEventListener("pointerup", up)
    })
    el.addEventListener("wheel", (e) => {
      e.preventDefault()
      this.input.mouse(id, "wheel", undefined, e.deltaY < 0 ? 1 : -1)
    }, { passive: false })
    el.addEventListener("contextmenu", (e) => e.preventDefault())
  }

  private base(el: HTMLElement, it: Item) {
    const s = el.style
    s.left = it.x + "px"
    s.top = it.y + "px"
    s.width = it.w + "px"
    s.height = it.h + "px"
    s.zIndex = String(it.z)
    s.opacity = String(it.a)
    if (it.clip) {
      const c = it.clip
      s.clipPath = `inset(${c[1] - it.y}px ${it.x + it.w - (c[0] + c[2])}px ${it.y + it.h - (c[1] + c[3])}px ${c[0] - it.x}px)`
    } else s.clipPath = ""
  }

  private sub(el: HTMLElement, name: string, tag = "div"): HTMLElement {
    let c = el.querySelector<HTMLElement>(`:scope > [data-sub="${name}"]`)
    if (!c) {
      c = document.createElement(tag)
      c.dataset.sub = name
      c.className = "sub " + name
      el.appendChild(c)
    }
    return c
  }
  private dropSub(el: HTMLElement, name: string) {
    el.querySelector(`:scope > [data-sub="${name}"]`)?.remove()
  }

  // ---------------------------------------------------------------- frames
  private fillFrame(el: HTMLElement, it: Item) {
    this.base(el, it)
    el.dataset.type = it.ft
    el.style.pointerEvents = it.pe ? "auto" : "none"
    el.style.borderRadius = it.round ? "50%" : ""
    el.classList.toggle("round", !!it.round)
    el.classList.toggle("disabled", !!it.dis)
    el.title = ""

    // backdrop
    if (it.bd) {
      const bd = it.bd
      const bg = this.sub(el, "bdbg")
      const [il, ir, itop, ib] = bd.ins
      Object.assign(bg.style, { left: il + "px", right: ir + "px", top: itop + "px", bottom: ib + "px", background: "", backgroundColor: "", opacity: "1" })
      const solid = solidOf(bd.bg)
      if (bd.bg) {
        if (solid) bg.style.backgroundColor = rgba(bd.bgc, solid)
        else {
          const look = lookupTexture(bd.bg, undefined, this.assets)
          if (look) {
            Object.assign(bg.style, look.css)
            bg.style.opacity = String(bd.bgc ? (bd.bgc[3] ?? 1) : 1)
            if (bd.tile && look.css.backgroundImage) { bg.style.backgroundSize = (bd.tileSize || 32) + "px"; bg.style.backgroundRepeat = "repeat" }
          }
        }
      }
      const edge = lookupEdge(bd.edge, bd.edgeSize)
      if (edge) {
        const e = this.sub(el, "bdedge")
        const c = parseHex(edge.color)
        e.style.border = `${edge.width}px solid ${rgba(bd.edgec, c)}`
      } else this.dropSub(el, "bdedge")
    } else { this.dropSub(el, "bdbg"); this.dropSub(el, "bdedge") }

    // hit rect insets
    if (it.hit) { /* handled by pointer events on the element box only */ }

    // status bar fill
    if (it.sb) {
      const sb = it.sb
      const fill = this.sub(el, "fill")
      const frac = sb.max > sb.min ? Math.max(0, Math.min(1, (sb.val - sb.min) / (sb.max - sb.min))) : 0
      const vert = sb.orient === "VERTICAL"
      const look = lookupTexture(sb.tex, undefined, this.assets)
      const c = sb.col ?? sb.vc
      Object.assign(fill.style, {
        left: sb.rev && !vert ? "auto" : "0", right: sb.rev && !vert ? "0" : "auto", top: vert ? "auto" : "0", bottom: "0",
        width: vert ? "100%" : frac * 100 + "%", height: vert ? frac * 100 + "%" : "100%", background: "", backgroundColor: "",
      })
      if (look && !look.solid) {
        Object.assign(fill.style, look.css)
        fill.style.backgroundSize = "100% 100%"
        if (c) { fill.style.backgroundColor = rgba(c); fill.style.backgroundBlendMode = "multiply" }
      } else {
        fill.style.backgroundColor = rgba(c)
      }
    } else this.dropSub(el, "fill")

    // edit box
    if (it.ed) this.fillEdit(el, it)
    else this.dropSub(el, "input")

    // slider interaction
    if (it.sl) this.fillSlider(el, it)

    // scrolling message frame
    if (it.msgs && it.mf) {
      const m = this.sub(el, "msgs")
      m.style.font = `${it.mf.size}px ${fontFamily(it.mf.font)}`
      m.style.textAlign = (it.mf.jh || "LEFT").toLowerCase()
      m.replaceChildren(...it.msgs.map((line) => {
        const d = document.createElement("div")
        d.style.color = rgba([line[1], line[2], line[3], 1])
        rich(d, line[0])
        return d
      }))
      m.scrollTop = m.scrollHeight
    } else this.dropSub(el, "msgs")
  }

  private fillEdit(el: HTMLElement, it: Item) {
    const ed = it.ed!
    const tag = ed.multi ? "textarea" : "input"
    let inp = el.querySelector<HTMLInputElement | HTMLTextAreaElement>(":scope > .sub.input")
    if (inp && inp.tagName.toLowerCase() !== tag) { inp.remove(); inp = null }
    if (!inp) {
      inp = document.createElement(tag) as HTMLInputElement | HTMLTextAreaElement
      inp.className = "sub input"
      inp.dataset.sub = "input"
      inp.spellcheck = false
      inp.autocomplete = "off"
      inp.addEventListener("pointerdown", (e) => e.stopPropagation())
      inp.addEventListener("input", () => this.input.edit(it.id, "text", inp!.value))
      inp.addEventListener("focus", () => this.input.edit(it.id, "focus"))
      inp.addEventListener("blur", () => this.input.edit(it.id, "blur"))
      inp.addEventListener("keydown", (e: Event) => {
        const ke = e as KeyboardEvent
        e.stopPropagation()
        if (ke.key === "Enter" && !ed.multi) this.input.edit(it.id, "enter")
        else if (ke.key === "Escape") this.input.edit(it.id, "escape")
        else if (ke.key === "Tab") { e.preventDefault(); this.input.edit(it.id, "tab") }
      })
      el.appendChild(inp)
    }
    if (inp.value !== ed.text) inp.value = ed.text
    if (!ed.multi) (inp as HTMLInputElement).type = ed.pw ? "password" : "text"
    if (ed.max) inp.maxLength = ed.max
    const ins = ed.ins ?? [0, 0, 0, 0]
    Object.assign(inp.style, {
      left: ins[0] + "px", right: ins[1] + "px", top: ins[2] + "px", bottom: ins[3] + "px",
      font: `${ed.size}px ${fontFamily(ed.font)}`, color: rgba(ed.col), textAlign: (ed.jh || "LEFT").toLowerCase(),
    })
    if (ed.focus && document.activeElement !== inp) inp.focus()
  }

  private fillSlider(el: HTMLElement, it: Item) {
    const sl = it.sl!
    const vert = sl.orient === "VERTICAL"
    el.onpointerdown = (e) => {
      if (sl.dis) return
      const r = el.getBoundingClientRect()
      const scale = r.width / it.w || 1
      const set = (ev: PointerEvent) => {
        let frac = vert ? 1 - (ev.clientY - r.top) / (it.h * scale) : (ev.clientX - r.left) / (it.w * scale)
        frac = Math.max(0, Math.min(1, frac))
        this.input.mouse(it.id, "slider", undefined, sl.min + frac * (sl.max - sl.min))
      }
      set(e)
      const mv = (m: PointerEvent) => set(m)
      const up = () => { window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up) }
      window.addEventListener("pointermove", mv)
      window.addEventListener("pointerup", up)
      e.stopPropagation()
    }
  }

  // -------------------------------------------------------------- textures
  private fillTexture(el: HTMLElement, it: Item) {
    this.base(el, it)
    const s = el.style
    el.textContent = ""
    el.className = "t"
    s.pointerEvents = "none"
    s.background = ""; s.backgroundColor = ""; s.mixBlendMode = ""; s.filter = ""; s.transform = ""; s.boxShadow = ""; s.borderRadius = ""
    s.margin = ""; s.color = ""; s.font = ""; s.maskImage = ""

    let look = lookupTexture(it.tex, it.atlas, this.assets)
    let tint: [number, number, number, number] = [1, 1, 1, 1]
    if (it.vc) tint = [it.vc[0], it.vc[1], it.vc[2], it.vc[3] ?? 1]

    if (it.col) {
      s.backgroundColor = rgba(it.col, tint)
    } else if (look) {
      if (look.solid) {
        s.backgroundColor = rgba(look.solid, tint)
      } else {
        Object.assign(s, look.css)
        if (look.css.opacity) s.opacity = String(it.a * parseFloat(look.css.opacity))
        if (look.css.margin) {
          const m = parseFloat(look.css.margin)
          s.margin = ""
          s.left = it.x + m + "px"; s.top = it.y + m + "px"; s.width = it.w - 2 * m + "px"; s.height = it.h - 2 * m + "px"
        }
        const img = look.css.backgroundImage
        const white = tint[0] === 1 && tint[1] === 1 && tint[2] === 1
        if (img && !white) {
          s.backgroundColor = rgba([tint[0], tint[1], tint[2], 1])
          s.backgroundBlendMode = "multiply"
          s.maskImage = img
          s.setProperty("-webkit-mask-image", img)
          s.setProperty("-webkit-mask-size", "100% 100%")
        } else if (tint[3] !== 1) s.opacity = String(it.a * tint[3])
        else if (!img && !white) s.filter = `brightness(${(tint[0] + tint[1] + tint[2]) / 3})`
        if (it.tc && img) this.applyTexCoord(el, it, img)
        if (it.htile || it.vtile) {
          s.backgroundRepeat = `${it.htile ? "repeat" : "no-repeat"} ${it.vtile ? "repeat" : "no-repeat"}`
          s.backgroundSize = "auto"
        }
      }
      if (look.text) {
        el.textContent = look.text
        Object.assign(s, { display: "flex", alignItems: "center", justifyContent: "center", color: look.css.color || "#fff", fontSize: look.css.font ? "" : "10px", fontWeight: "600" })
        if (look.css.font) s.font = look.css.font
      }
    }
    if (it.grad) {
      const [o, mn, mx] = it.grad
      const dir = o === "HORIZONTAL" ? "to right" : "to top"
      s.background = `linear-gradient(${dir}, ${rgba(mn)}, ${rgba(mx)})`
    }
    if (it.blend === "ADD") s.mixBlendMode = "plus-lighter"
    if (it.desat) s.filter = (s.filter ? s.filter + " " : "") + "grayscale(1)"
    if (it.rot) s.transform = `rotate(${-it.rot}rad)`
  }

  private applyTexCoord(el: HTMLElement, it: Item, img: string) {
    const tc = it.tc!
    let l: number, r: number, t: number, b: number
    if (tc.length === 8) { l = Math.min(tc[0], tc[2], tc[4], tc[6]); r = Math.max(tc[0], tc[2], tc[4], tc[6]); t = Math.min(tc[1], tc[3], tc[5], tc[7]); b = Math.max(tc[1], tc[3], tc[5], tc[7]) }
    else [l, r, t, b] = tc
    const flipX = l > r, flipY = t > b
    if (flipX) [l, r] = [r, l]
    if (flipY) [t, b] = [b, t]
    const bw = it.w / Math.max(r - l, 0.0001), bh = it.h / Math.max(b - t, 0.0001)
    const s = el.style
    s.backgroundImage = img
    s.backgroundRepeat = "no-repeat"
    s.backgroundSize = `${bw}px ${bh}px`
    s.backgroundPosition = `${-l * bw}px ${-t * bh}px`
    if (flipX || flipY) s.transform = `scale(${flipX ? -1 : 1}, ${flipY ? -1 : 1})`
  }

  // ------------------------------------------------------------ fontstrings
  private fillText(el: HTMLElement, it: Item) {
    this.base(el, it)
    const s = el.style
    const jh = it.jh || "CENTER"
    s.pointerEvents = "none"
    // a little slack so auto-sized text never wraps because of sub-pixel differences
    const slack = it.wrap && it.ml !== 1 ? 2 : 0
    s.width = it.w + slack + "px"
    s.left = it.x - (jh === "RIGHT" ? slack : jh === "CENTER" ? slack / 2 : 0) + "px"
    s.font = `${it.size}px/1.2 ${fontFamily(it.font || "")}`
    s.color = rgba(it.col)
    s.whiteSpace = it.wrap ? "pre-wrap" : "pre"
    s.textAlign = jh.toLowerCase()
    s.display = "flex"
    s.flexDirection = "column"
    s.justifyContent = it.jv === "TOP" ? "flex-start" : it.jv === "BOTTOM" ? "flex-end" : "center"
    s.alignItems = jh === "LEFT" ? "flex-start" : jh === "RIGHT" ? "flex-end" : "center"
    const shadows: string[] = []
    if (it.flags && /OUTLINE/i.test(it.flags)) shadows.push("1px 0 #000", "-1px 0 #000", "0 1px #000", "0 -1px #000")
    if (it.sh) shadows.push(`${it.sh[0]}px ${-it.sh[1]}px 0 ${rgba([it.sh[2], it.sh[3], it.sh[4], it.sh[5]])}`)
    s.textShadow = shadows.join(",")
    const inner = document.createElement("div")
    inner.style.width = "100%"
    inner.style.textAlign = jh.toLowerCase()
    if (it.ml) { inner.style.overflow = "hidden"; inner.style.maxHeight = it.ml * (it.size || 12) * 1.2 + "px" }
    rich(inner, it.txt || "")
    el.replaceChildren(inner)
  }
}

/** Render WoW text escapes (|cAARRGGBB, |r, |n, |T..|t, hyperlinks) into DOM. */
export function rich(container: HTMLElement, text: string) {
  container.textContent = ""
  const re = /\|c([0-9a-fA-F]{8})|\|r|\|n|\|T([^|]*)\|t|\|H[^|]*\|h|\|h|\|\|/g
  let color: string | null = null
  let last = 0
  const push = (str: string) => {
    if (!str) return
    const span = document.createElement("span")
    span.textContent = str
    if (color) span.style.color = color
    container.appendChild(span)
  }
  for (let m = re.exec(text); m; m = re.exec(text)) {
    push(text.slice(last, m.index))
    last = m.index + m[0].length
    if (m[1]) color = `#${m[1].slice(2)}`
    else if (m[0] === "|r") color = null
    else if (m[0] === "|n") container.appendChild(document.createTextNode("\n"))
    else if (m[0] === "||") push("|")
    else if (m[2] !== undefined) {
      const i = document.createElement("span")
      i.className = "inline-tex"
      i.title = m[2].split(":")[0]
      container.appendChild(i)
    }
  }
  push(text.slice(last))
  if (!container.childNodes.length) container.textContent = stripEscapes(text)
}
