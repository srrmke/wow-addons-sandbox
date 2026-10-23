// Turns a WoW texture reference into CSS. Blizzard art can't be shipped, so well-known
// Interface\ paths get a stylised stand-in; addon-shipped images are used as-is.

export interface TexLook {
  css: Record<string, string>
  text?: string
  /** true when the base is a flat colour that backdrop/vertex colours may multiply */
  solid?: [number, number, number, number]
}

export type AssetLookup = (path: string) => string | undefined

const gold = "#e8c36a"

const KNOWN: Record<string, TexLook> = {
  "interface\\buttons\\white8x8": { css: {}, solid: [1, 1, 1, 1] },
  "interface\\chatframe\\chatframebackground": { css: {}, solid: [1, 1, 1, 1] },
  "interface\\tooltips\\ui-tooltip-background": { css: {}, solid: [1, 1, 1, 1] },
  "interface\\dialogframe\\ui-dialogbox-background": { css: {}, solid: [0.19, 0.15, 0.11, 1] },
  "interface\\dialogframe\\ui-dialogbox-background-dark": { css: {}, solid: [0.1, 0.08, 0.06, 1] },
  "interface\\buttons\\ui-panel-button-up": {
    css: { background: "linear-gradient(#8b2a1c, #4a0f09)", boxShadow: `inset 0 0 0 1px ${gold}aa, inset 0 1px 0 #ffffff33`, borderRadius: "4px" },
  },
  "interface\\buttons\\ui-panel-button-down": {
    css: { background: "linear-gradient(#3a0c07, #6a1a10)", boxShadow: `inset 0 0 0 1px ${gold}88`, borderRadius: "4px" },
  },
  "interface\\buttons\\ui-panel-button-highlight": { css: { background: "#ffffff", opacity: "0.22", borderRadius: "4px" } },
  "interface\\buttons\\ui-panel-button-disabled": {
    css: { background: "linear-gradient(#3b3b3b, #232323)", boxShadow: "inset 0 0 0 1px #666", borderRadius: "4px" },
  },
  "interface\\buttons\\ui-panel-minimizebutton-up": {
    css: { background: "linear-gradient(#a02a1e, #5b120b)", boxShadow: `inset 0 0 0 1px ${gold}`, borderRadius: "5px", margin: "5px" },
    text: "✕",
  },
  "interface\\buttons\\ui-panel-minimizebutton-down": {
    css: { background: "linear-gradient(#4a0c06, #7a1c12)", boxShadow: `inset 0 0 0 1px ${gold}`, borderRadius: "5px", margin: "5px" },
    text: "✕",
  },
  "interface\\buttons\\ui-panel-minimizebutton-highlight": { css: { background: "#fff", opacity: "0.25", borderRadius: "5px", margin: "5px" } },
  "interface\\buttons\\ui-checkbox-up": {
    css: { background: "linear-gradient(#262016, #14110b)", boxShadow: `inset 0 0 0 1px ${gold}aa`, borderRadius: "3px", margin: "4px" },
  },
  "interface\\buttons\\ui-checkbox-down": {
    css: { background: "linear-gradient(#14110b, #2c2518)", boxShadow: `inset 0 0 0 1px ${gold}`, borderRadius: "3px", margin: "4px" },
  },
  "interface\\buttons\\ui-checkbox-highlight": { css: { background: "#fff", opacity: "0.2", borderRadius: "3px", margin: "4px" } },
  "interface\\buttons\\ui-checkbox-check": { css: { color: gold, font: "bold 18px system-ui", margin: "4px" }, text: "✔" },
  "interface\\buttons\\ui-sliderbar-button-horizontal": {
    css: { background: `linear-gradient(#f3d98b, #b8923a)`, borderRadius: "3px", boxShadow: "0 0 0 1px #000a" },
  },
  "interface\\buttons\\ui-scrollbar-knob": {
    css: { background: `linear-gradient(90deg, #f3d98b, #b8923a)`, borderRadius: "3px", boxShadow: "0 0 0 1px #000a" },
  },
  "interface\\buttons\\ui-sliderbar-background": { css: {}, solid: [0, 0, 0, 0.55] },
}

const EDGES: Record<string, { color: string; width: number }> = {
  "interface\\tooltips\\ui-tooltip-border": { color: "#9d9d9d", width: 2 },
  "interface\\dialogframe\\ui-dialogbox-border": { color: "#6f5a2c", width: 3 },
  "interface\\dialogframe\\ui-dialogbox-gold-border": { color: "#c9a24a", width: 3 },
  "interface\\buttons\\ui-sliderbar-border": { color: "#6b5a2c", width: 1 },
}

export function normalizePath(p: string): string {
  return p.replace(/\//g, "\\").toLowerCase().replace(/\.(blp|tga|png|jpg|jpeg|webp)$/, "")
}

function hash(s: string): number {
  let h = 2166136261
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) }
  return h >>> 0
}

function placeholder(label: string, kind: string): TexLook {
  const h = hash(label) % 360
  return {
    css: {
      background: `linear-gradient(135deg, hsl(${h} 45% 38%), hsl(${(h + 40) % 360} 45% 24%))`,
      boxShadow: "inset 0 0 0 1px #0008",
      borderRadius: kind === "icon" ? "4px" : "0",
    },
    text: kind === "icon" ? label.replace(/.*\\/, "").replace(/^inv_?/i, "").slice(0, 3).toUpperCase() : "",
  }
}

export function lookupTexture(tex: string | number | undefined, atlas: string | undefined, assets: AssetLookup): TexLook | null {
  if (atlas) return placeholder(atlas, "atlas")
  if (tex === undefined || tex === null || tex === "") return null
  if (typeof tex === "number") return placeholder(String(tex), "icon")
  const key = normalizePath(tex)
  const known = KNOWN[key]
  if (known) return known
  const url = assets(tex)
  if (url) return { css: { backgroundImage: `url("${url}")`, backgroundSize: "100% 100%", backgroundRepeat: "no-repeat" } }
  if (key.startsWith("interface\\icons\\")) return placeholder(key, "icon")
  return placeholder(key, "tex")
}

export interface Edge { color: string; width: number }
export function lookupEdge(path: string | undefined, edgeSize: number): Edge | null {
  if (!path) return null
  const key = normalizePath(path)
  const known = EDGES[key]
  if (known) return known
  if (key.includes("white8x8") || key.includes("chatframebackground")) return { color: "#fff", width: Math.max(1, edgeSize || 1) }
  return { color: "#bbb", width: Math.max(1, Math.min(4, (edgeSize || 8) / 4)) }
}

export function solidOf(path: string | undefined): [number, number, number, number] | null {
  if (!path) return null
  const k = KNOWN[normalizePath(path)]
  if (k?.solid) return k.solid
  return null
}

export function rgba(c: number[] | undefined, mul: [number, number, number, number] = [1, 1, 1, 1]): string {
  const r = Math.round(255 * (c ? c[0] : 1) * mul[0])
  const g = Math.round(255 * (c ? c[1] : 1) * mul[1])
  const b = Math.round(255 * (c ? c[2] : 1) * mul[2])
  const a = (c ? (c[3] ?? 1) : 1) * mul[3]
  return `rgba(${r},${g},${b},${a})`
}
