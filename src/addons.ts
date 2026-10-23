// Reading addon folders (File System Access API or <input webkitdirectory>) into in-memory addons.

export interface Addon {
  name: string
  meta: Record<string, string>
  /** TOC file entries in load order, relative to the addon folder, '/' separated */
  files: string[]
  /** lower-cased relative path -> text content (lua, xml, toc) */
  text: Map<string, string>
  /** lower-cased relative path (no extension) -> object URL of a displayable image */
  images: Map<string, string>
  dependencies: string[]
}

export interface RawFile { path: string; read(): Promise<ArrayBuffer>; lastModified: number; size: number }

const TEXT_EXT = /\.(lua|xml|toc)$/i
const IMG_EXT = /\.(png|jpe?g|webp|tga|gif)$/i

export function normKey(p: string): string {
  return p.replace(/\\/g, "/").replace(/^\.\//, "").toLowerCase()
}

export function parseToc(text: string): { meta: Record<string, string>; files: string[] } {
  const meta: Record<string, string> = {}
  const files: string[] = []
  for (const raw of text.replace(/^﻿/, "").split(/\r?\n/)) {
    const line = raw.trim()
    if (!line) continue
    if (line.startsWith("##")) {
      const m = line.match(/^##\s*([^:]+?)\s*:\s*(.*)$/)
      if (m) meta[m[1]] = m[2]
    } else if (!line.startsWith("#")) {
      files.push(line.replace(/\\/g, "/").replace(/\s+\[.*\]$/, ""))
    }
  }
  return { meta, files }
}

function decodeTga(buf: ArrayBuffer): string | null {
  const d = new DataView(buf)
  if (buf.byteLength < 18) return null
  const idLen = d.getUint8(0), cmType = d.getUint8(1), type = d.getUint8(2)
  const w = d.getUint16(12, true), h = d.getUint16(14, true), bpp = d.getUint8(16), desc = d.getUint8(17)
  if (cmType !== 0 || (type !== 2 && type !== 10) || (bpp !== 24 && bpp !== 32) || !w || !h) return null
  const bytes = bpp / 8
  const px = new Uint8ClampedArray(w * h * 4)
  let p = 18 + idLen
  const src = new Uint8Array(buf)
  const put = (i: number, o: number) => {
    px[i] = src[o + 2]; px[i + 1] = src[o + 1]; px[i + 2] = src[o]; px[i + 3] = bytes === 4 ? src[o + 3] : 255
  }
  let i = 0
  if (type === 2) {
    for (; i < w * h; i++, p += bytes) put(i * 4, p)
  } else {
    while (i < w * h && p < src.length) {
      const hdr = src[p++]
      const n = (hdr & 127) + 1
      if (hdr & 128) { for (let k = 0; k < n && i < w * h; k++, i++) put(i * 4, p); p += bytes }
      else for (let k = 0; k < n && i < w * h; k++, i++, p += bytes) put(i * 4, p)
    }
  }
  const out = new Uint8ClampedArray(w * h * 4)
  const topDown = (desc & 0x20) !== 0
  for (let y = 0; y < h; y++) {
    const sy = topDown ? y : h - 1 - y
    out.set(px.subarray(sy * w * 4, (sy + 1) * w * 4), y * w * 4)
  }
  const c = document.createElement("canvas")
  c.width = w; c.height = h
  c.getContext("2d")!.putImageData(new ImageData(out, w, h), 0, 0)
  return c.toDataURL("image/png")
}

async function loadAddon(name: string, files: RawFile[], prefix: string): Promise<Addon | null> {
  const rel = (f: RawFile) => f.path.slice(prefix.length)
  const toc = files.find((f) => rel(f).toLowerCase() === `${name.toLowerCase()}.toc`) ??
    files.find((f) => /^[^/]+\.toc$/i.test(rel(f)))
  if (!toc) return null
  const dec = new TextDecoder("utf-8")
  const { meta, files: listed } = parseToc(dec.decode(await toc.read()))
  const text = new Map<string, string>()
  const images = new Map<string, string>()
  for (const f of files) {
    const r = rel(f)
    if (TEXT_EXT.test(r)) text.set(normKey(r), dec.decode(await f.read()).replace(/^﻿/, ""))
    else if (IMG_EXT.test(r)) {
      const buf = await f.read()
      const key = normKey(r).replace(/\.[^./]+$/, "")
      if (/\.tga$/i.test(r)) {
        const url = decodeTga(buf)
        if (url) images.set(key, url)
      } else images.set(key, URL.createObjectURL(new Blob([buf])))
    }
  }
  const deps = [meta.Dependencies, meta.RequiredDeps, meta.Dependency, meta.OptionalDeps]
    .filter(Boolean).join(",").split(",").map((s) => s.trim()).filter(Boolean)
  return { name, meta, files: listed, text, images, dependencies: deps }
}

/** Accepts either one addon folder (contains a .toc) or an AddOns folder holding several. */
export async function loadFromFiles(rootName: string, files: RawFile[]): Promise<Addon[]> {
  const direct = files.filter((f) => !f.path.includes("/"))
  const addons: Addon[] = []
  if (direct.some((f) => /\.toc$/i.test(f.path))) {
    const a = await loadAddon(rootName, files, "")
    if (a) addons.push(a)
  } else {
    const groups = new Map<string, RawFile[]>()
    for (const f of files) {
      const top = f.path.split("/")[0]
      if (!f.path.includes("/")) continue
      groups.set(top, [...(groups.get(top) ?? []), f])
    }
    for (const [name, list] of groups) {
      const a = await loadAddon(name, list, name + "/")
      if (a) addons.push(a)
    }
  }
  return orderByDependencies(addons)
}

export function orderByDependencies(addons: Addon[]): Addon[] {
  const by = new Map(addons.map((a) => [a.name.toLowerCase(), a]))
  const out: Addon[] = []
  const state = new Map<string, number>()
  const visit = (a: Addon) => {
    const k = a.name.toLowerCase()
    if (state.get(k)) return
    state.set(k, 1)
    for (const d of a.dependencies) { const dep = by.get(d.toLowerCase()); if (dep) visit(dep) }
    out.push(a)
  }
  addons.sort((a, b) => a.name.localeCompare(b.name)).forEach(visit)
  return out
}

export async function walkDirectory(handle: FileSystemDirectoryHandle, base = "", out: RawFile[] = []): Promise<RawFile[]> {
  for await (const [name, entry] of handle.entries()) {
    if (name.startsWith(".") || name === "node_modules") continue
    const path = base ? `${base}/${name}` : name
    if (entry.kind === "directory") await walkDirectory(entry as FileSystemDirectoryHandle, path, out)
    else {
      const file = await (entry as FileSystemFileHandle).getFile()
      if (TEXT_EXT.test(name) || IMG_EXT.test(name)) {
        out.push({ path, read: () => file.arrayBuffer(), lastModified: file.lastModified, size: file.size })
      }
    }
  }
  return out
}

export function filesFromInput(list: FileList): { root: string; files: RawFile[] } {
  const arr = Array.from(list)
  const root = (arr[0] as File & { webkitRelativePath: string }).webkitRelativePath.split("/")[0]
  const files: RawFile[] = []
  for (const f of arr) {
    const rp = (f as File & { webkitRelativePath: string }).webkitRelativePath.split("/").slice(1).join("/")
    if (!rp || rp.split("/").some((s) => s.startsWith("."))) continue
    if (TEXT_EXT.test(rp) || IMG_EXT.test(rp)) files.push({ path: rp, read: () => f.arrayBuffer(), lastModified: f.lastModified, size: f.size })
  }
  return { root, files }
}

export function signature(files: RawFile[]): string {
  return files.map((f) => `${f.path}:${f.lastModified}:${f.size}`).sort().join("|")
}

export function textFile(path: string, content: string): RawFile {
  const bytes = new TextEncoder().encode(content)
  return { path, read: async () => bytes.buffer.slice(0) as ArrayBuffer, lastModified: 0, size: bytes.length }
}
