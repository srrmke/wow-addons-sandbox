// Font mapping and text measurement shared by the Lua bridge and the renderer.

export function fontFamily(path: string): string {
  const p = (path || "").toLowerCase()
  if (p.includes("arialn")) return '"Arial Narrow", "Helvetica Neue", Arial, sans-serif'
  if (p.includes("morpheus")) return '"Palatino Linotype", Palatino, Georgia, serif'
  if (p.includes("skurri")) return '"Trebuchet MS", "Segoe UI", sans-serif'
  if (p.includes("ariblk") || p.includes("2002")) return '"Arial Black", Arial, sans-serif'
  return '"Friz Quadrata TT", "Trebuchet MS", "Segoe UI", system-ui, sans-serif'
}

export const LINE_HEIGHT = 1.2

/** Remove |c..|r colour codes, |H..|h hyperlinks and |T..|t inline textures; |n becomes a newline. */
export function stripEscapes(text: string): string {
  return text
    .replace(/\|T[^|]*\|t/g, "  ")
    .replace(/\|c[0-9a-fA-F]{8}/g, "")
    .replace(/\|r/g, "")
    .replace(/\|H[^|]*\|h/g, "")
    .replace(/\|h/g, "")
    .replace(/\|n/g, "\n")
    .replace(/\|\|/g, "|")
}

let ctx: CanvasRenderingContext2D | null = null
const widthCache = new Map<string, number>()

function measureLine(line: string, path: string, size: number, flags: string): number {
  const key = `${path}|${size}|${flags}|${line}`
  const hit = widthCache.get(key)
  if (hit !== undefined) return hit
  if (!ctx) ctx = document.createElement("canvas").getContext("2d")!
  ctx.font = `${size}px ${fontFamily(path)}`
  const w = ctx.measureText(line).width
  if (widthCache.size > 20000) widthCache.clear()
  widthCache.set(key, w)
  return w
}

/** Size in pixels of an inline |Tpath:height:width:...|t texture. Height 0 (or none) means the font size; width defaults to height. */
export function inlineTextureSize(spec: string, fontSize: number): { w: number; h: number } {
  const p = spec.split(":")
  const h = Number(p[1]) || 0
  const w = p[2] !== undefined && p[2] !== "" ? Number(p[2]) || 0 : h
  const hh = h || fontSize
  return { w: w || hh, h: hh }
}

// Inline textures become private-use characters (U+E000 + index) so lines can be measured and wrapped with them.
const PUA = 0xe000
const PUA_RE = /[-]/g
function withIcons(text: string, size: number): { text: string; icons: number[] } {
  const icons: number[] = []
  const out = text.replace(/\|T([^|]*)\|t/g, (_m, spec: string) => {
    icons.push(inlineTextureSize(spec, size).w)
    return String.fromCharCode(PUA + Math.min(icons.length - 1, 0x18ff))
  })
  return { text: stripEscapes(out), icons }
}
function lineWidth(line: string, icons: number[], path: string, size: number, flags: string): number {
  let extra = 0
  const plain = line.replace(PUA_RE, (c) => { extra += icons[c.charCodeAt(0) - PUA] ?? size; return "" })
  return measureLine(plain, path, size, flags) + extra
}

export function measureWidth(text: string, path: string, size: number, flags: string): number {
  const { text: t, icons } = withIcons(text, size)
  let max = 0
  for (const line of t.split("\n")) max = Math.max(max, lineWidth(line, icons, path, size, flags))
  return max
}

export function measureHeight(text: string, path: string, size: number, flags: string, wrapWidth: number): number {
  const { text: t, icons } = withIcons(text, size)
  let count = 0
  for (const line of t.split("\n")) {
    if (!wrapWidth || wrapWidth <= 0) { count++; continue }
    let cur = ""
    let n = 1
    for (const word of line.split(" ")) {
      const next = cur ? cur + " " + word : word
      if (cur && lineWidth(next, icons, path, size, flags) > wrapWidth) { n++; cur = word } else cur = next
    }
    count += n
  }
  return count * size * LINE_HEIGHT
}
