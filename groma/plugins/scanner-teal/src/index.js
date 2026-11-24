// Local Groma scanner for paw: Lua and Teal sources.
//
// It reports:
// - each Lua or Teal file as a source file, with its module functions and
//   Teal records as symbols;
// - each extension directory (a folder with manifest.lua or init.*) as one
//   source unit, because the extension loader treats the folder as one unit;
// - the operations: one module chunk per file, the module functions, and the
//   functions of the kernel table (`paw.api`) that the Rust sources define;
// - the invocations: `require()` calls, the `requires` of a manifest, and the
//   uses of a module's members through a local alias or through the global
//   `paw` table. Each use carries the binding (the place that supplies the
//   module value) and a member name, so that core can derive a relationship.
// - one execution entry: the binary that embeds the runtime (from settings).
//
// The scanner reads only the files that groma passes to it. It needs no
// dependencies and runs no Lua.
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const SCANNER = { id: 'teal', technology: 'lua/teal', engine: 'paw-local-lexer', engineVersion: '0.1.0' }

const DEFAULTS = {
  global: 'paw',
  globalModule: 'paw',
  kernelModule: 'paw.api',
  luaRoots: ['runtime/lua'],
  extensionRoots: ['extensions'],
  entry: undefined,
}

function settingsOf(settings) {
  const value = { ...DEFAULTS, ...(settings ?? {}) }
  for (const key of ['global', 'globalModule', 'kernelModule']) {
    if (typeof value[key] !== 'string' || value[key] === '') throw new Error(`teal: settings.${key} must be a nonempty string`)
  }
  for (const key of ['luaRoots', 'extensionRoots']) {
    if (!Array.isArray(value[key]) || value[key].some((item) => typeof item !== 'string')) {
      throw new Error(`teal: settings.${key} must be an array of folder paths`)
    }
    value[key] = value[key].map((item) => item.replace(/\/+$/, ''))
  }
  if (value.entry !== undefined) {
    const entry = value.entry
    if (typeof entry !== 'object' || entry === null) throw new Error('teal: settings.entry must be an object')
    for (const key of ['file', 'declaration', 'name']) {
      if (typeof entry[key] !== 'string') throw new Error(`teal: settings.entry.${key} must be a string`)
    }
    if (!Array.isArray(entry.embeds)) throw new Error('teal: settings.entry.embeds must be an array of folder paths')
  }
  return value
}

const isLua = (file) => file.endsWith('.lua') || (file.endsWith('.tl') && !file.endsWith('.d.tl'))
const isRust = (file) => file.endsWith('.rs')
const under = (file, dir) => dir === '' || file.startsWith(`${dir}/`)

// --- Lexer ------------------------------------------------------------------

const KEYWORDS = new Set([
  'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in',
  'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while',
])

function longBracket(src, i) {
  // At `[`: returns the level of `[==[`, or -1.
  let j = i + 1
  while (src[j] === '=') j++
  return src[j] === '[' ? j - i - 1 : -1
}

function lex(src) {
  const tokens = []
  let i = 0
  let line = 1
  const n = src.length
  const advance = (to) => {
    for (let k = i; k < to; k++) if (src.charCodeAt(k) === 10) line++
    i = to
  }
  if (src.startsWith('#!')) advance(src.indexOf('\n') < 0 ? n : src.indexOf('\n'))
  while (i < n) {
    const c = src[i]
    if (c === '\n' || c === ' ' || c === '\t' || c === '\r' || c === '\f' || c === '\v') {
      advance(i + 1)
      continue
    }
    if (c === '-' && src[i + 1] === '-') {
      if (src[i + 2] === '[') {
        const level = longBracket(src, i + 2)
        if (level >= 0) {
          const close = `]${'='.repeat(level)}]`
          const end = src.indexOf(close, i + 4 + level)
          advance(end < 0 ? n : end + close.length)
          continue
        }
      }
      const end = src.indexOf('\n', i)
      advance(end < 0 ? n : end)
      continue
    }
    const start = i
    const startLine = line
    if (c === '"' || c === "'") {
      let j = i + 1
      while (j < n && src[j] !== c && src[j] !== '\n') j += src[j] === '\\' ? 2 : 1
      tokens.push({ type: 'string', value: decodeShort(src.slice(i + 1, j)), pos: start, line: startLine })
      advance(Math.min(j + 1, n))
      continue
    }
    if (c === '[') {
      const level = longBracket(src, i)
      if (level >= 0) {
        const close = `]${'='.repeat(level)}]`
        const end = src.indexOf(close, i + 2 + level)
        const stop = end < 0 ? n : end
        tokens.push({ type: 'string', value: src.slice(i + 2 + level, stop), pos: start, line: startLine })
        advance(end < 0 ? n : end + close.length)
        continue
      }
    }
    if (/[A-Za-z_]/.test(c)) {
      let j = i + 1
      while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++
      const word = src.slice(i, j)
      tokens.push({ type: KEYWORDS.has(word) ? 'keyword' : 'name', value: word, pos: start, line: startLine })
      advance(j)
      continue
    }
    if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(src[i + 1] ?? ''))) {
      let j = i + 1
      while (j < n && /[0-9A-Za-z_.]/.test(src[j])) {
        if ((src[j] === 'e' || src[j] === 'E' || src[j] === 'p' || src[j] === 'P') && (src[j + 1] === '+' || src[j + 1] === '-')) j++
        j++
      }
      tokens.push({ type: 'number', value: src.slice(i, j), pos: start, line: startLine })
      advance(j)
      continue
    }
    const three = src.slice(i, i + 3)
    const two = src.slice(i, i + 2)
    const op = three === '...' ? three : ['..', '::', '==', '~=', '<=', '>=', '//', '<<', '>>'].includes(two) ? two : c
    tokens.push({ type: 'op', value: op, pos: start, line: startLine })
    advance(i + op.length)
  }
  return tokens
}

function decodeShort(text) {
  return text.replace(/\\(.)/g, (_, ch) => ({ n: '\n', t: '\t', r: '\r' })[ch] ?? ch)
}

// --- Expressions ------------------------------------------------------------

const OPEN = new Set(['(', '[', '{'])
const CLOSE = new Set([')', ']', '}'])
const BINARY = new Set(['+', '-', '*', '/', '//', '%', '^', '..', '==', '~=', '<', '<=', '>', '>=', 'and', 'or', '&', '|', '~', '<<', '>>'])

function endsValue(token) {
  return token.type === 'name' || token.type === 'string' || token.type === 'number' ||
    (token.type === 'op' && CLOSE.has(token.value)) ||
    (token.type === 'keyword' && ['end', 'nil', 'true', 'false'].includes(token.value)) ||
    (token.type === 'op' && token.value === '...')
}

function continuesValue(token) {
  if (token.type === 'string') return true
  if (token.type === 'op') return ['.', ':', '(', '[', '{'].includes(token.value) || BINARY.has(token.value)
  if (token.type === 'keyword') return token.value === 'and' || token.value === 'or'
  return false
}

// Reads the expression list after `=` at index i. Returns [exprs, next].
// Each expression is a list of tokens. Stops at the statement end.
function readExprList(tokens, i) {
  const exprs = []
  let current = []
  let depth = 0
  let blocks = 0
  for (; i < tokens.length; i++) {
    const t = tokens[i]
    if (depth === 0 && blocks === 0 && current.length > 0) {
      const prev = current[current.length - 1]
      if (t.type === 'op' && t.value === ',') {
        exprs.push(current)
        current = []
        continue
      }
      if (endsValue(prev) && !continuesValue(t)) break
      if (t.type === 'op' && (t.value === ';' || t.value === '=')) break
    }
    if (t.type === 'op' && OPEN.has(t.value)) depth++
    else if (t.type === 'op' && CLOSE.has(t.value)) {
      if (depth === 0) break
      depth--
    } else if (t.type === 'keyword' && (t.value === 'function' || t.value === 'do' || t.value === 'then' || t.value === 'repeat')) {
      // `function ... end` inside an expression; `do`/`then` cannot start
      // an expression, but count them so a malformed list stops at `end`.
      if (t.value === 'function') blocks++
    } else if (t.type === 'keyword' && t.value === 'end') {
      if (blocks === 0) break
      blocks--
    }
    current.push(t)
  }
  if (current.length) exprs.push(current)
  return [exprs, i]
}

// A simple expression: `require("m")` or `require "m"`, then `.name`s; or
// `name.name.name`. Returns { require, chain } or undefined.
function simpleExpr(expr) {
  let i = 0
  let base
  if (expr[0]?.value === 'require' && expr[0].type === 'name') {
    const arg = requireArg(expr, 0)
    if (!arg) return undefined
    base = { require: arg.module, line: expr[0].line }
    i = arg.next
  } else if (expr[0]?.type === 'name') {
    base = { name: expr[0].value }
    i = 1
  } else return undefined
  const chain = []
  while (i < expr.length) {
    if (expr[i].type === 'op' && expr[i].value === '.' && expr[i + 1]?.type === 'name') {
      chain.push(expr[i + 1].value)
      i += 2
    } else return undefined
  }
  return { ...base, chain }
}

// At `require`: the module name of a literal argument.
function requireArg(tokens, i) {
  const a = tokens[i + 1]
  if (a?.type === 'string') return { module: a.value, next: i + 2 }
  if (a?.type === 'op' && a.value === '(' && tokens[i + 2]?.type === 'string' && tokens[i + 3]?.value === ')') {
    return { module: tokens[i + 2].value, next: i + 4 }
  }
  return undefined
}

// --- Per-file facts ---------------------------------------------------------

function analyzeLua(file, src) {
  const tokens = lex(src)
  const facts = {
    file,
    tokens,
    exportName: undefined, // the table the file returns
    exportsFromTable: new Map(), // `return { a = b }`: key -> local name
    functions: [], // { name, local, pos, line, owner }
    records: [], // Teal records, enums, interfaces
    requires: [], // { module, line, pos, type }
    assigns: [], // `local a, b = x, y` and `x.y = z`: { targets, exprs, line, local }
    manifest: undefined,
    aliasPositions: new Set(), // starts of `local x = a.b` right-hand sides
  }
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i]
    const prev = tokens[i - 1]
    const afterDot = prev && prev.type === 'op' && (prev.value === '.' || prev.value === ':')
    // Functions: `function a.b:c(`, `local function f(`.
    if (t.type === 'keyword' && t.value === 'function' && tokens[i + 1]?.type === 'name') {
      let j = i + 1
      const parts = [tokens[j].value]
      while (tokens[j + 1]?.type === 'op' && (tokens[j + 1].value === '.' || tokens[j + 1].value === ':') && tokens[j + 2]?.type === 'name') {
        parts.push(tokens[j + 2].value)
        j += 2
      }
      const isLocal = prev?.type === 'keyword' && prev.value === 'local'
      const start = isLocal ? prev : t
      facts.functions.push({
        owner: parts.length > 1 ? parts[0] : undefined,
        name: parts.length > 1 ? parts.slice(1).join('.') : parts[0],
        local: isLocal,
        pos: start.pos,
        line: tokens[i + 1].line,
      })
      continue
    }
    // Teal records, enums and interfaces at any depth: `local record X`,
    // `global record X`, `record X` in a record body.
    if (t.type === 'name' && ['record', 'enum', 'interface'].includes(t.value) && tokens[i + 1]?.type === 'name' && !afterDot &&
      (prev === undefined || prev.type === 'keyword' || (prev.type === 'name' && ['global', 'local', 'type'].includes(prev.value)) || prev.value === '=' ||
        tokens[i + 2]?.type === 'name' || (tokens[i + 2]?.type === 'op' && ['<', 'is'].includes(tokens[i + 2].value)))) {
      facts.records.push({ name: tokens[i + 1].value, kind: t.value, pos: t.pos, line: t.line })
      continue
    }
    // require calls; `local type X = require(...)` is a Teal type import.
    if (t.type === 'name' && t.value === 'require' && !afterDot) {
      const arg = requireArg(tokens, i)
      if (arg) {
        const typeOnly = tokens[i - 1]?.value === '=' && tokens[i - 3]?.value === 'type' && tokens[i - 4]?.value === 'local'
        if (!typeOnly) facts.requires.push({ module: arg.module, line: t.line, pos: t.pos })
      }
      continue
    }
    // `pcall(require, "m")`
    if (t.type === 'name' && t.value === 'pcall' && tokens[i + 1]?.value === '(' && tokens[i + 2]?.value === 'require' &&
      tokens[i + 3]?.value === ',' && tokens[i + 4]?.type === 'string') {
      facts.requires.push({ module: tokens[i + 4].value, line: t.line, pos: tokens[i + 2].pos })
      i += 4
      continue
    }
    // `local a, b <const> = ...` (not `local function`, not `local type`)
    if (t.type === 'keyword' && t.value === 'local' && tokens[i + 1]?.type === 'name' && tokens[i + 1].value !== 'type' &&
      !['record', 'enum', 'interface'].includes(tokens[i + 1].value)) {
      const targets = []
      let j = i + 1
      while (tokens[j]?.type === 'name') {
        targets.push(tokens[j].value)
        j++
        if (tokens[j]?.value === '<') j += 3 // <const>, <close>
        if (tokens[j]?.value === ':') { // Teal type annotation: skip to `=`, `,` at depth 0
          let depth = 0
          j++
          while (j < tokens.length) {
            const v = tokens[j].value
            if (OPEN.has(v) || v === '<') depth++
            else if (CLOSE.has(v) || v === '>') depth--
            else if (depth === 0 && (v === '=' || v === ',')) break
            else if (depth === 0 && tokens[j].type === 'keyword' && v !== 'function' && v !== 'nil') break
            j++
          }
        }
        if (tokens[j]?.value === ',') j++
        else break
      }
      if (tokens[j]?.value === '=') {
        const [exprs] = readExprList(tokens, j + 1)
        facts.assigns.push({ targets: targets.map((name) => [name]), exprs, line: t.line, local: true })
        // `local api = paw.api`: the alias is not a use; its uses are.
        for (const expr of exprs) if (simpleExpr(expr) && expr[0].value !== 'require') facts.aliasPositions.add(expr[0].pos)
      }
      continue
    }
    // `a.b, c.d = ...` at the start of a statement
    if (t.type === 'name' && !afterDot && (prev === undefined || !continuesAfter(prev))) {
      const targets = []
      let j = i
      while (tokens[j]?.type === 'name') {
        const chain = [tokens[j].value]
        j++
        while (tokens[j]?.value === '.' && tokens[j + 1]?.type === 'name') {
          chain.push(tokens[j + 1].value)
          j += 2
        }
        targets.push(chain)
        if (tokens[j]?.value === ',' && tokens[j + 1]?.type === 'name') j++
        else break
      }
      if (tokens[j]?.value === '=' && targets.length > 0) {
        const [exprs] = readExprList(tokens, j + 1)
        facts.assigns.push({ targets, exprs, line: t.line, local: false })
      }
    }
  }
  // The returned table: the last `return` at the start of a line, which is
  // the top-level one in the code style of paw; else the last `return`.
  const returns = tokens.map((t, i) => [t, i]).filter(([t]) => t.type === 'keyword' && t.value === 'return')
  const topLevel = returns.filter(([t]) => t.pos === 0 || src[t.pos - 1] === '\n')
  for (const [t, i] of (topLevel.length ? topLevel : returns).slice(-1)) {
    const next = tokens[i + 1]
    if (next?.type === 'name' && (i + 2 === tokens.length || tokens[i + 2].value === ';')) facts.exportName = next.value
    else if (next?.value === 'setmetatable' && tokens[i + 2]?.value === '(' && tokens[i + 3]?.type === 'name') facts.exportName = tokens[i + 3].value
    else if (next?.value === '{') readReturnTable(tokens, i + 1, facts)
    break
  }
  if (path.posix.basename(file) === 'manifest.lua') facts.manifest = readManifest(tokens)
  return facts
}

function continuesAfter(token) {
  // A token after which a name continues an expression or a declaration.
  if (token.type === 'op') return !['(', ')', ']', '}', ';'].includes(token.value) || token.value === '('
  if (token.type === 'keyword') return ['and', 'or', 'not', 'return', 'local', 'function', 'in', 'until', 'if', 'elseif', 'while', 'for'].includes(token.value)
  return token.type === 'name' && ['global', 'type'].includes(token.value)
}

function readReturnTable(tokens, i, facts) {
  let depth = 0
  for (let j = i; j < tokens.length; j++) {
    const v = tokens[j].value
    if (tokens[j].type === 'op' && OPEN.has(v)) depth++
    else if (tokens[j].type === 'op' && CLOSE.has(v)) {
      depth--
      if (depth === 0) return
    } else if (depth === 1 && tokens[j].type === 'name' && tokens[j + 1]?.value === '=' && tokens[j + 2]?.type === 'name' &&
      [',', '}', ';'].includes(tokens[j + 3]?.value) && [',', '{', ';'].includes(tokens[j - 1]?.value)) {
      facts.exportsFromTable.set(v, tokens[j + 2].value)
    } else if (depth === 1 && tokens[j].type === 'name' && tokens[j + 1]?.value === '=' && tokens[j + 2]?.value === 'function' &&
      [',', '{', ';'].includes(tokens[j - 1]?.value)) {
      facts.functions.push({ owner: '{return}', name: v, local: false, pos: tokens[j].pos, line: tokens[j].line })
    }
  }
}

function readManifest(tokens) {
  const manifest = { requires: [] }
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i]
    if (t.type === 'name' && t.value === 'name' && tokens[i + 1]?.value === '=' && tokens[i + 2]?.type === 'string') manifest.name = tokens[i + 2].value
    if (t.type === 'name' && t.value === 'requires' && tokens[i + 1]?.value === '=' && tokens[i + 2]?.value === '{') {
      for (let j = i + 3; j < tokens.length && tokens[j].value !== '}'; j++) {
        const key = tokens[j].type === 'name' ? tokens[j].value : tokens[j].value === '[' && tokens[j + 1]?.type === 'string' ? tokens[j + 1].value : undefined
        const eq = tokens[j].type === 'name' ? j + 1 : j + 3
        if (key && tokens[eq]?.value === '=' && tokens[eq + 1]?.type === 'string') {
          manifest.requires.push({ name: key, version: tokens[eq + 1].value, line: tokens[j].line, pos: tokens[j].pos })
          j = eq + 1
        }
      }
    }
  }
  return manifest
}

// The functions that a Rust file defines on the kernel table: `fn name(` in a
// `define!` block, and `api.set("name", ...)`.
function analyzeRust(file, src) {
  const text = src.replace(/\/\/[^\n]*/g, (m) => ' '.repeat(m.length))
  const lineAt = (pos) => text.slice(0, pos).split('\n').length
  const found = []
  for (const block of text.matchAll(/\bdefine!\s*\{/g)) {
    let depth = 0
    let end = block.index
    for (let k = block.index + block[0].length - 1; k < text.length; k++) {
      if (text[k] === '{') depth++
      else if (text[k] === '}' && --depth === 0) {
        end = k
        break
      }
    }
    const body = text.slice(block.index, end)
    for (const fn of body.matchAll(/(?:^|[\s;}])fn\s+([A-Za-z_]\w*)\s*\(/g)) {
      const pos = block.index + fn.index + fn[0].indexOf('fn')
      found.push({ name: fn[1], pos, line: lineAt(pos) })
    }
  }
  // `api.set("name", ...)`, and helpers called as `helper(lua, api, shared, "name", ...)`.
  for (const set of text.matchAll(/\bapi\s*(?:\.\s*set\s*\(|,\s*\w+\s*,)\s*"([A-Za-z_]\w*)"/g)) {
    found.push({ name: set[1], pos: set.index, line: lineAt(set.index) })
  }
  const install = /\bpub(?:\([^)]*\))?\s+fn\s+install\s*\(/.exec(text)
  return { file, functions: found, install: install ? { pos: install.index, line: lineAt(install.index) } : undefined }
}

// --- Module map -------------------------------------------------------------

function moduleOf(file, config, extensions) {
  for (const root of config.luaRoots) {
    if (under(file, root)) return modulePath(file.slice(root.length + 1))
  }
  const ext = extensions.find((item) => under(file, item.dir))
  if (ext) {
    const rest = file.slice(ext.dir.length + 1)
    if (rest.startsWith('lua/')) return modulePath(rest.slice(4))
    if (/^init\.(lua|tl)$/.test(rest)) return `${ext.name} (init)`
    if (rest === 'manifest.lua') return `${ext.name} (manifest)`
    return `${ext.name}/${rest.replace(/\.(lua|tl)$/, '')}`
  }
  return file.replace(/\.(lua|tl)$/, '')
}

function modulePath(rest) {
  const name = rest.replace(/\.(lua|tl)$/, '').split('/').join('.')
  return name.endsWith('.init') ? name.slice(0, -5) : name === 'init' ? '' : name
}

function findExtensions(files, config) {
  const byDir = new Map()
  for (const file of files) {
    for (const root of config.extensionRoots) {
      if (!under(file, root)) continue
      const rest = file.slice(root.length + 1).split('/')
      if (rest.length < 2) continue
      const dir = `${root}/${rest[0]}`
      const entry = byDir.get(dir) ?? { dir, name: rest[0], files: [] }
      entry.files.push(file)
      byDir.set(dir, entry)
    }
  }
  return [...byDir.values()]
    .filter((ext) => ext.files.some((file) => /\/(manifest\.lua|init\.(lua|tl))$/.test(file) && path.posix.dirname(file) === ext.dir))
    .sort((a, b) => a.dir.localeCompare(b.dir))
}

// --- Scan -------------------------------------------------------------------

async function readSources(root, files) {
  return Promise.all(files.map(async (file) => ({ file, src: await readFile(path.join(root, file), 'utf8') })))
}

function opId(file, kind, name) {
  return `${file}#${kind}:${name}`
}

async function scanTeal(root, settings, selected) {
  const config = settingsOf(settings)
  const luaFiles = [...new Set(selected.filter(isLua))].sort()
  if (!luaFiles.length) return undefined
  const rustFiles = [...new Set(selected.filter(isRust))].sort()
  const extensions = findExtensions(luaFiles, config)
  const lua = (await readSources(root, luaFiles)).map(({ file, src }) => analyzeLua(file, src))
  const rust = (await readSources(root, rustFiles)).map(({ file, src }) => analyzeRust(file, src))

  const operations = []
  const invocations = []
  const diagnostics = []
  const files = []
  const kernel = new Map() // api function name -> operation id
  let kernelInstall

  // Kernel table functions, from Rust.
  const kernelFiles = []
  for (const source of rust) {
    if (!source.functions.length) continue
    kernelFiles.push(source.file)
    for (const fn of source.functions) {
      const id = opId(source.file, 'api', fn.name)
      if (kernel.has(fn.name)) continue
      kernel.set(fn.name, id)
      operations.push({ id, file: source.file, name: `${config.kernelModule}.${fn.name}`, position: fn.pos })
    }
    if (source.install && source.file.endsWith('/mod.rs') && !kernelInstall) {
      kernelInstall = opId(source.file, 'install', 'install')
      operations.push({ id: kernelInstall, file: source.file, name: config.kernelModule, position: source.install.pos })
    }
  }
  kernelInstall ??= [...kernel.values()][0]

  // Modules: name -> facts. Extension modules are on that extension's path.
  const byFile = new Map(lua.map((facts) => [facts.file, facts]))
  const runtimeModules = new Map()
  const extModules = new Map() // ext dir -> Map(name -> facts)
  for (const facts of lua) {
    facts.module = moduleOf(facts.file, config, extensions)
    facts.ext = extensions.find((ext) => under(facts.file, ext.dir))
    facts.chunk = opId(facts.file, 'chunk', facts.module)
    operations.push({ id: facts.chunk, file: facts.file, name: facts.module || config.globalModule, position: 0 })
    const onPath = facts.ext ? facts.file.startsWith(`${facts.ext.dir}/lua/`) : config.luaRoots.some((r) => under(facts.file, r))
    if (!onPath) continue
    const table = facts.ext ? extModules.get(facts.ext.dir) ?? new Map() : runtimeModules
    if (facts.ext) extModules.set(facts.ext.dir, table)
    if (!table.has(facts.module)) table.set(facts.module, facts)
  }
  const globalFacts = runtimeModules.get('') ?? runtimeModules.get(config.globalModule)

  // Exports: member name -> operation id.
  for (const facts of lua) {
    facts.exports = new Map()
    const locals = new Map()
    for (const fn of facts.functions) {
      const id = opId(facts.file, 'fn', `${fn.owner ?? ''}.${fn.name}@${fn.pos}`)
      operations.push({ id, file: facts.file, name: `${facts.module}${fn.owner && fn.owner !== '{return}' ? '.' : ':'}${fn.name}`.replace(/^:/, ''), position: fn.pos })
      fn.id = id
      if (fn.owner === undefined) locals.set(fn.name, fn)
      if ((fn.owner === facts.exportName || fn.owner === '{return}') && !facts.exports.has(fn.name)) facts.exports.set(fn.name, id)
    }
    for (const [key, local] of facts.exportsFromTable) {
      const fn = locals.get(local)
      if (fn && !facts.exports.has(key)) facts.exports.set(key, fn.id)
    }
    for (const assign of facts.assigns) {
      assign.targets.forEach((target, index) => {
        if (target.length === 2 && target[0] === facts.exportName && assign.exprs[index]?.length === 1) {
          const fn = locals.get(assign.exprs[index][0].value)
          if (fn && !facts.exports.has(target[1])) facts.exports.set(target[1], fn.id)
        }
      })
    }
  }

  const resolveModule = (name, from) => {
    if (name === config.kernelModule) return { kernel: true }
    if (from?.ext) {
      const own = extModules.get(from.ext.dir)?.get(name)
      if (own) return { facts: own }
    }
    const runtime = runtimeModules.get(name)
    if (runtime) return { facts: runtime }
    if (name === config.globalModule && globalFacts) return { facts: globalFacts }
    for (const table of extModules.values()) {
      const other = table.get(name)
      if (other) return { facts: other }
    }
    return undefined
  }

  // Values: what a name or `paw.x` stands for. A value is
  // { module: target, members: [...], binding: { file, line } }.
  const valueOfExpr = (expr, scope, from, line, complex) => {
    const simple = simpleExpr(expr)
    if (simple) {
      if (simple.require !== undefined) {
        const target = resolveModule(simple.require, from)
        return target && { target, moduleName: simple.require, members: simple.chain, binding: { file: from.file, line: simple.line } }
      }
      const base = scope(simple.name, line)
      return base && { ...base, members: [...base.members, ...simple.chain] }
    }
    // A complex expression: the single module it names, if only one.
    if (!complex) return undefined
    const seen = new Map()
    for (let i = 0; i < expr.length; i++) {
      const t = expr[i]
      if (t.type !== 'name' || expr[i - 1]?.value === '.' || expr[i - 1]?.value === ':') continue
      const base = scope(t.value, line)
      if (!base) continue
      const chain = []
      for (let j = i + 1; expr[j]?.value === '.' && expr[j + 1]?.type === 'name'; j += 2) chain.push(expr[j + 1].value)
      const value = normalize({ ...base, members: [...base.members, ...chain] })
      if (value.global && value.members.length > 0) continue
      seen.set(value.moduleName, { ...value, members: [] })
    }
    if (seen.size === 1) {
      const base = [...seen.values()][0]
      return { ...base, members: [] }
    }
    return undefined
  }

  // The global table: `paw.x = ...` in the runtime.
  const globalMembers = new Map() // member -> value
  const globalBinding = { file: globalFacts?.file, line: 1 }
  const kernelBinding = { ...globalBinding }
  if (globalFacts) {
    const req = globalFacts.requires.find((r) => r.module === config.kernelModule)
    if (req) kernelBinding.line = req.line
  }
  const fileScope = (facts) => {
    const aliases = []
    return {
      aliases,
      lookup: (name, line) => {
        let best
        for (const alias of aliases) if (alias.name === name && alias.line <= line && (!best || alias.line >= best.line)) best = alias
        if (best) return best.value
        if (name === config.global) {
          return globalFacts && { target: { facts: globalFacts }, moduleName: config.globalModule, members: [], binding: globalBinding, global: true }
        }
        return undefined
      },
    }
  }
  const scopes = new Map(lua.map((facts) => [facts.file, fileScope(facts)]))
  // Normalizes a value whose base is the global table: `paw.api.x`,
  // `paw.commands.run`, through the members the runtime assigned.
  const normalize = (value) => {
    let current = value
    for (let guard = 0; current?.global && current.members.length > 0 && guard < 8; guard++) {
      const [first, ...rest] = current.members
      if (first === 'api' && config.kernelModule === `${config.global}.api`) {
        current = { target: { kernel: true }, moduleName: config.kernelModule, members: rest, binding: kernelBinding }
        break
      }
      const assigned = globalMembers.get(first)
      if (!assigned) break
      current = { ...assigned, members: [...assigned.members, ...rest] }
    }
    return current
  }

  // Two passes over the assignments: first the global table's members in the
  // runtime, then every file's local aliases.
  for (let pass = 0; pass < 2; pass++) {
    for (const facts of lua) {
      const scope = scopes.get(facts.file)
      scope.aliases.length = 0
      const lookup = (name, line) => {
        const value = scope.lookup(name, line)
        return value && normalize(value)
      }
      for (const assign of facts.assigns) {
        assign.targets.forEach((target, index) => {
          const expr = assign.exprs[index]
          if (!expr) return
          const isGlobal = !assign.local && target.length === 2 && target[0] === config.global
          const value = valueOfExpr(expr, lookup, facts, assign.line, isGlobal)
          if (!value) return
          if (assign.local && target.length === 1 && target[0] !== facts.exportName) scope.aliases.push({ name: target[0], line: assign.line, value })
          else if (!assign.local && target.length === 2 && target[0] === config.global && !facts.ext && !globalMembers.has(target[1])) {
            globalMembers.set(target[1], { ...value, binding: { file: facts.file, line: assign.line } })
          }
        })
      }
    }
  }

  const memberTarget = (value) => {
    if (value.target.kernel) {
      const name = value.members[0]
      return { op: (name && kernel.get(name)) ?? kernelInstall, name: [config.kernelModule, ...value.members.slice(0, 1)].join('.') }
    }
    const facts = value.target.facts
    for (let k = value.members.length; k > 0; k--) {
      const key = value.members.slice(0, k).join('.')
      const op = facts.exports.get(key)
      if (op) return { op, name: `${value.moduleName}.${key}` }
    }
    return { op: facts.chunk, name: [value.moduleName, ...value.members.slice(0, 1)].join('.') }
  }

  const add = (facts, line, target, member, binding) => {
    if (!target.op) return
    const targetFile = target.op.split('#')[0]
    if (targetFile === facts.file) return
    invocations.push({ source: facts.chunk, targets: [target.op], unresolved: false, line, member, binding })
  }

  for (const facts of lua) {
    const scope = scopes.get(facts.file)
    // require() calls
    for (const req of facts.requires) {
      const target = resolveModule(req.module, facts)
      if (!target) continue
      const op = target.kernel ? kernelInstall : target.facts.chunk
      add(facts, req.line, { op }, `require("${req.module}")`, { file: facts.file, line: req.line })
    }
    // manifest requires
    if (facts.manifest) {
      for (const need of facts.manifest.requires) {
        const ext = extensions.find((item) => item.name === need.name)
        const init = ext && lua.find((other) => other.ext === ext && /\/init\.(lua|tl)$/.test(other.file) && path.posix.dirname(other.file) === ext.dir)
        const target = need.name === config.global ? globalFacts : init
        if (target) add(facts, need.line, { op: target.chunk }, `requires ${need.name} ${need.version}`, { file: facts.file, line: need.line })
      }
    }
    // member uses: `alias.x`, `paw.x.y`, `alias:x(`
    const tokens = facts.tokens
    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i]
      if (t.type !== 'name') continue
      const prev = tokens[i - 1]
      if (prev?.type === 'op' && (prev.value === '.' || prev.value === ':')) continue
      if (prev?.type === 'keyword' && prev.value === 'function') continue
      if (tokens[i + 1]?.type !== 'op' || (tokens[i + 1].value !== '.' && tokens[i + 1].value !== ':')) continue
      if (facts.aliasPositions.has(t.pos)) continue
      const base = scope.lookup(t.value, t.line)
      if (!base) continue
      const members = []
      let j = i
      while (tokens[j + 1]?.type === 'op' && (tokens[j + 1].value === '.' || tokens[j + 1].value === ':') && tokens[j + 2]?.type === 'name') {
        members.push(tokens[j + 2].value)
        j += 2
        if (tokens[j - 1].value === ':') break
      }
      if (!members.length) continue
      // An assignment target (`paw.x = ...`) is not a use.
      if (tokens[j + 1]?.type === 'op' && tokens[j + 1].value === '=') continue
      const value = normalize({ ...base, members: [...base.members, ...members] })
      if (!value || (value.global && value.target.facts === facts)) continue
      if (!value.target.kernel && value.target.facts === facts) continue
      if (!value.target.kernel && value.target.facts.records.some((record) => record.name === value.members[0])) continue
      const target = memberTarget(value)
      add(facts, t.line, target, target.name, value.binding)
      i = j
    }
  }

  // Files, symbols and roots.
  const roots = [{ id: 'lua-path', kind: 'lua-path', name: config.luaRoots.join(', ') }]
  for (const ext of extensions) {
    const manifest = ext.files.find((file) => file === `${ext.dir}/manifest.lua`)
    roots.push({ id: `extension:${ext.name}`, kind: 'extension', name: ext.name, ...(manifest ? { file: manifest } : {}) })
  }
  roots.push({ id: 'other-lua', kind: 'source-group', name: 'other Lua' })
  if (kernelFiles.length) roots.push({ id: 'kernel-table', kind: 'kernel-table', name: config.kernelModule })
  for (const facts of lua) {
    const rootId = facts.ext ? `extension:${facts.ext.name}` : config.luaRoots.some((r) => under(facts.file, r)) ? 'lua-path' : 'other-lua'
    const symbols = []
    if (facts.manifest?.name) symbols.push({ id: `${facts.file}#extension`, name: facts.manifest.name, kind: 'extension' })
    for (const fn of facts.functions) {
      if (facts.exportName && fn.owner === facts.exportName) symbols.push({ id: fn.id, name: fn.name, kind: 'function' })
      else if (fn.owner === undefined && [...facts.exports.values()].includes(fn.id)) symbols.push({ id: fn.id, name: fn.name, kind: 'function' })
    }
    for (const record of facts.records) symbols.push({ id: `${facts.file}#type:${record.name}@${record.pos}`, name: record.name, kind: record.kind })
    files.push({ file: facts.file, roots: [rootId], symbols })
  }
  for (const file of kernelFiles) files.push({ file, roots: ['kernel-table'], symbols: [] })

  // Extensions are one unit each: the loader runs the folder as one.
  const sourceUnits = []
  for (const ext of extensions) {
    const members = lua.filter((facts) => facts.ext === ext).map((facts) => facts.file)
    const primary = members.find((file) => /\/init\.(lua|tl)$/.test(file) && path.posix.dirname(file) === ext.dir) ??
      members.find((file) => file === `${ext.dir}/manifest.lua`)
    if (primary && members.length > 1) sourceUnits.push({ primary, files: members })
  }

  // The binary that embeds the runtime.
  const entryPoints = []
  const known = new Set(files.map((item) => item.file))
  if (config.entry) {
    const embedded = lua.filter((facts) => config.entry.embeds.some((dir) => under(facts.file, dir.replace(/\/+$/, '')))).map((facts) => facts.file)
    if (embedded.length) {
      if (!known.has(config.entry.file)) {
        files.push({ file: config.entry.file, roots: ['lua-path'], symbols: [] })
        known.add(config.entry.file)
      }
      if (!known.has(config.entry.declaration)) {
        files.push({ file: config.entry.declaration, roots: ['lua-path'], symbols: [] })
        known.add(config.entry.declaration)
      }
      entryPoints.push({ file: config.entry.file, declaration: config.entry.declaration, name: config.entry.name, files: [config.entry.file, ...embedded] })
    }
  }

  diagnostics.push({
    severity: 'info',
    code: 'TEAL_SCOPE',
    message: 'Lua and Teal source read by a lexer, not a compiler. require() calls with a literal name, manifest requires, and member uses through a local alias or the global table are reported as supplied-module invocations. Dynamic requires, metatables and values passed between functions stay unresolved and are not reported.',
  })

  return {
    schemaVersion: 1,
    scanner: SCANNER,
    roots,
    files,
    sourceUnits,
    entryPoints,
    operations,
    invocations,
    diagnostics,
  }
}

async function readCodeStructure(root, references) {
  const result = []
  for (const reference of references) {
    if (!isLua(reference.file)) continue
    let src
    try {
      src = await readFile(path.join(root, reference.file), 'utf8')
    } catch {
      continue
    }
    const facts = analyzeLua(reference.file, src)
    const exported = new Set(facts.exportsFromTable.values())
    const declarations = []
    for (const fn of facts.functions) {
      const top = fn.owner === undefined || fn.owner === facts.exportName || fn.owner === '{return}'
      if (!top) continue
      const isPublic = fn.owner !== undefined || exported.has(fn.name)
      declarations.push({ kind: 'function', name: fn.name, line: fn.line, visibility: isPublic ? 'public' : 'private', entry: reference.symbols.includes(fn.name) })
    }
    for (const record of facts.records) {
      declarations.push({ kind: 'type', name: record.name, line: record.line, visibility: 'public', entry: reference.symbols.includes(record.name), members: [] })
    }
    declarations.sort((a, b) => a.line - b.line)
    if (declarations.length) result.push({ file: reference.file, declarations })
  }
  return result
}

const scanner = {
  id: 'teal',
  listSourceFiles: async (_root, _settings, candidates) => [...new Set(candidates.filter((file) => isLua(file) || isRust(file)))].sort(),
  checkReadiness: async (_root, settings, files) => {
    settingsOf(settings)
    if (!files.some(isLua)) throw new Error('teal: No selected Lua or Teal source files were found.')
  },
  readCodeStructure,
  scan: scanTeal,
}

export default scanner
export { analyzeLua, analyzeRust, lex }
