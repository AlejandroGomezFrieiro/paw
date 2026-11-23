-- Text buffers: a listing of the project edited as text, after oil.nvim.
-- docs/reference/lists-edited-as-text.md says how they are used, docs/reference/lua-views.md how an
-- extension adds a kind of its own.
--
--   :e paw://parts          :vs paw://sends          :e paw://markers
--
-- A buffer is lines of text, one thing of the project on each (a part, a
-- send, a device, a marker), written by its kind. Each line carries the id
-- of what it stands for, out of the text, so that a line changed is that
-- thing changed, a line moved is it moved, a line deleted is it deleted, a
-- line copied (`yyp`) is a copy of it, and a line typed new is a new one.
-- Nothing reaches the project while the text is edited; `:w` compares the
-- lines with what the buffer was read from, shows the plan, and applies it
-- as one undo step.
--
-- Editing is Vim's: the keymap's grammar works on the lines (counts,
-- registers, `.`, visual and visual-block selections, macros) through the
-- view's `grid`, whose rows are lines and whose columns are characters. A
-- column is passed to the grammar as `row * BIG + column`, so that the two
-- ends of a selection across lines stay in order when the grammar takes
-- the smaller and the larger. The buffer keeps its own undo of the text.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local events = require("paw.events")
local commands = require("paw.commands")
local registry = require("paw.registry")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type SeatsModule = require("paw.seats")
local type CanvasModule = require("paw.canvas")
local type UiModule = require("paw.ui")
local type MouseModule = require("paw.mouse")
local type LayoutModule = require("paw.layout")

local type Data = util.Data
local type Buf = contracts.Buf
local type Window = contracts.Window
local type LayoutBuffer = contracts.LayoutBuffer
local type KeyContext = contracts.KeyContext
local type Region = contracts.Region
local type Id = integer | string

--- What a line reads as: its fields by name.
local type Fields = {string: Data}

local type Context = contracts.TextContext

-- The text -----------------------------------------------------------------------
--
-- Lines are `{ text, id }`; `id` is nil on a line typed new. Positions are a
-- row (from 1) and a column (from 0, in characters).

--- A line: its text, and the id of what it stands for.
local record Line
  text: string
  id: Id
  order: integer
end

--- A step of the text's undo: the lines, and where the cursor was.
local record Step
  lines: {Line}
  row: integer
  col: integer
end

--- A text of lines that keeps its own undo (a buffer's `state.text`):
--- the lines, those it was read from (`base`), and `readonly`, what to
--- say when a change is tried.
local record Text
  lines: {Line}
  base: {Line}
  undos: {Step}
  redos: {Step}
  open: boolean
  tick: integer
  readonly: string
end
local Text_mt: metatable<Text> = {__index = Text}

--- What a buffer keeps (`buf.state`): its kind and what the kind's
--- pattern took from the name, the text, the fields each id was read as
--- and the place of each id, the fields each text reads as (kept), the
--- error of the last read, whether the project changed under changes,
--- the edits of the project it was read at, and whether it is modified.
local record State
  kind: contracts.TextKind<contracts.TextItem, Fields>
  args: {string}
  text: Text
  fields: {Id: Fields}
  order: {Id: integer}
  parsed: {string: {Fields | string}}
  error: string
  conflict: boolean
  seen: integer
  modified: boolean
end

--- The cursor of a window (`win.state`): row, column, the first row
--- shown, the column a vertical move wants, and the rows shown.
local record Cursor
  row: integer
  col: integer
  top: integer
  want: number
  height: integer
end

--- A buffer of the layout with its state as this module keeps it.
local record TextBuffer
  id: integer
  name: string
  type: string
  target: string
  state: State
end

--- What a register holds that this module puts: lines (with the buffer
--- they were yanked from), a block of rows, or text. Others put parts.
local record Register is KeymapModule.Register
  lines: {Line}
  source: string
  rows: {string}
  text: string
end

--- A span of the text: "line" (rows `r0` to `r1`), "char" (from (r0, c0)
--- up to (r1, c1), the end left out) or "block" (rows and columns `c0` to
--- `c1`, the end left out).
local record Span
  kind: string
  r0: integer
  r1: integer
  c0: integer
  c1: integer
end

--- A block insert: what is typed on the first line goes on the others.
local record Block
  r0: integer
  r1: integer
  col: integer
  before: string
  append: boolean
end

--- Insert mode under way: the window, the buffer, and a block insert.
local record Insert
  win: integer
  buf: integer
  block: Block
end

--- The cells of a line (`M.cells`).
local record Cell
  text: string
  col: integer
end

--- What `paw.keymap.set` takes besides the key and what it does.
local type MapOptions = KeymapModule.MapOptions

--- What a key of a kind gets, wrapped by `paw.layout.powers`.
local type Wrapped = function(ctx: KeyContext, region?: Region): Region

--- What `paw.layout.split` and `paw.layout.leaf` take.
local record SplitOptions
  view: string
  buf: integer
  vertical: boolean
end

--- paw/layout.tl, as far as this module calls it, with its windows as `contracts.Window`.
local record Layout
  buffers: {integer: LayoutBuffer}
  current: function(): Window
  get: function(id: integer): Window
  buf_of: function(win: Window): LayoutBuffer
  buf_create: function(type_name: string, target: string): LayoutBuffer
  buftype: function<B is contracts.Buftype>(name: string, def: B): B
  powers: function(scope: string, def: contracts.Powers, wrap: function(Wrapped): Wrapped)
  show_in: function(win: Window, name: string, buf: integer): Window
  leaf: function(view: string, fields: SplitOptions): Window
  windows: function(): {Window}
  enter: function(win: Window)
  split: function(opts: SplitOptions): Window
end

local type KeyList = {{string}}

--- paw/frontend.tl's actions, as far as this module adds one: the frontend
--- names the types of paw.statusline, which names this module's, so this
--- module cannot name the frontend's.
local record Frontend
  act: {string: function(name: string, window: boolean): Window, string}
end

local record PawState
  last_cmdline: string
end

local record Paw is partial.Paw
  keymap: KeymapModule
  seats: SeatsModule
  canvas: CanvasModule
  mouse: MouseModule
  ui: UiModule
  layout: LayoutModule
  frontend: Frontend
  state: PawState
  undo: function(): boolean
end
local paw = (_G as {string: Paw}).paw
local layout = paw.layout as Layout
local keymap = paw.keymap
local function ui(): UiModule
  return paw.ui
end

--- The edits of the project: one field of the project, quicker than the whole.
local project_edits = api.project_get as function(string): integer

--- What `paw.textbuf.open` takes.
local record OpenOptions
  here: boolean
  vertical: boolean
  window: boolean
end

--- What `paw.textbuf.insert` takes besides how.
local record InsertOptions
  block: Block
end

local type Operator = KeymapModule.Operator

--- The operators of the text.
local record Ops
  delete: Operator
  yank: Operator
  change: Operator
  lower: Operator
  upper: Operator
  swapcase: Operator
  increment: function(by: integer): Operator
end

local record M
  type TextBuffer = TextBuffer
  type Cursor = Cursor
  type Fields = Fields
  type Line = Line
  type Text = Text
  type State = State
  type Register = Register
  type OpenOptions = OpenOptions
  --- The kinds by name, with the extension that made each one.
  --- `paw.textbuf.kind` puts one.
  kinds: registry.Registry<contracts.TextKind<contracts.TextItem, Fields>>
  --- The columns of a row in a column of the grid (`row * BIG + column`).
  BIG: integer
  --- The operators of the text (`d`, `y`, `c`, `gu`, `gU`, `g~`, and
  --- `increment(by)`, which makes the operator of `Ctrl-a` and `Ctrl-x`).
  ops: Ops
  width: function(s: string): integer
  copy_lines: function(lines: {Line}): {Line}
  kind_of: function(target: string): contracts.TextKind<contracts.TextItem, Fields>, {string}
  same: function(a: Data, b: Data): boolean
  here: function(): Window, TextBuffer, Text, Cursor
  replace: function(ctx?: KeyContext)
  join: function(ctx?: KeyContext)
  tilde: function(ctx?: KeyContext)
  write: function(buf: TextBuffer, force: boolean)
  buf: function(): TextBuffer
end
M.kinds = registry.new("textbuf_kinds", "text buffer kinds")
local BIG = 1000000
M.BIG = BIG

-- Characters -------------------------------------------------------------------

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local function chars(s: string): {string}
  local out: {string} = {}
  for ch in s:gmatch(CHAR) do
    out[#out + 1] = ch
  end
  return out
end

--- How many characters a string has (UTF-8).
local function width(s: string): integer
  local n = 0
  for _ in s:gmatch(CHAR) do
    n = n + 1
  end
  return n
end
M.width = width

--- Text cut to `w` columns, not padded.
local function clip(text: string, w: integer): string
  if w <= 0 then
    return ""
  end
  if api.str_width(text) <= w then
    return text
  end
  return util.fit(text, w)
end

--- The text before column `col` (counted in characters from 0) and after.
local function split(s: string, col: integer): string, string
  if col <= 0 then
    return "", s
  end
  local n, at = 0, #s + 1
  for pos in s:gmatch("()" .. CHAR) do
    if n == col then
      at = pos as integer
      break
    end
    n = n + 1
  end
  return s:sub(1, at - 1), s:sub(at)
end

local function char_at(s: string, col: integer): string
  local _, after = split(s, col)
  return after:match("^" .. CHAR)
end

--- What kind of character: 0 a space, 1 part of a word, 2 punctuation.
local function class(ch: string, big?: boolean): integer
  if ch == nil or ch == "\n" or ch:match("^%s$") then
    return 0
  end
  if big then
    return 1
  end
  if ch:match("^[%w_]$") or #ch > 1 then
    return 1
  end
  return 2
end

--- An error as a person reads it: its first line, without where in the
--- code it was raised.
local function reason(err: string): string
  return (tostring(err):match("^[^\n]*"):gsub("^.-:%d+: ", ""):gsub("^runtime error: ", ""))
end

--- A copy of lines (`{ text, id }`).
local function copy_lines(lines: {Line}): {Line}
  local out: {Line} = {}
  for i, l in ipairs(lines) do
    out[i] = {text = l.text, id = l.id}
  end
  return out
end
M.copy_lines = copy_lines

--- A text of lines (`{ text, id }`) that keeps its own undo, as a buffer's `state.text`.
function M.text(lines?: {Line}): Text
  local t = setmetatable({lines = copy_lines(lines or {}), undos = {}, redos = {}} as Text, Text_mt)
  t.base = copy_lines(t.lines)
  if #t.lines == 0 then
    t.lines[1] = {text = ""}
  end
  return t
end

function Text:line(row: integer): string
  return self.lines[row] and self.lines[row].text or ""
end
function Text:len(row: integer): integer
  return width(self:line(row))
end
function Text:count(): integer
  return #self.lines
end

--- Whether the lines differ from what was read.
function Text:modified(): boolean
  local a, b = self.lines, self.base
  -- An empty listing is shown as one empty line.
  if #b == 0 and #a == 1 and a[1].text == "" then
    return false
  end
  if #a ~= #b then
    return true
  end
  for i = 1, #a do
    if a[i].text ~= b[i].text or a[i].id ~= b[i].id then
      return true
    end
  end
  return false
end

--- Start a change: the lines as they are go on the undo list, once for the
--- whole change (an insert stays one change until it is left).
function Text:begin(row: integer, col: integer)
  if self.open then
    return
  end
  self.open = true
  self.undos[#self.undos + 1] = {lines = copy_lines(self.lines), row = row, col = col}
  if #self.undos > 500 then
    table.remove(self.undos, 1)
  end
  self.redos = {}
end

function Text:finish()
  self.open = false
  -- A change that changed nothing leaves nothing to undo.
  local last = self.undos[#self.undos]
  if last and #last.lines == #self.lines then
    local same = true
    for i, l in ipairs(last.lines) do
      if l.text ~= self.lines[i].text or l.id ~= self.lines[i].id then
        same = false
        break
      end
    end
    if same then
      self.undos[#self.undos] = nil
    end
  end
  self.tick = (self.tick or 0) + 1
end

function Text:undo(row: integer, col: integer): integer, integer
  local step = table.remove(self.undos)
  if not step then
    return nil
  end
  self.redos[#self.redos + 1] = {lines = copy_lines(self.lines), row = row, col = col}
  self.lines = step.lines
  self.tick = (self.tick or 0) + 1
  return step.row, step.col
end

function Text:redo(row: integer, col: integer): integer, integer
  local step = table.remove(self.redos)
  if not step then
    return nil
  end
  self.undos[#self.undos + 1] = {lines = copy_lines(self.lines), row = row, col = col}
  self.lines = step.lines
  self.tick = (self.tick or 0) + 1
  return step.row, step.col
end

--- Put new lines in place of all, as read again; the undo list goes.
function Text:reset(lines: {Line})
  self.lines = copy_lines(lines)
  self.base = copy_lines(lines)
  if #self.lines == 0 then
    self.lines[1] = {text = ""}
  end
  self.undos, self.redos, self.open = {}, {}, false
  self.tick = (self.tick or 0) + 1
end

-- A text that cannot be changed (a page of help, `readonly` being what to
-- say) stays as it is, and says so.
local function frozen(t: Text): boolean
  if not t.readonly then
    return false
  end
  paw.notify(t.readonly, "warn")
  return true
end

function Text:set(row: integer, text: string)
  if frozen(self) then
    return
  end
  self.lines[row].text = text
end

--- The text from (r0, c0) up to (r1, c1), the end left out, lines joined
--- with "\n".
function Text:get_span(r0: integer, c0: integer, r1: integer, c1: integer): string
  if r0 == r1 then
    local _, rest = split(self:line(r0), c0)
    return (split(rest, c1 - c0))
  end
  local _, first = split(self:line(r0), c0)
  local parts = {first}
  for r = r0 + 1, r1 - 1 do
    parts[#parts + 1] = self:line(r)
  end
  parts[#parts + 1] = (split(self:line(r1), c1))
  return table.concat(parts, "\n")
end

--- Remove the text from (r0, c0) up to (r1, c1); the lines between go, and
--- the first keeps its id. Returns what was removed.
function Text:delete_span(r0: integer, c0: integer, r1: integer, c1: integer): string
  if frozen(self) then
    return ""
  end
  local gone = self:get_span(r0, c0, r1, c1)
  local head = split(self:line(r0), c0)
  local _, tail = split(self:line(r1), c1)
  self.lines[r0].text = head .. tail
  for _ = r0 + 1, r1 do
    table.remove(self.lines, r0 + 1)
  end
  return gone
end

--- Put text (which may hold "\n") at a position. Lines it makes are new.
--- Returns where it ends.
function Text:insert(row: integer, col: integer, text: string): integer, integer
  if frozen(self) then
    return row, col
  end
  local head, tail = split(self:line(row), col)
  local parts: {string} = {}
  for part in (text .. "\n"):gmatch("([^\n]*)\n") do
    parts[#parts + 1] = part
  end
  if #parts == 1 then
    self.lines[row].text = head .. parts[1] .. tail
    return row, col + width(parts[1])
  end
  self.lines[row].text = head .. parts[1]
  for i = 2, #parts do
    table.insert(self.lines, row + i - 1, {text = parts[i] .. (i == #parts and tail or "")})
  end
  return row + #parts - 1, width(parts[#parts])
end

--- Remove whole lines; returns them.
function Text:delete_lines(r0: integer, r1: integer): {Line}
  if frozen(self) then
    return {}
  end
  local out: {Line} = {}
  for _ = r0, r1 do
    if self.lines[r0] then
      out[#out + 1] = table.remove(self.lines, r0)
    end
  end
  if #self.lines == 0 then
    self.lines[1] = {text = ""}
  end
  return out
end

--- Put lines before row `at` (after the last with `#lines + 1`).
function Text:insert_lines(at: integer, lines: {Line})
  if frozen(self) then
    return
  end
  -- Into an empty listing, the lines take the place of its one empty line.
  if #self.lines == 1 and self.lines[1].text == "" and not self.lines[1].id then
    self.lines = {}
    at = 1
  end
  for i, l in ipairs(lines) do
    table.insert(self.lines, at + i - 1, {text = l.text, id = l.id})
  end
end

-- Kinds -------------------------------------------------------------------------------

--- The buffer shown in the keyboard's window, if it is a text buffer.
local function current_buf(): TextBuffer
  local _, buf = M.here()
  return buf
end

--- Make a kind of text buffer. It shows for the names that its `pattern`
--- matches (`paw://` and the others). See `docs/reference/lua-views.md`. A kind with
--- `readonly` (the message for a change) cannot change. A kind with
--- `scratch` (the message for `:w`) is never written, and `:q` closes it
--- with its changes. `gutter = false`
--- removes the line numbers. paw does not read a `static` kind again when
--- the project changes. `paint(canvas, x, y, text, kind, width, row, buf)`
--- draws a line in place of the usual colors.
---   paw.textbuf.kind("clips", { pattern = "^paw://clips$", read = ..., format = ..., parse = ..., plan = ... })
--- A kind also has the fields of a buffer type, next to the text:
--- `keymaps`, `motions`, `textobjects` and `operators` (see
--- `paw.layout.powers`. Their `ctx` has `buf`, `kind`, `args` and `target`).
--- `describe(ctx)` is for `K`, and `status(ctx, line)` is for the `view`
--- component of the status line. Its keys are in key scope
--- `textbuf.<name>`, before the keys of the text.
function M.kind<I is contracts.TextItem, F>(name: string, spec: contracts.TextKind<I, F>): contracts.TextKind<I, F>
  spec.name = name
  spec.pattern = spec.pattern or ("^paw://" .. name:gsub("%p", "%%%0") .. "$")
  M.kinds:put(name, spec as contracts.TextKind<contracts.TextItem, Fields>)
  layout.powers(
    "textbuf." .. name,
    spec,
    function(fn: Wrapped): Wrapped
      return function(ctx: KeyContext, region?: Region): Region
        local buf = current_buf()
        ctx = ctx or {}
        if buf then
          ctx.buf, ctx.kind, ctx.args, ctx.target = buf as LayoutBuffer, buf.state.kind, buf.state.args, buf.target
        end
        return fn(ctx, region)
      end
    end
  )
  return spec
end

--- The kind a buffer name is of, and what its pattern took from it.
local function kind_of(target: string): contracts.TextKind<contracts.TextItem, Fields>, {string}
  if not (target is string) then
    return nil
  end
  for _, spec in pairs(M.kinds:entries()) do
    local found = {target:match(spec.pattern)}
    if found[1] ~= nil then
      if found[1] == target and not spec.pattern:find("%(") then
        found = {}
      end
      return spec, found
    end
  end
end
M.kind_of = kind_of

--- Put cells in columns. Each column is as wide as its widest cell, with
--- two spaces between columns. paw removes the spaces at the end.
function M.align(rows: {{string}}): {string}
  local widths: {integer} = {}
  for _, cells in ipairs(rows) do
    for i, cell in ipairs(cells) do
      widths[i] = math.max(widths[i] or 0, width(cell))
    end
  end
  local out: {string} = {}
  for r, cells in ipairs(rows) do
    local parts: {string} = {}
    for i, cell in ipairs(cells) do
      parts[i] = i < #cells and cell .. string.rep(" ", widths[i] - width(cell)) or cell
    end
    out[r] = (table.concat(parts, "  "):gsub("%s+$", ""))
  end
  return out
end

--- The cells of a line: the stretches between runs of two spaces or more
--- (or a tab), each with the column it starts at.
function M.cells(text: string): {Cell}
  local out: {Cell} = {}
  local col = 0
  local pos = 1
  while pos <= #text do
    local s, e = text:find("%S.-%f[%s]", pos)
    if not s then
      s, e = text:find("%S.*$", pos)
      if not s then
        break
      end
    end
    -- A quoted name goes on to its closing quote, whatever spaces it holds.
    if text:sub(s, s) == '"' then
      local close = s + 1
      while true do
        local q = text:find('"', close, true)
        if not q then
          break
        end
        if text:sub(q - 1, q - 1) ~= "\\" then
          e = math.max(e, q)
          break
        end
        close = q + 1
      end
      local rest = text:find("%f[%s]", e + 1)
      e = rest and rest - 1 or #text
    end
    -- A cell goes on through single spaces.
    while true do
      local ns, ne = text:find("^ %S.-%f[%s]", e + 1)
      if not ns then
        ns, ne = text:find("^ %S.*$", e + 1)
      end
      if not ns then
        break
      end
      e = ne
    end
    col = col + width(text:sub(pos, s - 1))
    local cell = text:sub(s, e)
    out[#out + 1] = {text = cell, col = col}
    col = col + width(cell)
    pos = e + 1
  end
  return out
end

--- A name as a cell: quoted when it would not read back as itself.
function M.quote(name: string | number): string
  local text = tostring(name or "")
  if text == "" or text:find("  ") or text:find("\t") or text:match("^%s") or text:match("%s$") or text:match('^"') then
    return '"' .. text:gsub('"', '\\"') .. '"'
  end
  return text
end

--- A cell's text without the quotes `quote` put round it.
function M.unquote(cell: string): string
  local inner = cell:match('^"(.*)"$')
  if inner then
    return (inner:gsub('\\"', '"'))
  end
  return cell
end

-- Buffers ----------------------------------------------------------------------------

local function ctx_of(buf: TextBuffer): Context
  local st = buf.state
  return {target = buf.target, args = st.args, buf = buf as LayoutBuffer, kind = st.kind}
end

--- An item as a kind's `read` may give it: with the fields it reads as.
local record Item is contracts.TextItem
  fields: Fields
end

--- The lines a kind gives now: `{ text, id }` each, and the fields each id
--- reads as.
local function read(buf: TextBuffer): {Line}, {Id: Fields}, string
  local st = buf.state
  local ctx = ctx_of(buf)
  local items: {contracts.TextItem}
  local err: string
  local ok, failed = pcall(function() items, err = st.kind.read(ctx) end) as (boolean, string)
  if not ok then
    return nil, nil, reason(failed)
  end
  if not items then
    return nil, nil, err
  end
  local rows: {{string}} = {}
  for i, item in ipairs(items) do
    local cells: {string}
    local fine, why = pcall(function() cells = st.kind.format(item, ctx) end) as (boolean, string)
    if not fine then
      return nil, nil, reason(why)
    end
    rows[i] = cells
  end
  local texts = M.align(rows)
  local lines: {Line} = {}
  local fields: {Id: Fields} = {}
  for i, item in ipairs(items) do
    lines[i] = {text = texts[i], id = item.id}
    -- What the text reads as, not what the project holds: a line left as
    -- it was is no change, however the project rounds.
    local parsed = st.kind.parse(texts[i], ctx)
    fields[item.id] = parsed or (item as Item).fields or {}
  end
  return lines, fields
end

local function texts_equal(a: {Line}, b: {Line}): boolean
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i].text ~= b[i].text or a[i].id ~= b[i].id then
      return false
    end
  end
  return true
end

--- Read the buffer again from the project: the text, what it was read
--- from, and its undo list.
function M.reload(buf: TextBuffer)
  local st = buf.state
  local lines, fields, err = read(buf)
  if not lines then
    st.error = err
    lines, fields = {}, {}
  else
    st.error = nil
  end
  st.text:reset(lines)
  st.fields, st.conflict = fields, false
  st.order = {}
  for i, l in ipairs(lines) do
    st.order[l.id] = i
  end
  st.seen = project_edits("edits")
  st.parsed = {}
  api.ui_redraw()
end

--- Call it after the project changed. paw reads an unmodified buffer again.
--- paw marks a modified buffer as older than the project.
function M.sync(buf: TextBuffer)
  local st = buf.state
  if st.kind.static then
    return
  end
  local edits = project_edits("edits")
  if edits == st.seen then
    return
  end
  st.seen = edits
  local lines = read(buf)
  if not lines or texts_equal(lines, st.text.base) then
    return
  end
  if st.text:modified() then
    st.conflict = true
  else
    M.reload(buf)
  end
end

-- Every text buffer keeps up with the project as it changes.
local function sync_all()
  for _, buf in pairs(layout.buffers) do
    local tb = buf as TextBuffer
    if buf.type == "textbuf" and tb.state and tb.state.kind then
      M.sync(tb)
    end
  end
end
for _, family in ipairs({"part.*", "device.*", "project.*", "tempo.*"}) do
  events.on(events.pattern(family), sync_all)
end

--- What one line reads as: the fields, or nil and what is wrong. Kept by
--- text, as lines are read on every redraw.
local function parse(buf: TextBuffer, text: string): Fields, string
  local st = buf.state
  if text:match("^%s*$") then
    return nil
  end
  local hit = st.parsed[text]
  if hit then
    return hit[1] as Fields, hit[2] as string
  end
  local fields: Fields
  local err: string
  local ok, failed = pcall(function() fields, err = st.kind.parse(text, ctx_of(buf)) end) as (boolean, string)
  if not ok then
    fields, err = nil, reason(failed)
  end
  st.parsed[text] = {fields, err}
  return fields, err
end

--- True if the values of two fields are the same: numbers within a small tolerance,
--- and tables field by field.
local function same(a: Data, b: Data): boolean
  if a == b then
    return true
  end
  if not (a is {Data: Data}) or not (b is {Data: Data}) then
    if a is number and b is number then
      return math.abs(a - b) < 1e-9
    end
    return false
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

M.same = same

--- The changes that the lines ask for, compared with the data that paw
--- read. These are the lines that paw cannot read, and the items deleted,
--- changed (with the fields that changed), copied and added. It also tells if the kept items
--- are in a different order.
function M.changes(buf: TextBuffer): contracts.TextChanges<Fields>
  local st = buf.state
  local out: contracts.TextChanges<Fields> = {
    deleted = {}, changed = {}, copied = {}, added = {}, lines = {}, errors = {}, moved = false
  }
  local seen: {Id: boolean} = {}
  local kept: {Id} = {}
  for row, line in ipairs(st.text.lines) do
    if not line.text:match("^%s*$") then
      local fields, err = parse(buf, line.text)
      if not fields then
        out.errors[#out.errors + 1] = {row = row, text = line.text, error = err or "this line does not read"}
      else
        local entry: contracts.TextLine<Fields> = {row = row, fields = fields, id = line.id}
        local base = line.id ~= nil and st.fields[line.id]
        if base and not seen[line.id] then
          seen[line.id] = true
          entry.base = base
          entry.keys = {}
          for k, v in pairs(fields) do
            if not same(v, base[k]) then
              entry.keys[#entry.keys + 1] = k
            end
          end
          for k in pairs(base) do
            if fields[k] == nil then
              entry.keys[#entry.keys + 1] = k
            end
          end
          table.sort(entry.keys)
          if #entry.keys > 0 then
            out.changed[#out.changed + 1] = entry as contracts.TextChange<Fields>
          end
          kept[#kept + 1] = line.id
        elseif base then
          entry.copy_of, entry.base, entry.id = line.id, base, nil
          out.copied[#out.copied + 1] = entry
        else
          entry.id = nil
          out.added[#out.added + 1] = entry
        end
        out.lines[#out.lines + 1] = entry
      end
    end
  end
  local before: {Id} = {}
  for _, l in ipairs(st.text.base) do
    if not seen[l.id] then
      out.deleted[#out.deleted + 1] = {id = l.id, base = st.fields[l.id], row = st.order[l.id]}
    else
      before[#before + 1] = l.id
    end
  end
  for i, id in ipairs(kept) do
    if before[i] ~= id then
      out.moved = true
    end
  end
  -- The lines that moved: those out of the longest run that kept its
  -- order, each with where it was read (`from`) and where it is (`place`).
  local seq: {contracts.TextLine<Fields>} = {}
  for i, e in ipairs(out.lines) do
    e.place = i
    if e.base and not e.copy_of then
      seq[#seq + 1] = e
    end
  end
  local len: {integer} = {}
  local prev: {integer: integer} = {}
  local best = 0
  local last: integer
  for i, e in ipairs(seq) do
    e.from = st.order[e.id]
    len[i] = 1
    for j = 1, i - 1 do
      if seq[j].from < e.from and len[j] + 1 > len[i] then
        len[i], prev[i] = len[j] + 1, j
      end
    end
    if len[i] > best then
      best, last = len[i], i
    end
  end
  local stays: {integer: boolean} = {}
  while last do
    stays[last], last = true, prev[last]
  end
  out.moves = {}
  for i, e in ipairs(seq) do
    if not stays[i] then
      out.moves[#out.moves + 1] = e
    end
  end
  return out
end

-- Windows ---------------------------------------------------------------------------

-- The window a graphical frontend shows a buffer in, of its own.
local loose: Window
-- Insert mode under way.
local ins: Insert
paw.seats.keep(
  "textbuf", function(): Insert return ins end, function(i: Insert) ins = i end, function(): Insert return nil end
)

--- The text buffer window the keyboard is in.
function M.current(): Window
  local win = layout.current()
  if win and win.view == "textbuf" then
    return win
  end
  if ui().focused == "textbuf" and loose then
    return loose
  end
end

local function win_by_id(id: integer): Window
  return layout.get(id) or (loose and loose.id == id and loose) or nil
end

local function state(win: Window): Cursor
  local s = win.state as Cursor
  s.row = s.row or 1
  s.col = s.col or 0
  s.top = s.top or 1
  return s
end

--- The window, its buffer, the buffer's text and the window's cursor.
function M.here(): Window, TextBuffer, Text, Cursor
  local win = M.current()
  local buf = win and layout.buf_of(win) as TextBuffer
  if not (buf and buf.state and buf.state.text) then
    return nil
  end
  return win, buf, buf.state.text, state(win)
end
local here = M.here

--- Keep the cursor on the text: on a line, and on a character of it (or
--- at the end with `past`, as insert mode may be).
local function clamp(t: Text, s: Cursor, past?: boolean)
  s.row = math.tointeger(util.clamp(s.row, 1, t:count()))
  local n = t:len(s.row)
  s.col = math.tointeger(util.clamp(s.col, 0, math.max(0, past and n or n - 1)))
end

local function first_nonblank(t: Text, row: integer): integer
  local text = t:line(row)
  local lead = text:match("^%s*")
  return width(lead) < width(text) and width(lead) or 0
end

--- A change has been made that `.` may repeat.
local function changed(buf: TextBuffer)
  local st = buf.state
  st.modified = st.text:modified()
  if keymap.changed then
    keymap.changed()
  end
  api.ui_redraw()
end

-- Motions --------------------------------------------------------------------------

--- The character at a position, "\n" at the end of a line, nil past the last.
local function at(t: Text, row: integer, col: integer): string
  if row > t:count() then
    return nil
  end
  if col >= t:len(row) then
    return row < t:count() and "\n" or nil
  end
  return char_at(t:line(row), col)
end

local function step(t: Text, row: integer, col: integer): integer, integer
  if col < t:len(row) then
    return row, col + 1
  end
  if row < t:count() then
    return row + 1, 0
  end
  return nil
end

local function back(t: Text, row: integer, col: integer): integer, integer
  if col > 0 then
    return row, col - 1
  end
  if row > 1 then
    return row - 1, t:len(row - 1)
  end
  return nil
end

--- How a word motion finds its place: from a position, for words or WORDs.
local type WordFn = function(t: Text, row: integer, col: integer, big: boolean): integer, integer

--- The start of the next word, `big` for WORDs.
local function word_next(t: Text, row: integer, col: integer, big: boolean): integer, integer
  local c = class(at(t, row, col), big)
  local r, k = row, col
  -- Out of this word.
  -- With no word after it, the end of the text (past the last character).
  if c ~= 0 then
    while true do
      local nr, nk = step(t, r, k)
      if not nr then
        return r, t:len(r)
      end
      r, k = nr, nk
      if class(at(t, r, k), big) ~= c then
        break
      end
    end
  end
  -- Over the spaces; an empty line is a word of its own.
  while class(at(t, r, k), big) == 0 do
    if k == 0 and t:len(r) == 0 and r ~= row then
      return r, 0
    end
    local nr, nk = step(t, r, k)
    if not nr then
      return r, t:len(r)
    end
    r, k = nr, nk
  end
  return r, k
end

local function word_end(t: Text, row: integer, col: integer, big: boolean): integer, integer
  local r, k = step(t, row, col)
  if not r then
    return row, col
  end
  while class(at(t, r, k), big) == 0 do
    local nr, nk = step(t, r, k)
    if not nr then
      return r, k
    end
    r, k = nr, nk
  end
  local c = class(at(t, r, k), big)
  while true do
    local nr, nk = step(t, r, k)
    if not nr or class(at(t, nr, nk), big) ~= c then
      return r, k
    end
    r, k = nr, nk
  end
end

local function word_back(t: Text, row: integer, col: integer, big: boolean): integer, integer
  local r, k = back(t, row, col)
  if not r then
    return row, col
  end
  while class(at(t, r, k), big) == 0 do
    if k == 0 and t:len(r) == 0 then
      return r, 0
    end
    local nr, nk = back(t, r, k)
    if not nr then
      return r, k
    end
    r, k = nr, nk
  end
  local c = class(at(t, r, k), big)
  while true do
    local nr, nk = back(t, r, k)
    if not nr or nr ~= r or class(at(t, nr, nk), big) ~= c then
      return r, k
    end
    r, k = nr, nk
  end
end

--- The last `f`, `F`, `t` or `T`, for `;` and `,`.
local record Find
  how: string
  ch: string
end
local last_find: Find

--- The column `f`, `F`, `t` or `T` and a character take the cursor to, `n`
--- times; `again` (for `;`) passes over the character `t` stopped before.
local function find_char(t: Text, s: Cursor, how: string, ch: string, n: integer, again?: boolean): integer
  local cs = chars(t:line(s.row))
  local forward = how == "f" or how == "t"
  local col = s.col
  -- Where `t` or `T` stands, the character it stopped before is passed over.
  if again and how == "t" then
    col = col + 1
  elseif again and how == "T" then
    col = col - 1
  end
  for _ = 1, n do
    local found: integer
    if forward then
      for k = col + 2, #cs do
        if cs[k] == ch then
          found = k - 1
          break
        end
      end
    else
      for k = col, 1, -1 do
        if cs[k] == ch then
          found = k - 1
          break
        end
      end
    end
    if not found then
      return nil
    end
    col = found
  end
  if how == "t" then
    col = col - 1
  elseif how == "T" then
    col = col + 1
  end
  return col
end

--- What a motion does to the cursor: the text, the cursor, the count,
--- the key's context and the buffer.
local type MoveFn = function(t: Text, s: Cursor, n: integer, ctx: KeyContext, buf: TextBuffer)

--- The motions: each moves the cursor of the current window.
local motions: {string: contracts.KeyFn} = {}

local function move(fn: MoveFn): contracts.KeyFn
  return function(ctx?: KeyContext)
    local win, buf, t, s = here()
    if not win then
      return
    end
    fn(t, s, ctx.count or 1, ctx, buf)
    api.ui_redraw()
  end
end

motions.left = move(function(_: Text, s: Cursor, n: integer) s.col = math.max(0, s.col - n); s.want = s.col end)
motions.right = move(
  function(t: Text, s: Cursor, n: integer, ctx: KeyContext)
    -- After an operator, `l` may take the last character of the line.
    s.col = math.min(s.col + n, math.max(0, t:len(s.row) - (ctx.mode == "o" and 0 or 1)))
    s.want = s.col
  end
)
local function vertical(t: Text, s: Cursor, n: integer)
  s.row = math.tointeger(util.clamp(s.row + n, 1, t:count()))
  s.col = math.tointeger(math.min(s.want or s.col, math.max(0, t:len(s.row) - 1)))
end
motions.down = move(function(t: Text, s: Cursor, n: integer) vertical(t, s, n) end)
motions.up = move(function(t: Text, s: Cursor, n: integer) vertical(t, s, -n) end)
motions.first = move(
  function(t: Text, s: Cursor, _: integer, ctx: KeyContext)
    s.row = ctx.count and math.tointeger(util.clamp(ctx.count, 1, t:count())) or 1
    s.col, s.want = first_nonblank(t, s.row), nil
  end
)
motions.last = move(
  function(t: Text, s: Cursor, _: integer, ctx: KeyContext)
    s.row = ctx.count and math.tointeger(util.clamp(ctx.count, 1, t:count())) or t:count()
    s.col, s.want = first_nonblank(t, s.row), nil
  end
)
motions.home = move(function(_: Text, s: Cursor) s.col, s.want = 0, 0 end)
motions.nonblank = move(function(t: Text, s: Cursor) s.col = first_nonblank(t, s.row); s.want = s.col end)
motions.line_end = move(
  function(t: Text, s: Cursor, n: integer, ctx: KeyContext)
    if n > 1 then
      s.row = math.min(t:count(), s.row + n - 1)
    end
    s.col = math.max(0, t:len(s.row) - (ctx.mode == "o" and 0 or 1))
    s.want = math.huge
  end
)
local function words(fn: WordFn, big: boolean): contracts.KeyFn
  return move(
    function(t: Text, s: Cursor, n: integer, ctx: KeyContext)
      for _ = 1, n do
        local r, k = fn(t, s.row, s.col, big)
        -- After an operator a word ends at the end of its line, as in Vim.
        if ctx.mode == "o" and fn == word_next and r > s.row then
          r, k = s.row, t:len(s.row)
          s.row, s.col = r, k
          break
        end
        s.row, s.col = r, k
      end
      s.want = s.col
    end
  )
end
motions.w, motions.W = words(word_next, false), words(word_next, true)
motions.b, motions.B = words(word_back, false), words(word_back, true)
motions.e, motions.E = words(word_end, false), words(word_end, true)
local OTHER_WAY: {string: string} = {f = "F", F = "f", t = "T", T = "t"}
local function finder(how: string): contracts.KeyFn
  return move(
    function(t: Text, s: Cursor, n: integer, ctx: KeyContext)
      local ch = ctx.char
      if how == ";" or how == "," then
        if not last_find then
          return
        end
        local h = last_find.how
        if how == "," then
          h = OTHER_WAY[h]
        end
        local col = find_char(t, s, h, last_find.ch, n, true)
        if col then
          s.col, s.want = col, col
        end
        return
      end
      last_find = {how = how, ch = ch}
      local col = find_char(t, s, how, ch, n)
      if col then
        s.col, s.want = col, col
      end
    end
  )
end
for _, how in ipairs({"f", "F", "t", "T", ";", ","}) do
  motions[how] = finder(how)
end
motions.half_down = move(
  function(t: Text, s: Cursor, n: integer) vertical(t, s, n * math.max(1, math.floor((s.height or 20) / 2))) end
)
motions.half_up = move(
  function(t: Text, s: Cursor, n: integer) vertical(t, s, -n * math.max(1, math.floor((s.height or 20) / 2))) end
)

-- Motions that take the character they land on, after an operator.
local inclusive: {string: boolean} = {e = true, E = true, f = true, t = true, ["$"] = true, [";"] = true, [","] = true}

-- Regions ---------------------------------------------------------------------------

--- A region of the keymap as a span of the text: `kind` "line" (rows
--- `r0` to `r1`), "char" (from (r0, c0) up to (r1, c1), the end left out)
--- or "block" (rows and columns `c0` to `c1`, the end left out).
local function span(region: Region, ctx: KeyContext, t: Text): Span
  if region.kind == "line" then
    return {
      kind = "line", r0 = math.tointeger(math.max(1, region.r0)), r1 = math.tointeger(math.min(t:count(), region.r1))
    }
  end
  local a, b = math.tointeger(region.c0), math.tointeger(region.c1)
  local r0, c0 = a // BIG, a % BIG
  local r1, c1 = b // BIG, b % BIG
  if region.kind == "block" then
    local lo, hi = math.min(c0, c1), math.max(c0, c1)
    if region.unstretched then
      hi = lo
    end
    return {kind = "block", r0 = math.tointeger(region.r0), r1 = math.tointeger(region.r1), c0 = lo, c1 = hi + 1}
  end
  if region.unstretched then
    r1, c1 = r0, c0
  end
  -- A selection takes its last character; so does a motion that lands on it.
  if region.visual or (region.object == nil and ctx and inclusive[ctx.keys or ""]) then
    if c1 < t:len(r1) then
      c1 = c1 + 1
    elseif r1 < t:count() and region.visual then
      r1, c1 = r1 + 1, 0
    end
  end
  return {kind = "char", r0 = r0, c0 = c0, r1 = r1, c1 = c1}
end

local function region_of(r0: integer, c0: integer, r1: integer, c1: integer, kind?: string): Region
  return {
    view = "textbuf", kind = kind or "char", r0 = r0, r1 = r1, c0 = r0 * BIG + c0, c1 = r1 * BIG + c1, object = true
  }
end

--- What a span holds, for a register.
local function yank_span(t: Text, sp: Span, buf: TextBuffer): Register
  if sp.kind == "line" then
    local lines: {Line} = {}
    for r = sp.r0, sp.r1 do
      lines[#lines + 1] = {text = t:line(r), id = t.lines[r].id}
    end
    return {kind = "lines", lines = lines, source = buf.name}
  elseif sp.kind == "block" then
    local rows: {string} = {}
    for r = sp.r0, sp.r1 do
      local _, rest = split(t:line(r), sp.c0)
      rows[#rows + 1] = (split(rest, sp.c1 - sp.c0))
    end
    return {kind = "block", rows = rows}
  end
  return {kind = "text", text = t:get_span(sp.r0, sp.c0, sp.r1, sp.c1)}
end

local function delete_span(t: Text, sp: Span)
  if sp.kind == "line" then
    t:delete_lines(sp.r0, sp.r1)
    return
  end
  if sp.kind == "block" then
    for r = sp.r0, sp.r1 do
      if t.lines[r] then
        local head, rest = split(t:line(r), sp.c0)
        local _, tail = split(rest, sp.c1 - sp.c0)
        t:set(r, head .. tail)
      end
    end
    return
  end
  t:delete_span(sp.r0, sp.c0, sp.r1, sp.c1)
end

-- Insert mode ---------------------------------------------------------------------

local insert_key: function(key: string, pasted?: boolean)

local function insert_finish()
  local done = ins
  ins = nil
  if ui().grabber == insert_key then
    ui().grabber = nil
  end
  if not done then
    return
  end
  local win = win_by_id(done.win)
  local buf = layout.buffers[done.buf] as TextBuffer
  if not (win and buf and buf.state.text) then
    return
  end
  local t, s = buf.state.text, state(win)
  -- A block insert: what was typed on the first line goes on the others.
  local block = done.block
  if block then
    local before, now = block.before, t:line(block.r0)
    local typed: string
    if now ~= before then
      local _, after = split(now, block.col)
      typed = after
    end
    if typed then
      local _, tail = split(before, block.col)
      typed = typed:sub(1, #typed - #tail)
      if typed ~= "" and not typed:find("\n") then
        for r = block.r0 + 1, block.r1 do
          if t.lines[r] then
            local n = t:len(r)
            if n >= block.col or block.append then
              local col = block.col
              if n < col then
                t:set(r, t:line(r) .. string.rep(" ", col - n))
              end
              t:insert(r, col, typed)
            end
          end
        end
      end
    end
  end
  t:finish()
  s.col = math.max(0, s.col - 1)
  clamp(t, s)
  s.want = s.col
  if keymap.mode == "i" then
    keymap.set_mode("n")
  end
  changed(buf)
end

local SPECIAL_CHARS: {string: string} = {["<Space>"] = " ", ["<lt>"] = "<", ["<Bar>"] = "|", ["<Bslash>"] = "\\"}

insert_key = function(key: string, pasted?: boolean)
  local win = ins and win_by_id(ins.win)
  local buf = ins and layout.buffers[ins.buf] as TextBuffer
  if not (win and buf) then
    ins = nil
    ui().grabber = nil
    return
  end
  local t, s = buf.state.text, state(win)
  if pasted then
    s.row, s.col = t:insert(s.row, s.col, (key:gsub("\r\n?", "\n")))
    return api.ui_redraw()
  end
  if key == "<Esc>" or key == "<C-c>" or key == "<C-[>" then
    return insert_finish()
  end
  if key == "<CR>" or key == "<C-j>" or key == "<C-m>" then
    s.row, s.col = t:insert(s.row, s.col, "\n")
  elseif key == "<BS>" or key == "<C-h>" then
    if s.col > 0 then
      t:delete_span(s.row, s.col - 1, s.row, s.col)
      s.col = s.col - 1
    elseif s.row > 1 then
      local n = t:len(s.row - 1)
      t:delete_span(s.row - 1, n, s.row, 0)
      s.row, s.col = s.row - 1, n
    end
  elseif key == "<Del>" then
    if s.col < t:len(s.row) then
      t:delete_span(s.row, s.col, s.row, s.col + 1)
    elseif s.row < t:count() then
      t:delete_span(s.row, s.col, s.row + 1, 0)
    end
  elseif key == "<C-w>" then
    local cs = chars(t:line(s.row))
    local k = s.col
    while k > 0 and cs[k]:match("^%s$") do
      k = k - 1
    end
    local c = k > 0 and class(cs[k]) or 0
    while k > 0 and class(cs[k]) == c and c ~= 0 do
      k = k - 1
    end
    t:delete_span(s.row, k, s.row, s.col)
    s.col = k
  elseif key == "<C-u>" then
    t:delete_span(s.row, 0, s.row, s.col)
    s.col = 0
  elseif key == "<Left>" then
    s.col = math.max(0, s.col - 1)
  elseif key == "<Right>" then
    s.col = math.min(t:len(s.row), s.col + 1)
  elseif key == "<Up>" or key == "<Down>" then
    s.row = math.tointeger(util.clamp(s.row + (key == "<Up>" and -1 or 1), 1, t:count()))
    s.col = math.min(s.col, t:len(s.row))
  elseif key == "<Home>" then
    s.col = 0
  elseif key == "<End>" then
    s.col = t:len(s.row)
  elseif key == "<Tab>" then
    -- Fields are two spaces apart.
    s.row, s.col = t:insert(s.row, s.col, "  ")
  else
    local ch = SPECIAL_CHARS[key] or key
    if not ch:match("^<.+>$") then
      s.row, s.col = t:insert(s.row, s.col, ch)
    end
  end
  api.ui_redraw()
end

--- Hand the keyboard to insert mode in a window, its change begun.
local function begin_insert(win: Window, buf: TextBuffer, block?: Block)
  ins = {win = win.id, buf = buf.id, block = block}
  ui().grabber = insert_key
  keymap.set_mode("i")
  api.ui_redraw()
end

--- Start insert mode at the cursor of the current window. `how` is "i"
--- before the cursor, "a" after it, or "I" at the first character that is
--- not a space. It is "A" at the end, "o" on a new line below, or "O" above.
function M.insert(how: string, opts?: InsertOptions)
  local win, buf, t, s = here()
  if not win then
    return
  end
  if t.readonly then
    return paw.notify(t.readonly, "warn")
  end
  if keymap.mode == "x" then
    keymap.set_mode("n")
  end
  t:begin(s.row, s.col)
  if how == "a" then
    s.col = math.min(t:len(s.row), s.col + 1)
  elseif how == "A" then
    s.col = t:len(s.row)
  elseif how == "I" then
    s.col = first_nonblank(t, s.row)
  elseif how == "o" then
    t:insert_lines(s.row + 1, {{text = ""}})
    s.row, s.col = math.min(s.row + 1, t:count()), 0
  elseif how == "O" then
    t:insert_lines(s.row, {{text = ""}})
    s.col = 0
  end
  begin_insert(win, buf, opts and opts.block)
end

--- The payload of `mode.changed` (paw/keymap.tl): the mode, and the one before.
local type ModeChanged = KeymapModule.ModeChanged

-- Insert mode ends when the window loses the keyboard.
events.on(
  paw.keymap.mode_changed,
  function(e: ModeChanged)
    if e.old == "i" and e.mode ~= "i" and ins then
      insert_finish()
    end
  end
)

-- Operators -----------------------------------------------------------------------

--- What an operator does on a span; true keeps the change open (insert
--- mode carries it on).
local type SpanFn = function(t: Text, sp: Span, ctx: KeyContext, s: Cursor, buf: TextBuffer): boolean

local function on_span(fn: SpanFn): Operator
  return function(region: Region, ctx?: KeyContext)
    local win, buf, t, s = here()
    if not win then
      return
    end
    local sp = span(region, ctx, t)
    t:begin(s.row, s.col)
    local keep_open = fn(t, sp, ctx or {}, s, buf)
    if not keep_open then
      t:finish()
      clamp(t, s)
      changed(buf)
    end
  end
end

local function to_start(t: Text, s: Cursor, sp: Span)
  s.row = sp.r0
  s.col = sp.kind == "line" and first_nonblank(t, sp.r0) or sp.c0
  clamp(t, s)
  s.want = s.col
end

M.ops = {}

M.ops.delete = on_span(
  function(t: Text, sp: Span, ctx: KeyContext, s: Cursor, buf: TextBuffer): boolean
    keymap.setreg(yank_span(t, sp, buf), ctx.register)
    delete_span(t, sp)
    to_start(t, s, sp)
  end
)

M.ops.yank = on_span(
  function(t: Text, sp: Span, ctx: KeyContext, s: Cursor, buf: TextBuffer): boolean
    local value = yank_span(t, sp, buf)
    keymap.setreg(value, ctx.register, true)
    if sp.kind ~= "line" then
      to_start(t, s, sp)
    end
    local n = value.lines and #value.lines or 0
    if n > 2 then
      paw.notify(n .. " lines yanked")
    end
  end
)

M.ops.change = on_span(
  function(t: Text, sp: Span, ctx: KeyContext, s: Cursor, buf: TextBuffer): boolean
    -- `cw` changes the word and leaves the spaces after it, as `ce` would.
    if sp.kind == "char" and (ctx.keys == "w" or ctx.keys == "W") and sp.r0 == sp.r1 then
      local cs = chars(t:line(sp.r0))
      while sp.c1 > sp.c0 + 1 and (cs[sp.c1] or ""):match("^%s$") do
        sp.c1 = sp.c1 - 1
      end
    end
    keymap.setreg(yank_span(t, sp, buf), ctx.register)
    if sp.kind == "line" then
      -- The lines go but the first, which is emptied: it stays what it was.
      local first = t.lines[sp.r0]
      if sp.r1 > sp.r0 then
        t:delete_lines(sp.r0 + 1, sp.r1)
      end
      local lead = first.text:match("^%s*")
      t:set(sp.r0, lead)
      s.row, s.col = sp.r0, width(lead)
    else
      delete_span(t, sp)
      s.row, s.col = sp.r0, sp.c0
    end
    -- Insert mode carries the change on, as one change with what is typed;
    -- on a block, what is typed goes on each of its lines.
    local block: Block = sp.kind == "block" and {r0 = sp.r0, r1 = sp.r1, col = sp.c0, before = t:line(sp.r0)} or nil
    begin_insert(M.current(), buf, block)
    return true
  end
)

local function case_op(fn: function(string): string): Operator
  return on_span(
    function(t: Text, sp: Span, _: KeyContext, s: Cursor): boolean
      if sp.kind == "line" then
        for r = sp.r0, sp.r1 do
          t:set(r, fn(t:line(r)))
        end
      elseif sp.kind == "block" then
        for r = sp.r0, sp.r1 do
          if t.lines[r] then
            local head, rest = split(t:line(r), sp.c0)
            local mid, tail = split(rest, sp.c1 - sp.c0)
            t:set(r, head .. fn(mid) .. tail)
          end
        end
      else
        local text = t:get_span(sp.r0, sp.c0, sp.r1, sp.c1)
        t:delete_span(sp.r0, sp.c0, sp.r1, sp.c1)
        t:insert(sp.r0, sp.c0, fn(text))
      end
      to_start(t, s, sp)
    end
  )
end
local function swapcase(text: string): string
  return (text:gsub("%a", function(c: string): string return c:match("%l") and c:upper() or c:lower() end))
end
M.ops.lower = case_op(string.lower)
M.ops.upper = case_op(string.upper)
M.ops.swapcase = case_op(swapcase)

-- Numbers: Ctrl-a and Ctrl-x -----------------------------------------------------------

--- Add `n` to the number at or after column `col` of a text, up to column
--- `limit`. A sign before it counts. Decimals also count, and paw keeps
--- them. Returns the new text and the column of the last character of the number.
function M.add_number(text: string, col: integer, n: number, limit?: integer): string, integer
  local cs = chars(text)
  -- Back to the start of the number under the cursor, if on one.
  local k = col + 1
  local function digit(i: integer): boolean
    return cs[i] and cs[i]:match("^%d$") ~= nil
  end
  if digit(k) or (cs[k] == "." and digit(k + 1) and digit(k - 1)) then
    while k > 1 and (digit(k - 1) or (cs[k - 1] == "." and digit(k - 2))) do
      k = k - 1
    end
  else
    while k <= #cs and not digit(k) and (not limit or k <= limit) do
      k = k + 1
    end
    if not digit(k) or (limit and k > limit) then
      return nil
    end
  end
  local s = k
  if cs[s - 1] == "-" then
    s = s - 1
  end
  local e = k
  while digit(e + 1) or (cs[e + 1] == "." and digit(e + 2)) do
    e = e + 1
  end
  local str = table.concat(cs, "", s, e)
  local value = tonumber(str)
  if not value then
    return nil
  end
  local decimals = str:match("%.(%d+)$")
  local new = value + n
  local out = decimals and string.format("%." .. #decimals .. "f", new) or string.format("%d", math.tointeger(new))
  local zeros = not decimals and str:match("^%-?(0%d+)$")
  if zeros then
    out = (new < 0 and "-" or "") .. string.format("%0" .. #zeros .. "d", math.abs(new))
  end
  return table.concat(cs, "", 1, s - 1) .. out .. table.concat(cs, "", e + 1), s - 1 + width(out) - 1
end

--- Add `n` to the number at or after the cursor (`Ctrl-a`, `Ctrl-x`).
function M.increment(n: number)
  local win, buf, t, s = here()
  if not win then
    return
  end
  local text, col = M.add_number(t:line(s.row), s.col, n)
  if not text then
    return
  end
  t:begin(s.row, s.col)
  t:set(s.row, text)
  t:finish()
  s.col, s.want = col, col
  changed(buf)
end

--- The operator that adds `by` times the count to the numbers selected.
M.ops.increment = function(by: integer): Operator
  return on_span(
    function(t: Text, sp: Span, ctx: KeyContext, s: Cursor): boolean
      local n = by * (ctx.count or 1)
      local r0, r1 = sp.r0, sp.r1
      for r = r0, r1 do
        if t.lines[r] then
          local from = (sp.kind == "block" or (sp.kind == "char" and r == r0)) and sp.c0 or 0
          local limit = sp.kind == "block" and sp.c1 or nil
          local text = M.add_number(t:line(r), from, n, limit)
          if text then
            t:set(r, text)
          end
        end
      end
      to_start(t, s, sp)
    end
  )
end

-- Putting ---------------------------------------------------------------------------

--- Put a register's text after the cursor, or before it (`p`, `P`).
function M.put(before: boolean, register?: string, count?: integer)
  local win, buf, t, s = here()
  if not win then
    return
  end
  local value = keymap.getreg(register) as Register
  if not value then
    return paw.notify("nothing to put yet", "warn")
  end
  count = count or 1
  t:begin(s.row, s.col)
  if value.kind == "lines" or value.kind == "parts" then
    local lines: {Line} = {}
    for _ = 1, count do
      for _, l in ipairs(value.lines or {}) do
        -- An id means something only in the buffer it was yanked from.
        lines[#lines + 1] = {text = l.text, id = value.source == buf.name and l.id or nil}
      end
    end
    if #lines == 0 then
      t:finish()
      return paw.notify("that register holds " .. value.kind .. ", which is not text", "warn")
    end
    local to = before and s.row or s.row + 1
    if t:count() == 1 and t:line(1) == "" and not t.lines[1].id then
      to = 1
    end
    t:insert_lines(to, lines)
    s.row = math.min(to, t:count())
    s.col = first_nonblank(t, s.row)
  elseif value.kind == "text" then
    local col = before and s.col or math.min(t:len(s.row), s.col + 1)
    local r, c = t:insert(s.row, col, string.rep(value.text, count))
    if value.text:find("\n") then
      s.col = col
    else
      s.row, s.col = r, math.max(0, c - 1)
    end
  elseif value.kind == "block" then
    local col = before and s.col or math.min(t:len(s.row), s.col + 1)
    local w = 0
    for _, row in ipairs(value.rows) do
      w = math.max(w, width(row))
    end
    for i, row in ipairs(value.rows) do
      local r = s.row + i - 1
      if not t.lines[r] then
        t:insert_lines(r, {{text = ""}})
      end
      local n = t:len(r)
      if n < col then
        t:set(r, t:line(r) .. string.rep(" ", col - n))
      end
      local piece = row .. string.rep(" ", w - width(row))
      t:insert(r, col, string.rep(piece, count))
    end
    s.col = col
  else
    t:finish()
    return paw.notify("that register holds " .. tostring(value.kind) .. ", which is not text", "warn")
  end
  t:finish()
  clamp(t, s)
  s.want = s.col
  changed(buf)
end

-- Small changes -----------------------------------------------------------------------

local function small(fn: MoveFn): contracts.KeyFn
  return function(ctx?: KeyContext)
    local win, buf, t, s = here()
    if not win then
      return
    end
    t:begin(s.row, s.col)
    fn(t, s, ctx.count or 1, ctx, buf)
    t:finish()
    clamp(t, s)
    changed(buf)
  end
end

--- Replace the characters under the cursor with the one typed (`r`).
M.replace = small(
  function(t: Text, s: Cursor, n: integer, ctx: KeyContext)
    local ch = ctx.char
    if not ch or ch:match("^<.+>$") then
      return
    end
    if s.col + n > t:len(s.row) then
      return
    end
    t:delete_span(s.row, s.col, s.row, s.col + n)
    t:insert(s.row, s.col, string.rep(ch, n))
    s.col = s.col + n - 1
  end
)

--- Join lines (`J`).
M.join = small(
  function(t: Text, s: Cursor, n: integer)
    for _ = 1, math.max(1, n - 1) do
      if s.row >= t:count() then
        break
      end
      local a = t:line(s.row):gsub("%s+$", "")
      local b = t:line(s.row + 1):gsub("^%s+", "")
      local col = width(a)
      t:set(s.row, a .. (b ~= "" and a ~= "" and " " or "") .. b)
      t:delete_lines(s.row + 1, s.row + 1)
      s.col = col
    end
  end
)

--- Swap the case of the characters under the cursor (`~`).
M.tilde = small(
  function(t: Text, s: Cursor, n: integer)
    local stop = math.min(t:len(s.row), s.col + n)
    if stop <= s.col then
      return
    end
    local text = t:get_span(s.row, s.col, s.row, stop)
    t:delete_span(s.row, s.col, s.row, stop)
    t:insert(s.row, s.col, swapcase(text))
    s.col = math.min(stop, t:len(s.row) - 1)
  end
)

--- Undo `n` changes of the text, or redo them.
function M.undo(redo: boolean, n?: integer)
  local win, buf, t, s = here()
  if not win then
    return
  end
  local done = 0
  for _ = 1, n or 1 do
    local row, col: integer, integer
    if redo then
      row, col = t:redo(s.row, s.col)
    else
      row, col = t:undo(s.row, s.col)
    end
    if not row then
      break
    end
    s.row, s.col, done = row, col, done + 1
  end
  if done == 0 then
    return paw.notify(
      redo and "already at the newest change" or "already at the oldest change: the project's own undo is `:undo`"
    )
  end
  clamp(t, s)
  buf.state.modified = t:modified()
  api.ui_redraw()
end

-- Text objects ------------------------------------------------------------------------

local type Object = KeymapModule.TextObject

local function word_object(around: boolean, big: boolean): Object
  return function(): Region
    local win, _, t, s = here()
    if not win then
      return nil
    end
    local cs = chars(t:line(s.row))
    if #cs == 0 then
      return nil
    end
    local k = s.col + 1
    local c = class(cs[k], big)
    local a, b = k, k
    while a > 1 and class(cs[a - 1], big) == c do
      a = a - 1
    end
    while b < #cs and class(cs[b + 1], big) == c do
      b = b + 1
    end
    if around then
      if b < #cs and class(cs[b + 1], big) == 0 then
        while b < #cs and class(cs[b + 1], big) == 0 do
          b = b + 1
        end
      else
        while a > 1 and class(cs[a - 1], big) == 0 do
          a = a - 1
        end
      end
    end
    return region_of(s.row, a - 1, s.row, b)
  end
end

--- A field of the line under the cursor: its value (after a keyword the
--- kind names), or with `around` the whole field.
local function field_object(around: boolean): Object
  return function(): Region
    local win, buf, t, s = here()
    if not win then
      return nil
    end
    local cells = M.cells(t:line(s.row))
    local pick: Cell
    for _, cell in ipairs(cells) do
      if cell.col <= s.col then
        pick = cell
      end
    end
    pick = pick or cells[1]
    if not pick then
      return nil
    end
    local from, to = pick.col, pick.col + width(pick.text)
    if not around then
      local kw = buf.state.kind.keywords or {}
      local word = pick.text:match("^(%S+) (.+)$")
      if word and kw[word] then
        from = from + width(word) + 1
      end
      local sign = pick.text:match("^(▸) ") or pick.text:match("^(>) ")
      if sign then
        from = pick.col + width(sign) + 1
      end
    end
    return region_of(s.row, from, s.row, to)
  end
end

-- Ex lines -----------------------------------------------------------------------------
--
-- What `:` takes in a text buffer, before the commands do: `:w`, `:w!`,
-- `:e!`, a line number, and ranges of lines (`%`, `.`, `$`, `'<,'>`,
-- numbers, `+n`) for `:s`, `:sort`, `:d`, `:y`, `:m`, `:normal`.

local function address(text: string, t: Text, s: Cursor): integer, string
  local base: integer
  local rest = text
  local function take(pat: string): string
    local got = rest:match("^" .. pat)
    if got then
      rest = rest:sub(#got + 1)
    end
    return got
  end
  if take("%.") then
    base = s.row
  elseif take("%$") then
    base = t:count()
  elseif take("'<") then
    local v = keymap.last_visual
    base = v and math.tointeger(math.min(v.row, v.cursor_row or v.row)) or s.row
  elseif take("'>") then
    local v = keymap.last_visual
    base = v and math.tointeger(math.max(v.row, v.cursor_row or v.row)) or s.row
  else
    local n = take("%d+")
    if n then
      base = math.tointeger(tonumber(n))
    end
  end
  while true do
    local sign, n = rest:match("^([%+%-])(%d*)")
    if not sign then
      break
    end
    rest = rest:sub(#sign + #n + 1)
    base = (base or s.row) + (sign == "-" and -1 or 1) * (math.tointeger(tonumber(n)) or 1)
  end
  return base, rest
end

local function range(line: string, t: Text, s: Cursor): integer, integer, string, boolean
  if line:sub(1, 1) == "%" then
    return 1, t:count(), line:sub(2), true
  end
  local a, rest = address(line, t, s)
  if not a then
    return nil, nil, line, false
  end
  local b = a
  if rest:sub(1, 1) == "," or rest:sub(1, 1) == ";" then
    local second: integer
    second, rest = address(rest:sub(2), t, s)
    b = second or a
  end
  if a > b then
    a, b = b, a
  end
  return a, b, rest, true
end

--- Vim's patterns as Lua's, as far as they go: `\d` `\s` `\w` `\(` `\)`;
--- a Lua pattern's `%` works as it is.
local VIM_CLASSES: {string: string} = {
  d = "%d",
  s = "%s",
  w = "[%w_]",
  D = "%D",
  S = "%S",
  W = "[^%w_]",
  a = "%a",
  ["("] = "(",
  [")"] = ")",
  ["."] = "%.",
  ["*"] = "%*",
  ["["] = "%[",
  ["]"] = "%]",
  ["/"] = "/",
}
local function lua_pattern(pat: string): string
  local out = pat:gsub("\\([dswDSWa%(%)%.%*%[%]/])", VIM_CLASSES)
  return out
end

local function replacement(rep: string): string
  return (rep:gsub("%%", "%%%%"):gsub("\\(%d)", "%%%1"):gsub("&", "%%0"):gsub("\\%%%%0", "&"))
end

local function substitute(t: Text, a: integer, b: integer, args: string): integer, integer, string
  local sep = args:sub(1, 1)
  if sep == "" or sep:match("[%w%s\"|]") then
    return nil, nil, "usage: s/pattern/replacement/[g]"
  end
  local parts: {string} = {}
  local cur, i = "", 2
  while i <= #args do
    local ch = args:sub(i, i)
    if ch == "\\" and args:sub(i + 1, i + 1) == sep then
      cur, i = cur .. sep, i + 2
    elseif ch == "\\" then
      cur, i = cur .. ch .. args:sub(i + 1, i + 1), i + 2
    elseif ch == sep and #parts < 2 then
      parts[#parts + 1], cur, i = cur, "", i + 1
    else
      cur, i = cur .. ch, i + 1
    end
  end
  parts[#parts + 1] = cur
  local pat, rep, flags = parts[1] or "", parts[2] or "", parts[3] or ""
  if pat == "" then
    return nil, nil, "no pattern"
  end
  pat = lua_pattern(pat)
  rep = replacement(rep)
  local ok = pcall(string.find, "", pat)
  if not ok then
    return nil, nil, "the pattern does not read: " .. pat
  end
  local count, lines = 0, 0
  for r = a, b do
    local text = t:line(r)
    local new, n = text:gsub(pat, rep, flags:find("g") and nil or 1)
    if n > 0 then
      t:set(r, new)
      count, lines = count + n, lines + 1
    end
  end
  return count, lines
end

local function sort_lines(t: Text, a: integer, b: integer, flags: string)
  local list: {Line} = {}
  for r = a, b do
    list[#list + 1] = t.lines[r]
  end
  local numeric, fold, reverse = flags:find("n"), flags:find("i"), flags:find("!")
  local pat = flags:match("/(.-)/")
  -- A line's key: a number with `n`, else its text.
  local function key(l: Line): string | number
    local text = l.text
    if pat then
      local _, e = text:find(lua_pattern(pat))
      text = e and text:sub(e + 1) or text
    end
    if numeric then
      return tonumber(text:match("%-?%d+%.?%d*")) or -math.huge
    end
    return fold and text:lower() or text
  end
  for i, l in ipairs(list) do
    l.order = i
  end
  table.sort(
    list,
    function(x: Line, y: Line): boolean
      local kx, ky = key(x), key(y)
      if kx ~= ky then
        if kx is number and ky is number then
          if reverse then
            return kx > ky
          end
          return kx < ky
        end
        if reverse then
          return tostring(kx) > tostring(ky)
        end
        return tostring(kx) < tostring(ky)
      end
      return x.order < y.order
    end
  )
  for i, l in ipairs(list) do
    l.order = nil
    t.lines[a + i - 1] = l
  end
end

--- What a command of the buffer's own gets: the window, the buffer, its
--- text and cursor, the lines `a` to `b`, the bang, what follows the
--- name, and whether a range was typed.
local record ExLine
  win: Window
  buf: TextBuffer
  t: Text
  s: Cursor
  a: integer
  b: integer
  bang: boolean
  args: string
  ranged: boolean
end

--- A command of the buffer's own: false leaves the line to the command
--- of that name.
local type ExFn = function(c: ExLine): boolean

local ex: {string: ExFn} = {}

--- Run a line typed after `:` in a text buffer. Returns true when it was
--- the buffer's to run.
function M.exec(line: string): boolean
  local win, buf, t, s = here()
  if not win then
    return false
  end
  line = line:gsub("^[%s:]+", ""):gsub("%s+$", "")
  local a, b, rest, ranged = range(line, t, s)
  local name, bang, args = rest:match("^(%a*)(!?)%s*(.-)$")
  if not name then
    return false
  end
  if name == "" and bang == "" and args == "" and ranged then
    s.row = math.tointeger(util.clamp(b, 1, t:count()))
    s.col = first_nonblank(t, s.row)
    api.ui_redraw()
    return true
  end
  local fn = ex[name]
  if not fn then
    return false
  end
  local default_all = name == "sort"
  if not ranged then
    if default_all then
      a, b = 1, t:count()
    else
      a, b = s.row, s.row
    end
  end
  a, b = math.tointeger(util.clamp(a, 1, t:count())), math.tointeger(util.clamp(b, 1, t:count()))
  -- A command may leave the line to the command of that name (false).
  return fn(
    {win = win, buf = buf, t = t, s = s, a = a, b = b, bang = bang == "!", args = args, ranged = ranged}
  ) ~= false
end

local function edit_lines(fn: function(c: ExLine): string): ExFn
  return function(c: ExLine): boolean
    c.t:begin(c.s.row, c.s.col)
    local err = fn(c)
    c.t:finish()
    clamp(c.t, c.s)
    changed(c.buf)
    if err then
      paw.notify(err, "warn")
    end
  end
end

ex.s = edit_lines(
  function(c: ExLine): string
    local count, lines, err = substitute(c.t, c.a, c.b, c.args)
    if not count then
      return err
    end
    if count == 0 then
      return "pattern not found"
    end
    paw.notify(
      string.format("%d substitution%s on %d line%s", count, count == 1 and "" or "s", lines, lines == 1 and "" or "s")
    )
  end
)
ex.substitute = ex.s
ex.sort = edit_lines(function(c: ExLine): string sort_lines(c.t, c.a, c.b, (c.bang and "!" or "") .. c.args) end)
ex.sor = ex.sort
ex.d = edit_lines(
  function(c: ExLine): string
    keymap.setreg(yank_span(c.t, {kind = "line", r0 = c.a, r1 = c.b}, c.buf), c.args:match("^%S"))
    c.t:delete_lines(c.a, c.b)
    c.s.row = c.a
  end
)
ex.delete = ex.d
ex.y = function(c: ExLine): boolean
  keymap.setreg(yank_span(c.t, {kind = "line", r0 = c.a, r1 = c.b}, c.buf), c.args:match("^%S"), true)
end
ex.yank = ex.y
ex.m = edit_lines(
  function(c: ExLine): string
    local to = c.args:match("^%s*(%S+)")
    local dest: integer
    if to == "0" then
      dest = 0
    elseif to then
      dest = address(to, c.t, c.s)
    end
    if not dest then
      return "usage: m <line>: `:m 0` to the top, `:m $` to the end"
    end
    if dest >= c.a and dest < c.b then
      return "lines do not move into themselves"
    end
    local lines = c.t:delete_lines(c.a, c.b)
    if dest > c.b then
      dest = dest - #lines
    end
    c.t:insert_lines(dest + 1, lines)
    c.s.row = dest + #lines
  end
)
ex.move = ex.m
ex.normal = function(c: ExLine): boolean
  for r = c.a, c.b do
    c.s.row, c.s.col = r, 0
    keymap.normal(c.args)
    if ins then
      insert_finish()
    end
  end
end
ex.norm = ex.normal
-- `:w file`, `:e name` and the like are the commands', not the buffer's.
ex.w = function(c: ExLine): boolean
  if c.args ~= "" or c.ranged then
    return false
  end
  if c.buf.state.kind.scratch then
    paw.notify(c.buf.state.kind.scratch, "warn")
    return
  end
  M.write(c.buf, c.bang)
end
ex.write = ex.w
ex.e = function(c: ExLine): boolean
  if c.args ~= "" then
    return false
  end
  if c.bang or not c.t:modified() then
    M.reload(c.buf)
    paw.notify(c.buf.name .. " read again")
    return
  end
  paw.notify("the buffer has changes: `:e!` throws them away and reads it again, `:w` applies them", "warn")
end
ex.edit = ex.e
ex.wq = function(c: ExLine): boolean
  if c.buf.state.kind.scratch then
    return ex.w(c)
  end
  if not c.t:modified() then
    return false
  end
  paw.notify("the buffer has changes: `:w` applies them first", "warn")
end
ex.x = ex.wq
ex.q = function(c: ExLine): boolean
  if c.bang then
    M.reload(c.buf)
  end
  -- A scratch kind's changes are never written: they go with the window.
  if c.buf.state.kind.scratch or not c.t:modified() then
    return false
  end
  paw.notify("the buffer has changes: `:w` applies them, `:q!` closes the window without", "warn")
end
ex.quit = ex.q
ex.close = ex.q
ex.u = function(): boolean M.undo(false, 1) end
ex.undo = ex.u
ex.red = function(): boolean M.undo(true, 1) end
ex.redo = ex.red

-- Writing --------------------------------------------------------------------------------

--- The plan a buffer's changes make: `{ text, run }` steps, or nil and why
--- (and the line that does not read).
function M.plan(buf: TextBuffer): {contracts.PlanStep}, string, contracts.TextError
  M.sync(buf)
  local st = buf.state
  local ch = M.changes(buf)
  if #ch.errors > 0 then
    local e = ch.errors[1]
    return nil, string.format("line %d does not read: %s  (%s)", e.row, e.error, clip(e.text, 40)), e
  end
  local steps: {contracts.PlanStep}
  local err: string
  local ok, failed = pcall(function() steps, err = st.kind.plan(ch, ctx_of(buf)) end) as (boolean, string)
  if not ok then
    return nil, reason(failed)
  end
  if not steps then
    return nil, err
  end
  return steps
end

--- Apply steps as one undo step, then read the buffer again.
--- A step that fails takes back what the steps before it did, and the
--- buffer keeps its changes.
function M.apply(buf: TextBuffer, steps: {contracts.PlanStep}): boolean, string
  api.undo_label("Write " .. buf.name)
  local before = project_edits("edits")
  -- A step that changes something outside the project (a file) notes how
  -- to take it back in `state.undo`.
  local plan_state: contracts.PlanState = {made = {}, undo = {}}
  for _, s in ipairs(steps) do
    if s.run then
      local ok, err = pcall(s.run, plan_state) as (boolean, string)
      if not ok then
        for i = #plan_state.undo, 1, -1 do
          pcall(plan_state.undo[i])
        end
        if project_edits("edits") ~= before then
          api.undo_checkpoint()
          paw.undo()
        end
        buf.state.seen = project_edits("edits")
        return false, string.format("%s failed, and nothing was changed: %s", s.text, reason(err))
      end
    end
  end
  M.reload(buf)
  return true
end

-- The plan shown before writing, as oil.nvim shows it: a float that takes
-- y or Enter to apply, n, q or Esc to leave it.
local record Confirm is contracts.View
  scroll: integer
  steps: {contracts.PlanStep}
  shown: {contracts.PlanStep}
  buf: TextBuffer
  loose: boolean
end
local confirm: Confirm = {modal = true, focusable = true, window = false, scroll = 0, steps = {}}
paw.seats.fields(
  "textbuf.plan",
  confirm as {string: Data},
  {"scroll", "steps", "shown", "buf", "loose"},
  {scroll = 0, steps = {}, shown = {}} as {string: Data}
)

local FOOTER = "y or Enter: apply, as one undo step · n or Esc: back"
local verbs: {string: string} = {delete = "Error", remove = "Error", add = "Info", copy = "Info", new = "Info"}

function confirm:render(canvas: Buf, _: contracts.RenderContext)
  local lines = self.shown or {}
  local h = canvas.height - 1
  self.scroll = math.tointeger(util.clamp(self.scroll, 0, math.max(0, #lines - h)))
  for row = 0, h - 1 do
    local s = lines[row + 1 + self.scroll]
    if s then
      local verb = s.text:match("^(%a+)")
      canvas:text(1, row, util.fit(s.text, canvas.width - 2), verbs[verb or ""] or "Normal")
    end
  end
  canvas:fill(0, canvas.height - 1, canvas.width, 1, " ", "FloatFooter")
  canvas:text(1, canvas.height - 1, FOOTER, "FloatFooter")
end

--- Close the plan; from a graphical frontend's window, back to the buffer's.
local function close_plan()
  local to_window = confirm.loose
  confirm.loose = nil
  ui().close()
  if to_window and paw.canvas.open_views.textbuf then
    ui().focus("textbuf")
  end
end

function confirm:on_key(key: string): boolean
  if key == "y" or key == "<CR>" then
    local buf, steps, n = self.buf, self.steps, #self.shown
    close_plan()
    self.steps, self.shown, self.buf = {}, {}, nil
    if not (buf and layout.buffers[buf.id]) then
      return
    end
    local ok, err = M.apply(buf, steps)
    if ok then
      paw.notify(string.format("%s written: %d change%s, one undo step", buf.name, n, n == 1 and "" or "s"))
    else
      paw.notify(err, "error")
    end
  elseif key == "n" or key == "q" or key == "<Esc>" or key == "<C-c>" then
    self.steps, self.shown, self.buf = {}, {}, nil
    close_plan()
  elseif key == "j" or key == "<Down>" then
    self.scroll = self.scroll + 1
  elseif key == "k" or key == "<Up>" then
    self.scroll = self.scroll - 1
  end
  api.ui_redraw()
end

ui().view("textbuf.plan", confirm)

--- `:w` in a text buffer: the plan, to confirm. With `force`, also when the
--- project changed after paw read the buffer.
function M.write(buf: TextBuffer, force: boolean)
  local st = buf.state
  M.sync(buf)
  if not st.text:modified() then
    -- Nothing to apply: `:w` saves the project, as it does anywhere else.
    commands.run("write", {})
    return
  end
  if st.conflict and not force then
    return paw.notify(
      buf.name
        .. " changed in the project since it was read: `:e!` reads it again (your changes go), `:w!` applies them over it",
      "warn"
    )
  end
  local steps, err, e = M.plan(buf)
  if not steps then
    if e then
      local win = M.current()
      if win then
        state(win).row, state(win).col = e.row, 0
      end
    end
    return paw.notify(err, "error")
  end
  -- Steps marked `quiet` are applied but not listed: they carry out what
  -- the listed ones say.
  local shown: {contracts.PlanStep} = {}
  for _, s in ipairs(steps) do
    if not s.quiet then
      shown[#shown + 1] = s
    end
  end
  if #shown == 0 then
    M.reload(buf)
    return paw.notify("nothing to change: " .. buf.name .. " read again")
  end
  confirm.steps, confirm.shown, confirm.buf, confirm.scroll = steps, shown, buf, 0
  local w = width(FOOTER) + 4
  for _, s in ipairs(shown) do
    w = math.max(w, width(s.text) + 4)
  end
  local win = M.current()
  ui().open(
    "textbuf.plan",
    {
      title = "Write " .. buf.name .. ": " .. #shown .. " change" .. (#shown == 1 and "" or "s"),
      width = math.min(w, 110),
      height = math.min(#shown + 3, 30),
    }
  )
  -- Typed in a graphical frontend's window, the plan opens in one too.
  if win and win == loose and paw.canvas.open_views.textbuf then
    confirm.loose = true
    paw.canvas.open_view("textbuf.plan")
  end
end

-- Drawing -----------------------------------------------------------------------------------

local GUTTER = 5

--- The columns left of the text: the line numbers and signs, if the kind has them.
local function gutter(buf: TextBuffer): integer
  return buf.state.kind and buf.state.kind.gutter == false and 0 or GUTTER
end

--- What a line is, for the gutter: its place when read, `+` new or a
--- copy, `~` changed, `!` not readable, and what is wrong with it.
local record Sign
  sign: string
  number: string
  style: string
  error: string
end

local function signs(buf: TextBuffer): {Sign}
  local st = buf.state
  local out: {Sign} = {}
  local seen: {Id: boolean} = {}
  for row, line in ipairs(st.text.lines) do
    local blank = line.text:match("^%s*$") ~= nil
    local fields: Fields
    local err: string
    if not blank then
      fields, err = parse(buf, line.text)
    end
    local sign, number, style = " ", "", "Dim"
    if line.id ~= nil and st.order[line.id] and not seen[line.id] then
      seen[line.id] = true
      number = tostring(st.order[line.id])
      local base = st.text.base[st.order[line.id]]
      if base and base.text ~= line.text then
        sign, style = "~", "Warn"
      end
    elseif not blank then
      sign, style = "+", "Info"
      if line.id ~= nil and st.order[line.id] then
        number = tostring(st.order[line.id])
      end
    end
    if not blank and not fields then
      sign, style = "!", "Error"
    end
    out[row] = {
      sign = sign, number = number, style = style, error = not blank and not fields and (err or "does not read") or nil
    }
  end
  return out
end

--- Styles for the parts of a line: keywords dim, the first cell bright.
local function paint_line(
  canvas: Buf, x: integer, y: integer, text: string, kind: contracts.TextKind<contracts.TextItem, Fields>, maxw: integer
)
  canvas:text(x, y, clip(text, maxw), "Normal")
  local kw = kind.keywords or {}
  for i, cell in ipairs(M.cells(text)) do
    if cell.col < maxw then
      local word = cell.text:match("^(%S+)")
      local style = kind.style and kind.style(cell.text, i)
      if style then
        canvas:text(x + cell.col, y, clip(cell.text, maxw - cell.col), style)
      elseif i == 1 then
        canvas:text(x + cell.col, y, clip(cell.text, maxw - cell.col), kind.first_style or "PartName")
      elseif word and kw[word] then
        canvas:text(x + cell.col, y, clip(word, maxw - cell.col), "Dim")
      end
    end
  end
end

local function render(win: Window, canvas: Buf, ctx?: contracts.RenderContext)
  local buf = ctx.buf as TextBuffer
  local st = buf and buf.state
  if not (st and st.text) then
    ui().titlebar(canvas, {name = buf and buf.name or "text", focused = ctx.focused})
    canvas:text(2, 2, "nothing to show", "Empty")
    return
  end
  M.sync(buf)
  local t, s = st.text, state(win)
  clamp(t, s, ins and ins.win == win.id)
  local modified = t:modified()
  local title = st.kind.title and st.kind.title(ctx_of(buf)) or buf.name
  local right = (modified and "[+] " or "") .. t:count() .. " line" .. (t:count() == 1 and "" or "s")
  if st.conflict then
    right = "changed elsewhere · " .. right
  end
  ui().titlebar(
    canvas, {name = buf.name, context = title ~= buf.name and title or nil, focused = ctx.focused, right = right}
  )
  local W, H = canvas.width, canvas.height
  local rows = H - 2
  if rows < 1 then
    return
  end
  s.height = rows
  if s.row < s.top then
    s.top = s.row
  elseif s.row >= s.top + rows then
    s.top = s.row - rows + 1
  end
  s.top = math.max(1, s.top)
  local gs: {Sign} = st.text.readonly and {} or signs(buf)
  local G = gutter(buf)
  local tw = W - G
  local mode = ctx.focused and keymap.mode or "n"
  local sel = ctx.focused and keymap.selection()
  local sp = sel and sel.view == "textbuf" and span(sel, nil, t)
  canvas:fill(0, 1, W, rows, " ", "Normal")
  for i = 0, rows - 1 do
    local row = s.top + i
    local y = 1 + i
    if row > t:count() then
      canvas:text(0, y, "~", "Faint")
    else
      local g = gs[row]
      if g and G > 0 then
        canvas:text(0, y, string.format("%3s", g.number), "PartIndex")
        canvas:text(3, y, g.sign, g.style)
      end
      local text = t:line(row)
      if st.kind.paint then
        st.kind.paint(canvas, G, y, text, st.kind, tw, row, buf as LayoutBuffer)
      else
        paint_line(canvas, G, y, text, st.kind, tw)
      end
      if sp and row >= sp.r0 and row <= sp.r1 then
        local a, b: integer, integer
        if sp.kind == "line" then
          a, b = 0, math.max(1, width(text))
        elseif sp.kind == "block" then
          a, b = sp.c0, sp.c1
        else
          a = row == sp.r0 and sp.c0 or 0
          b = row == sp.r1 and sp.c1 or width(text) + 1
        end
        a, b = math.max(0, a), math.min(tw, b)
        if b > a then
          canvas:fill(G + a, y, b - a, 1, nil, "Visual")
        end
      end
      if row == s.row and ctx.focused then
        local cx = s.col
        if cx < tw then
          local ch = char_at(text, cx) or " "
          canvas:text(G + cx, y, ch, mode == "i" and "InsertCursor" or (mode == "x" and "CursorVisual" or "Cursor"))
        end
      end
    end
  end
  -- The line along the bottom: what is wrong with the line under the
  -- cursor, else what to do.
  local g = gs[s.row]
  canvas:fill(0, H - 1, W, 1, " ", "Ruler")
  local text, style: string, string
  if st.error then
    text, style = st.error, "Error"
  elseif g and g.error then
    text, style = "line " .. s.row .. ": " .. g.error, "Error"
  elseif st.conflict then
    text, style =
      "the project changed since this was read: `:e!` reads it again, `:w!` applies your changes over it", "Warn"
  elseif mode == "i" then
    text, style = "Esc leaves insert mode · fields are two spaces apart", "Dim"
  elseif modified and not st.kind.scratch then
    text, style = "`:w` shows what will change and applies it · `:e!` throws the changes away · `u` undoes", "Dim"
  else
    text, style =
      st.kind.hint or "edit the lines and `:w` · `dd` deletes, `yyp` copies, `cw` renames, Ctrl-a adds 1", "Dim"
  end
  canvas:text(1, H - 1, util.fit(text, W - 2), style)
end

-- The buffer type ------------------------------------------------------------------------------

--- The buffer type of text buffers.
local record Def is contracts.Buftype
end

local def: Def = layout.buftype(
  "textbuf",
  {
    claims = function(name: string): boolean return kind_of(name) ~= nil end,
    bufname = function(target: string): string return target end,
    title = function(lbuf: LayoutBuffer): string
      local buf = lbuf as TextBuffer
      local st = buf.state
      if st and st.kind and st.kind.title then
        local text: string
        local ok = pcall(function() text = st.kind.title(ctx_of(buf)) end)
        if ok and text then
          return text
        end
      end
      return buf.target
    end,
    create = function(target: string, lbuf: LayoutBuffer): {string: string | number | boolean}
      local buf = lbuf as TextBuffer
      local kind, args = kind_of(target)
      local st: State = {kind = kind, args = args, text = M.text({}), fields = {}, order = {}, parsed = {}}
      local readonly = kind and kind.readonly as string | boolean
      if readonly then
        st.text.readonly = readonly is string and readonly or "this buffer cannot be changed"
      end
      buf.state = st
      if kind then
        M.reload(buf)
      end
      return st as {string: string | number | boolean}
    end,
    render = render,
    window = function(): Window return loose end,
  } as Def
)
local view = ui().views:get("textbuf")
view.title = "Text"

-- What a kind adds: its keys first, then `K` and its part of the status line.
local function kind_here(): contracts.TextKind<contracts.TextItem, Fields>, TextBuffer
  local _, buf = here()
  local kind = buf and buf.state.kind
  return kind, buf
end

view.subscope = function(_: contracts.View): string
  local kind = kind_here()
  return kind and "textbuf." .. kind.name
end

view.describe = function(_: contracts.View): contracts.Description
  local kind, buf = kind_here()
  if kind and kind.describe then
    return kind.describe(ctx_of(buf))
  end
end

view.status = function(_: contracts.View, line?: contracts.StatusContext): string | {contracts.Piece}
  local kind, buf = kind_here()
  if kind and kind.status then
    return kind.status(ctx_of(buf), line)
  end
end

local grid: contracts.Grid = {
  get = function(): number, number
    local win, _, t, s = here()
    if not win then
      return 0, 0
    end
    -- A motion after an operator may end past the last character.
    clamp(t, s, true)
    return s.row, s.row * BIG + s.col
  end,
  set = function(row: number, col: number)
    local win, _, t, s = here()
    if not win then
      return
    end
    s.row = math.tointeger(util.clamp(math.floor(row), 1, t:count()))
    s.col = math.floor(col % BIG)
    clamp(t, s)
    s.want = s.col
    api.ui_redraw()
  end,
  step = function(): number return 1 end,
  -- A place for marks and jumps names its buffer too, so that `Ctrl-o`
  -- goes back across buffers, as Vim's jump list does.
  mark = function(): contracts.GridMark
    local win, buf, _, s = here()
    if not win then
      return {0, 0}
    end
    return {s.row, s.row * BIG + s.col, buf.name}
  end,
}
grid.jump = function(pos: contracts.GridMark)
  local win, buf = here()
  if not win then
    return
  end
  local name = pos[3]
  if name is string and name ~= buf.name and kind_of(name) then
    layout.show_in(win, "textbuf", layout.buf_create("textbuf", name).id)
  end
  grid.set(pos[1] as number, pos[2] as number)
end
grid.search = function(text: string): {contracts.GridHit}
  local _, _, t = here()
  local out: {contracts.GridHit} = {}
  if not t then
    return out
  end
  local needle = text:lower()
  for r = 1, t:count() do
    local found = t:line(r):lower():find(needle, 1, true)
    if found then
      out[#out + 1] = {row = r, col = r * BIG + width(t:line(r):sub(1, found - 1))}
    end
  end
  return out
end
view.grid = grid

def.on_mouse = function(win: Window, e: contracts.MouseEvent): boolean
  local buf = layout.buf_of(win) as TextBuffer
  if not (buf and buf.state.text) then
    return
  end
  local t, s = buf.state.text, state(win)
  local step_ = paw.mouse.wheel(e)
  if step_ then
    s.top = math.max(1, s.top + step_ * 3)
    s.row = math.tointeger(util.clamp(s.row, s.top, s.top + (s.height or 10) - 1))
    clamp(t, s)
    api.ui_redraw()
    return
  end
  if e.kind ~= "down" or e.button ~= "left" then
    return
  end
  if layout.current() ~= win and win ~= loose then
    layout.enter(win)
  end
  local row = s.top + math.floor(e.y) - 1
  if e.y >= 1 and row <= t:count() then
    s.row, s.col = row, math.max(0, math.floor(e.x) - gutter(buf))
    clamp(t, s)
    s.want = s.col
    -- A double click opens what the line stands for, as Enter does.
    if e.double and buf.state.kind.open then
      buf.state.kind.open(ctx_of(buf), t.lines[s.row] as contracts.TextLine<Fields>, t:line(s.row))
    end
  end
  api.ui_redraw()
end

-- Opening ---------------------------------------------------------------------------------

--- Show a text buffer: in this window (`opts.here`), split below (beside
--- with `opts.vertical`), or in a graphical frontend's window of its own
--- (`opts.window`). Returns the window.
function M.open(name: string, opts?: OpenOptions): Window, string
  opts = opts or {}
  if not kind_of(name) then
    return nil, "no text buffer `" .. tostring(name) .. "`"
  end
  local buf = layout.buf_create("textbuf", name)
  local win: Window
  if opts.window then
    loose = layout.leaf("textbuf", {buf = buf.id})
    win = loose
    paw.canvas.open_view("textbuf", {title = buf.name})
  elseif opts.here then
    win = layout.show_in(layout.current(), "textbuf", buf.id)
  else
    for _, w in ipairs(layout.windows()) do
      if w.view == "textbuf" and w.buf == buf.id then
        win = w
      end
    end
    if win then
      layout.enter(win)
    else
      win = layout.split({view = "textbuf", buf = buf.id, vertical = opts.vertical})
      if not win then
        win = layout.show_in(layout.current(), "textbuf", buf.id)
      end
    end
  end
  api.ui_redraw()
  return win
end

--- The buffer shown in the keyboard's window, if it is a text buffer.
M.buf = current_buf

-- Keys -----------------------------------------------------------------------------------------

local map = keymap.set
local nx: {KeymapModule.Mode} = {"n", "x"}
local function tmap(lhs: string, rhs: contracts.KeyFn, desc: string, opts?: MapOptions)
  local o: MapOptions = opts and util.merge(opts as {string: Data}, {}) as MapOptions or {}
  o.view, o.desc = "textbuf", desc
  map(lhs, rhs, o)
end
local function motion(): MapOptions
  return {motion = true}
end
local function linewise(): MapOptions
  return {motion = true, linewise = true}
end
local function with_count(fn: function(n: integer, ctx: KeyContext)): contracts.KeyFn
  return function(ctx?: KeyContext) fn(ctx.count or 1, ctx) end
end

tmap("h", motions.left, "Left", motion())
tmap("<Left>", motions.left, "Left", motion())
tmap("l", motions.right, "Right", motion())
tmap("<Right>", motions.right, "Right", motion())
tmap("j", motions.down, "Down a line", linewise())
tmap("<Down>", motions.down, "Down a line", linewise())
tmap("k", motions.up, "Up a line", linewise())
tmap("<Up>", motions.up, "Up a line", linewise())
tmap("gg", motions.first, "First line, or line N", {motion = true, linewise = true, jump = true})
tmap("G", motions.last, "Last line, or line N", {motion = true, linewise = true, jump = true})
tmap("0", motions.home, "Start of the line", motion())
tmap("<Home>", motions.home, "Start of the line", motion())
tmap("^", motions.nonblank, "First character of the line", motion())
tmap("$", motions.line_end, "End of the line", motion())
tmap("<End>", motions.line_end, "End of the line", motion())
tmap("w", motions.w, "Next word", motion())
tmap("W", motions.W, "Next WORD", motion())
tmap("b", motions.b, "Previous word", motion())
tmap("B", motions.B, "Previous WORD", motion())
tmap("e", motions.e, "End of the word", motion())
tmap("E", motions.E, "End of the WORD", motion())
tmap("f", motions.f, "To the next character typed", {motion = true, char = true})
tmap("F", motions.F, "To the previous character typed", {motion = true, char = true})
tmap("t", motions.t, "Till the next character typed", {motion = true, char = true})
tmap("T", motions.T, "Till the previous character typed", {motion = true, char = true})
tmap(";", motions[";"], "The last f, t, F or T again", motion())
tmap(",", motions[","], "The last f, t, F or T, the other way", motion())
tmap("<C-d>", motions.half_down, "Down half a window", linewise())
tmap("<C-u>", motions.half_up, "Up half a window", linewise())

local function op(lhs: string, fn: Operator, desc: string)
  map(lhs, nil, {view = "textbuf", mode = nx, desc = desc, operator = fn})
end
op("d", M.ops.delete, "Delete")
op("y", M.ops.yank, "Yank")
op("c", M.ops.change, "Change")
op("gu", M.ops.lower, "Make lowercase")
op("gU", M.ops.upper, "Make uppercase")
op("g~", M.ops.swapcase, "Swap case")
local function vop(lhs: string, fn: Operator, desc: string)
  map(lhs, nil, {view = "textbuf", mode = "x", desc = desc, operator = fn})
end
vop("x", M.ops.delete, "Delete the selection")
vop("u", M.ops.lower, "Make the selection lowercase")
vop("U", M.ops.upper, "Make the selection uppercase")
vop("~", M.ops.swapcase, "Swap the selection's case")
vop("<C-a>", M.ops.increment(1), "Add 1 to the numbers selected, or the count")
vop("<C-x>", M.ops.increment(-1), "Take 1 from the numbers selected, or the count")
vop(
  "J",
  function(region: Region)
    local _, _, t, s = here()
    if t then
      s.row = math.tointeger(region.r0)
    end
    M.join({count = math.tointeger(region.r1 - region.r0 + 1)})
  end,
  "Join the lines selected"
)
-- Visual block: `I` and `A` type on every line of the block.
local function block_insert(append: boolean): Operator
  return function(region: Region)
    local win, _, t, s = here()
    if not win then
      return
    end
    local sp = span(region, nil, t)
    if sp.kind ~= "block" then
      s.row, s.col =
        sp.r0, append and (sp.kind == "line" and t:len(sp.r1) or sp.c1) or (sp.kind == "line" and 0 or sp.c0)
      return M.insert("i")
    end
    local col = append and sp.c1 or sp.c0
    s.row, s.col = sp.r0, math.min(col, t:len(sp.r0))
    if append and t:len(sp.r0) < col then
      t:set(sp.r0, t:line(sp.r0) .. string.rep(" ", col - t:len(sp.r0)))
      s.col = col
    end
    M.insert("i", {block = {r0 = sp.r0, r1 = sp.r1, col = col, before = t:line(sp.r0), append = append}})
  end
end
vop("I", block_insert(false), "Insert before the block, on every line")
vop("A", block_insert(true), "Append after the block, on every line")
map(
  "r",
  function(ctx?: KeyContext)
    local region = keymap.selection()
    local ch = ctx.char
    keymap.set_mode("n")
    if not (region and ch) or ch:match("^<.+>$") then
      return
    end
    on_span(
      function(t: Text, sp: Span, _: KeyContext, s: Cursor): boolean
        for r = sp.r0, sp.r1 do
          if t.lines[r] then
            local a = (sp.kind == "line" or (sp.kind == "char" and r > sp.r0)) and 0 or sp.c0
            local b = (sp.kind == "line" or (sp.kind == "char" and r < sp.r1)) and t:len(r) or sp.c1
            b = math.min(b, t:len(r))
            if b > a then
              t:delete_span(r, a, r, b)
              t:insert(r, a, string.rep(ch == " " and " " or ch, b - a))
            end
          end
        end
        to_start(t, s, sp)
      end
    )(region, ctx)
  end,
  {view = "textbuf", mode = "x", char = true, desc = "Replace every character selected with the one typed"}
)

local function object(lhs: string, fn: Object, desc: string)
  map(lhs, nil, {view = "textbuf", mode = {"o", "x"}, desc = desc, object = fn})
end
object("iw", word_object(false, false), "The word")
object("aw", word_object(true, false), "The word and the spaces after it")
object("iW", word_object(false, true), "The WORD")
object("aW", word_object(true, true), "The WORD and the spaces after it")
object("if", field_object(false), "The field's value (after its keyword)")
object("af", field_object(true), "The whole field")

local function insert_at(how: string): contracts.KeyFn
  return function() M.insert(how) end
end
local function normal(keys: function(ctx: KeyContext): string): contracts.KeyFn
  return function(ctx?: KeyContext) keymap.normal(keys(ctx)) end
end
tmap("i", insert_at("i"), "Insert before the cursor")
tmap("a", insert_at("a"), "Append after the cursor")
tmap("I", insert_at("I"), "Insert at the start of the line")
tmap("A", insert_at("A"), "Append at the end of the line")
tmap("o", insert_at("o"), "A new line below")
tmap("O", insert_at("O"), "A new line above")
tmap(
  "x",
  normal(function(ctx: KeyContext): string return (ctx.count or 1) .. "dl" end),
  "Delete the character under the cursor"
)
tmap(
  "<Del>",
  normal(function(ctx: KeyContext): string return (ctx.count or 1) .. "dl" end),
  "Delete the character under the cursor"
)
tmap(
  "X",
  normal(function(ctx: KeyContext): string return (ctx.count or 1) .. "dh" end),
  "Delete the character before the cursor"
)
tmap("D", normal(function(): string return "d$" end), "Delete to the end of the line")
tmap("C", normal(function(): string return "c$" end), "Change to the end of the line")
tmap(
  "s",
  normal(function(ctx: KeyContext): string return (ctx.count or 1) .. "cl" end),
  "Change the character under the cursor"
)
tmap("S", normal(function(): string return "cc" end), "Change the line")
tmap("Y", normal(function(ctx: KeyContext): string return (ctx.count or 1) .. "yy" end), "Yank the line")
tmap(
  "p", function(ctx?: KeyContext) M.put(false, ctx.register, ctx.count) end, "Put after the cursor, or below the line"
)
tmap(
  "P", function(ctx?: KeyContext) M.put(true, ctx.register, ctx.count) end, "Put before the cursor, or above the line"
)
tmap("r", M.replace, "Replace the character under the cursor with the one typed", {char = true})
tmap("~", M.tilde, "Swap the case of the character under the cursor")
tmap("J", M.join, "Join the line below to this one")
tmap("u", function(ctx?: KeyContext) M.undo(false, ctx.count) end, "Undo a change to the text", {repeatable = false})
tmap("<C-r>", function(ctx?: KeyContext) M.undo(true, ctx.count) end, "Redo a change to the text", {repeatable = false})
tmap(
  "<C-a>",
  with_count(function(n: integer) M.increment(n) end),
  "Add 1 to the number under or after the cursor, or the count"
)
tmap(
  "<C-x>",
  with_count(function(n: integer) M.increment(-n) end),
  "Take 1 from the number under or after the cursor, or the count"
)
tmap(
  "<CR>",
  function()
    local win, buf, t, s = here()
    if not win then
      return
    end
    local open = buf.state.kind.open
    if not open then
      return paw.notify("nothing to open from this line", "warn")
    end
    open(ctx_of(buf), t.lines[s.row] as contracts.TextLine<Fields>, t:line(s.row))
  end,
  "Open what the line stands for: a part's devices",
  {repeatable = false}
)
tmap(
  "-",
  function()
    local win, buf = here()
    if not win then
      return
    end
    local up = buf.state.kind.parent and buf.state.kind.parent(ctx_of(buf))
    if not up then
      return paw.notify("nothing above this buffer", "warn")
    end
    M.open(up, {here = true})
  end,
  "The buffer this one belongs to: paw://parts from a part's devices",
  {repeatable = false}
)
tmap(
  "<C-w>f",
  function()
    local _, buf = here()
    if buf then
      M.open(buf.name, {window = true})
    end
  end,
  "Show the buffer in a window of its own, in the graphical frontend",
  {repeatable = false}
)

-- `:` here takes the buffer's own lines first; from a selection it starts
-- with its lines, as Vim's does.
local function cmdline(from_visual: boolean): contracts.KeyFn
  return function()
    local text = ""
    if from_visual then
      keymap.set_mode("n")
      text = "'<,'>"
    end
    ui().input(
      {
        prompt = ":",
        history = "cmdline",
        text = text,
        complete = function(line: string): {commands.Entry} return commands.complete(line) end,
      },
      function(line: string)
        if line:match("%S") then
          paw.state.last_cmdline = line
          commands.used(line:match("^%s*:?(%S+)"))
        end
        commands.exec(line)
      end
    )
  end
end
tmap(":", cmdline(false), "Type a command: the buffer's own (`:w`, `:s`, `:sort`, `:e!`) or any", {repeatable = false})
map(
  ":", cmdline(true), {view = "textbuf", mode = "x", desc = "Type a command on the lines selected", repeatable = false}
)

local text_keys: KeyList = {
  {"c", "change"},
  {"d", "delete"},
  {"y", "yank"},
  {"p", "put"},
  {"<C-a>", "+1"},
  {":", "command, :w applies"},
  {"<CR>", "open"},
  {"?", "keys"},
}
-- A kind with keys of its own (`keys` in its spec, as the files buffers
-- have) shows those.
ui().keybar.set(
  "textbuf",
  "n",
  function(): KeyList
    local buf = M.buf()
    local kind = buf and buf.state and buf.state.kind
    return kind and kind.keys or text_keys
  end
)
ui().keybar.set("textbuf", "i", {{"<Esc>", "normal"}})
ui().keybar.set(
  "textbuf", "x", {{"d", "delete"}, {"y", "yank"}, {"c", "change"}, {"<C-a>", "+1"}, {"I", "insert"}, {":", "on lines"}}
)

-- Commands -------------------------------------------------------------------------------------

-- Lines typed after `:` in a text buffer are its own first.
table.insert(commands.line_handlers, function(line: string): boolean return M.exec(line) end)

-- By name too, for completion and scripts; typed after `:` in a text buffer
-- these lines are taken before they get here.
commands.define(
  "sort",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    local args = tostring(ctx.args[1] or "")
    if not M.exec("sort" .. (args ~= "" and " " .. args or "")) then
      paw.notify("`:sort` sorts the lines of a text buffer: `:e paw://parts` opens one", "warn")
    end
  end,
  {
    desc = "Sort the lines of a text buffer: `sort`, `sort!` the other way, `sort n` by number, `sort i` ignoring case",
    raw = true,
  }
)

commands.define(
  "textbuf.open",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    local name = ctx.args[1] and tostring(ctx.args[1]) or "paw://parts"
    if not name:find("://") then
      name = "paw://" .. name
    end
    local opts: {string: boolean} = {}
    for i = 2, #ctx.args do
      opts[tostring(ctx.args[i])] = true
    end
    local win, err = M.open(name, opts as OpenOptions)
    if not win then
      paw.notify(err, "warn")
    end
  end,
  {
    desc = "Edit a listing as text: `textbuf.open parts`, `sends`, `markers`, `part/2/devices`; `vertical`, `here` or `window` says where",
    complete = function(_: string, info: contracts.CompleteInfo): {string | contracts.CompleteCandidate}
      if info.index > 1 then
        return {"vertical", "here", "window"}
      end
      local out: {string} = {}
      for name in pairs(M.kinds:entries()) do
        out[#out + 1] = "paw://" .. name
      end
      out[#out + 1] = "paw://part/1/devices"
      table.sort(out)
      return out
    end,
  }
)
commands.define(
  "textbuf.window",
  function(): contracts.CommandResult
    local _, buf = here()
    if not buf then
      paw.notify("no text buffer here: `:e paw://parts` opens one", "warn")
      return
    end
    M.open(buf.name, {window = true})
  end,
  {desc = "Show this text buffer in a window of its own, in the graphical frontend"}
)

-- The frontends' menus.
paw.frontend.act.open_textbuf = function(name: string, window: boolean): Window, string
  return M.open(name, {window = window})
end

return M
