-- The Markdown the manual is written in, made into lines of text for the
-- help buffers (paw/help.tl): headings, paragraphs, lists, tables, fenced
-- code, quotes, rules, and inside a line `code`, [links](target), **bold**
-- and *italic*. Nothing else of Markdown is used in the docs, so nothing
-- else is read; HTML comments are dropped, except `<!-- tags: a b -->`,
-- which names the place it stands as help tags.
--
--   local doc = paw.markdown.render(paw.markdown.parse(text), { width = 78 })
--   doc.lines[3]   --> { text = "...", spans = { { c0, c1, style } }, links = { { c0, c1, target } }, codes = { ... } }
--
-- Columns are counted in characters from 0, as the text buffers count them.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.

local record M
  --- A piece of a line's text with one look: its style (a highlight
  --- group), the target of the link it is in, whether it is code, and its
  --- width once measured.
  record Run
    text: string
    style: string
    link: string
    code: boolean
    w: integer
  end

  --- What a block is.
  enum BlockType
    "heading"
    "para"
    "item"
    "table"
    "code"
    "quote"
    "rule"
    "blank"
    "tags"
  end

  --- A block of a document: a `heading` (level, text), a `para` (text,
  --- depth), an `item` of a list (depth, marker, text), a `table` (rows of
  --- cells, the first the header; depth), `code` (lines, depth), a `quote`
  --- (text), a `rule`, a `blank` or `tags` (names). `tag` is free for the
  --- caller (paw/help.tl names its headings with it).
  record Block
    type: BlockType
    level: integer
    text: string
    depth: integer
    marker: string
    rows: {{string}}
    lines: {string}
    names: {string}
    tag: string
  end

  --- Columns `c0` to `c1` of a line in a style.
  type Span = {integer, integer, string}
  --- Columns `c0` to `c1` of a line that link to a target.
  type Link = {integer, integer, string}
  --- Columns `c0` to `c1` of a line that are code, its text, and whether
  --- it is `first`: in a table's first column, or at the start of a list
  --- item, where a key or command is named before it is described.
  type Code = {integer, integer, string, boolean}

  --- A rendered line: its text, its width, and its styles, links and code.
  record Line
    text: string
    w: integer
    spans: {Span}
    links: {Link}
    codes: {Code}
  end

  --- What an anchor marks.
  enum AnchorKind
    "heading"
    "tags"
    "code"
    "lead"
  end

  --- A place in the rendered lines that can be named: a heading (level,
  --- text), help tags (names), code (col, text, first), or the bold words
  --- at the start of a paragraph (`lead`: text).
  record Anchor
    row: integer
    kind: AnchorKind
    col: integer
    level: integer
    text: string
    names: {string}
    first: boolean
  end

  --- What `render` takes: the width of the lines (78 by default), and the
  --- tag to show at the right of a heading.
  record RenderOptions
    width: integer
    heading_tag: function(block: Block): string
    --- Called before each block: where a long render may stop for a
    --- while (help made at idle, paw/help.tl).
    pause: function()
  end

  width: function(s: string): integer
  inline: function(s: string, style?: string, link?: string, out?: {Run}): {Run}

  --- What `render` gives.
  record Document
    lines: {Line}
    anchors: {Anchor}
  end
end

local type Run = M.Run
local type Block = M.Block
local type Line = M.Line
local type Anchor = M.Anchor

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

--- How many cells a string takes.
local function width(s: string): integer
  if not s:find("[\128-\255]") then return #s end
  local _, n = s:gsub("[^\128-\191]", "")
  return n
end
M.width = width

--- The first `n` characters of `s`, and the rest.
local function cut(s: string, n: integer): string, string
  local count, at = 0, #s + 1
  for pos in s:gmatch("()" .. CHAR) do
    if count == n then
      at = pos as integer
      break
    end
    count = count + 1
  end
  return s:sub(1, at - 1), s:sub(at)
end

local function trim(s: string): string return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Inline -----------------------------------------------------------------------
--
-- A line's text becomes runs: `{ text, style?, link?, code? }`.

local inline: function(s: string, style?: string, link?: string, out?: {Run}): {Run}

--- Where the closing `delim` of an emphasis starting at `from` is, not
--- inside code.
local function closing(s: string, from: integer, delim: string): integer
  local i = from
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" then
      i = i + 2
    elseif c == "`" then
      local ticks = s:match("^`+", i)
      local close = s:find(ticks, i + #ticks, true)
      i = close and close + #ticks or i + #ticks
    elseif s:sub(i, i + #delim - 1) == delim and s:sub(i - 1, i - 1) ~= " " then
      -- `_` closes only at the end of a word, so that snake_case stays.
      if delim:sub(1, 1) ~= "_" or not s:sub(i + #delim, i + #delim):match("[%w]") then return i end
      i = i + 1
    else
      i = i + 1
    end
  end
end

--- The runs of a line of Markdown, each with the style and link given.
inline = function(s: string, style?: string, link?: string, out?: {Run}): {Run}
  out = out or {}
  local buf: {string} = {}
  local function flush()
    if #buf > 0 then
      out[#out + 1] = { text = table.concat(buf), style = style, link = link }
      buf = {}
    end
  end
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" and s:match("^\\[%p]", i) then
      buf[#buf + 1] = s:sub(i + 1, i + 1)
      i = i + 2
    elseif c == "`" then
      local ticks = s:match("^`+", i)
      local close = s:find(ticks, i + #ticks, true)
      if close then
        flush()
        local code = s:sub(i + #ticks, close - 1)
        if code:match("^ .* $") and code:match("%S") then code = code:sub(2, -2) end
        out[#out + 1] = { text = code, style = "HelpCode", link = link, code = true }
        i = close + #ticks
      else
        buf[#buf + 1] = ticks
        i = i + #ticks
      end
    elseif c == "!" and s:match("^!%[[^%]]*%]%([^)]*%)", i) then
      local alt, after = s:match("^!%[([^%]]*)%]%([^)]*%)()", i)
      flush()
      out[#out + 1] = { text = "[picture: " .. alt .. "]", style = "HelpDim" }
      i = after
    elseif c == "[" and s:match("^%[.-%]%(", i) then
      -- The link's text may hold code with brackets in it; its target ends at
      -- the first closing parenthesis.
      local depth, j = 0, i
      while j <= #s do
        local d = s:sub(j, j)
        if d == "`" then
          local close = s:find("`", j + 1, true)
          j = close or j
        elseif d == "[" then
          depth = depth + 1
        elseif d == "]" then
          depth = depth - 1
          if depth == 0 then break end
        end
        j = j + 1
      end
      local target, after = s:match("^%(([^)]*)%)()", j + 1)
      if depth == 0 and target then
        flush()
        inline(s:sub(i + 1, j - 1), style == nil and "HelpLink" or style, trim(target), out)
        i = after
      else
        buf[#buf + 1] = c
        i = i + 1
      end
    elseif c == "<" and s:match("^<https?://[^>%s]+>", i) then
      local url = s:match("^<([^>]+)>", i)
      flush()
      out[#out + 1] = { text = url, style = "HelpLink", link = url }
      i = i + #url + 2
    elseif (c == "*" or c == "_") and not (c == "_" and s:sub(i - 1, i - 1):match("[%w]")) then
      local delim = s:sub(i + 1, i + 1) == c and c .. c or c
      local close = s:sub(i + #delim, i + #delim):match("%S") and closing(s, i + #delim, delim)
      if close then
        flush()
        inline(s:sub(i + #delim, close - 1), #delim == 2 and "HelpBold" or "HelpItalic", link, out)
        i = close + #delim
      else
        buf[#buf + 1] = c
        i = i + 1
      end
    else
      -- Plain text, up to the next character that may start a mark.
      local stop = s:find("[\\`!%[<%*_]", i + 1) or #s + 1
      buf[#buf + 1] = s:sub(i, stop - 1)
      i = stop
    end
  end
  flush()
  return out
end
M.inline = inline

--- The text of runs without their marks: a heading as it reads.
function M.plain(s: string): string
  local out: {string} = {}
  for _, run in ipairs(inline(s)) do out[#out + 1] = run.text end
  return table.concat(out)
end

-- Blocks ------------------------------------------------------------------------
--
-- A document is a list of blocks: `heading` (level, text), `para` (text),
-- `item` (depth, marker, text), `table` (rows of cells, the first the
-- header), `code` (lines, depth), `quote` (text), `rule`, `blank`, `tags`
-- (names).

--- The cells of a table's row: split at `|` not in code nor escaped.
local function cells(line: string): {string}
  line = trim(line):gsub("^|", ""):gsub("|$", "")
  -- `ticks`: the run of backticks the code being read was opened with.
  local out, cur: {string}, {string} = {}, {}
  local i = 1
  local ticks: string
  while i <= #line do
    local c = line:sub(i, i)
    if c == "\\" and line:sub(i + 1, i + 1) == "|" then
      cur[#cur + 1] = "|"
      i = i + 2
    elseif c == "`" then
      local run = line:match("^`+", i)
      if not ticks then ticks = run elseif run == ticks then ticks = nil end
      cur[#cur + 1] = run
      i = i + #run
    else
      if c == "|" and not ticks then
        out[#out + 1] = trim(table.concat(cur))
        cur = {}
      else
        cur[#cur + 1] = c
      end
      i = i + 1
    end
  end
  out[#out + 1] = trim(table.concat(cur))
  return out
end

local function is_rule_row(line: string): boolean return line:match("^%s*|?%s*:?%-%-+:?%s*|") ~= nil or line:match("^%s*|%s*:?%-+") ~= nil end

--- Markdown as a list of blocks (headings, paragraphs, lists, code, tables)
--- for `render`.
function M.parse(text: string): {Block}
  local lines: {string} = {}
  for line in (text:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = (line:gsub("\t", "    ")) end
  local blocks: {Block} = {}
  local function add(block: Block): Block
    blocks[#blocks + 1] = block
    return block
  end
  -- The indents of the list items open, to tell how deep an item is.
  local stack: {integer} = {}
  local function depth_of(indent: integer): integer
    while #stack > 0 and indent < stack[#stack] do stack[#stack] = nil end
    if #stack == 0 or indent > stack[#stack] then stack[#stack + 1] = indent end
    return #stack
  end
  local i = 1
  local para: Block
  while i <= #lines do
    local line = lines[i]
    local indent = #line:match("^ *")
    local fence = line:match("^%s*(```+)")
    local item_indent, marker, item_text = line:match("^( *)([-*+]) +(.*)$")
    if not marker then item_indent, marker, item_text = line:match("^( *)(%d+[.)]) +(.*)$") end
    if line:match("^%s*$") then
      para = nil
      if blocks[#blocks] and blocks[#blocks].type ~= "blank" then add({ type = "blank" }) end
      i = i + 1
    elseif fence then
      para = nil
      local body: {string} = {}
      i = i + 1
      while i <= #lines and not lines[i]:match("^%s*" .. fence) do
        body[#body + 1] = lines[i]:sub(math.min(indent, #lines[i]:match("^ *")) + 1)
        i = i + 1
      end
      add({ type = "code", lines = body, depth = indent > 0 and #stack or 0 })
      i = i + 1
    elseif line:match("^%s*<!%-%-") then
      para = nil
      local comment = line
      while not comment:find("%-%->") and i < #lines do
        i = i + 1
        comment = comment .. "\n" .. lines[i]
      end
      local names = comment:match("<!%-%-%s*tags:%s*(.-)%s*%-%->")
      if names then
        local block: Block = { type = "tags", names = {} }
        for name in names:gmatch("%S+") do block.names[#block.names + 1] = name end
        add(block)
      end
      i = i + 1
    elseif line:match("^#+%s") and indent == 0 then
      para = nil
      local hashes, title = line:match("^(#+)%s+(.-)%s*#*%s*$")
      add({ type = "heading", level = #hashes, text = title })
      stack = {}
      i = i + 1
    elseif line:match("^%s*|") and lines[i + 1] and is_rule_row(lines[i + 1]) then
      para = nil
      local rows = { cells(line) }
      i = i + 2
      while i <= #lines and lines[i]:match("^%s*|") do
        rows[#rows + 1] = cells(lines[i])
        i = i + 1
      end
      add({ type = "table", rows = rows, depth = indent > 0 and #stack or 0 })
    elseif line:match("^%s*([-*_])%s*%1%s*%1[-*_%s]*$") and not marker then
      para = nil
      add({ type = "rule" })
      i = i + 1
    elseif marker then
      para = add({ type = "item", depth = depth_of(#item_indent), marker = marker, text = item_text })
      i = i + 1
    elseif line:match("^%s*>") then
      local quoted = line:match("^%s*> ?(.*)$")
      if para and para.type == "quote" then
        para.text = para.text .. " " .. quoted
      else
        para = add({ type = "quote", text = quoted })
      end
      i = i + 1
    elseif indent >= 4 and #stack == 0 and (not blocks[#blocks] or blocks[#blocks].type == "blank") then
      local body: {string} = {}
      while i <= #lines and (lines[i]:match("^    ") or lines[i]:match("^%s*$")) do
        body[#body + 1] = lines[i]:sub(5)
        i = i + 1
      end
      local blank_after = false
      while #body > 0 and body[#body]:match("^%s*$") do
        body[#body], blank_after = nil, true
      end
      add({ type = "code", lines = body, depth = 0 })
      if blank_after then add({ type = "blank" }) end
    elseif para and (para.type == "para" or para.type == "item") then
      -- A line going on with the paragraph or item before it.
      para.text = para.text .. " " .. trim(line)
      i = i + 1
    else
      -- Text indented under a list item goes on in the list; text at the
      -- margin ends it.
      if indent == 0 then stack = {} end
      para = add({ type = "para", text = trim(line), depth = indent > 0 and #stack or 0 })
      i = i + 1
    end
  end
  while blocks[#blocks] and blocks[#blocks].type == "blank" do blocks[#blocks] = nil end
  return blocks
end

-- Lines --------------------------------------------------------------------------
--
-- A rendered line: `{ text, spans = { { c0, c1, style } }, links = { { c0,
-- c1, target } }, codes = { { c0, c1, text, first } } }` (`first`: the code
-- is in a table's first column or starts a list item, where a key or
-- command is named before it is described).

--- Runs cut into words: pieces of runs, broken at spaces outside code.
local function words_of(runs: {Run}): {{Run}}
  local words: {{Run}} = {}
  local cur: {Run}
  for _, run in ipairs(runs) do
    if run.code then
      cur = cur or {}
      cur[#cur + 1] = run
    else
      local text = run.text
      local pos = 1
      while pos <= #text do
        local s, e = text:find("%s+", pos)
        local piece = text:sub(pos, (s or #text + 1) - 1)
        if piece ~= "" then
          cur = cur or {}
          cur[#cur + 1] = { text = piece, style = run.style, link = run.link }
        end
        if not s then break end
        if cur then words[#words + 1] = cur end
        cur = nil
        pos = e + 1
      end
    end
  end
  if cur then words[#words + 1] = cur end
  return words
end

local function word_width(word: {Run}): integer
  local n = 0
  for _, piece in ipairs(word) do
    piece.w = piece.w or width(piece.text)
    n = n + piece.w
  end
  return n
end

local function new_line(prefix?: string, style?: string): Line
  local line: Line = { text = prefix or "", w = width(prefix or ""), spans = {}, links = {}, codes = {} }
  if style and prefix and prefix ~= "" then line.spans[1] = { 0, width(prefix), style } end
  return line
end

local function append(line: Line, text: string, style?: string, link?: string, code?: string, first?: boolean, tw?: integer)
  local c0 = line.w
  line.text = line.text .. text
  local c1 = c0 + (tw or width(text))
  line.w = c1
  if style then line.spans[#line.spans + 1] = { c0, c1, style } end
  if link then
    local last = line.links[#line.links]
    -- A link's words with the spaces between them are one link.
    if last and last[3] == link and last[2] >= c0 - 1 then
      last[2] = c1
    else
      line.links[#line.links + 1] = { c0, c1, link }
    end
  end
  if code then line.codes[#line.codes + 1] = { c0, c1, text, first } end
end

--- Runs filled into lines `w` wide: the first line starts with `first`
--- (a bullet), the rest with `rest` (as many spaces). `style` goes under
--- every piece that has none (a table's header). `lead` says which code is
--- marked `first`: "all", or "lead" for the code before the first plain word.
local function fill(runs: {Run}, w: integer, first: string, rest: string, style?: string, lead?: string): {Line}
  local out: {Line} = {}
  local line = new_line(first)
  local used = line.w
  local rest_w = width(rest)
  local empty = true
  local leading = lead ~= nil
  for _, word in ipairs(words_of(runs)) do
    local ww = word_width(word)
    if not empty and used + 1 + ww > w then
      out[#out + 1] = line
      line = new_line(rest)
      used, empty = rest_w, true
    end
    if not empty then
      -- The space between two words of one link is part of the link.
      local prev = line.links[#line.links]
      append(line, " ", nil, prev and word[1].link == prev[3] and word[1].link or nil, nil, nil, 1)
      used = used + 1
    end
    local has_code = false
    for _, piece in ipairs(word) do has_code = has_code or piece.code end
    if lead == "lead" and not has_code then leading = false end
    for _, piece in ipairs(word) do
      local text, tw = piece.text, piece.w
      -- A word wider than the whole line is cut where the line ends.
      while tw > w - rest_w and used + tw > w and used < w do
        local head, tail = cut(text, w - used)
        append(line, head, piece.style or style, piece.link, piece.code and piece.text, leading)
        out[#out + 1] = line
        line = new_line(rest)
        used, text = rest_w, tail
        tw = width(text)
      end
      append(line, text, piece.style or style, piece.link, piece.code and piece.text, leading, tw)
      used = used + tw
    end
    empty = false
  end
  out[#out + 1] = line
  return out
end

--- How wide each column of a table may be in `w` characters: as wide as
--- its widest cell while they all fit, else the narrow ones keep theirs and
--- the wide ones share what is left.
local function column_widths(natural: {integer}, w: integer): {integer}
  local n = #natural
  local room = w - 2 * (n - 1)
  local total = 0
  for _, nw in ipairs(natural) do total = total + nw end
  local out: {integer} = {}
  if total <= room then
    for i, nw in ipairs(natural) do out[i] = nw end
    return out
  end
  local open: {boolean} = {}
  local left = room
  for i = 1, n do open[i] = true end
  local changed = true
  while changed do
    changed = false
    local count = 0
    for i = 1, n do if open[i] then count = count + 1 end end
    if count == 0 then break end
    local share = math.floor(left / count)
    for i = 1, n do
      if open[i] and natural[i] <= share then
        out[i], open[i], left, changed = natural[i], false, left - natural[i], true
      end
    end
  end
  local count = 0
  for i = 1, n do if open[i] then count = count + 1 end end
  for i = 1, n do
    if open[i] then
      out[i] = math.max(8, math.floor(left / count))
    end
  end
  return out
end

local function runs_width(runs: {Run}): integer
  local n = 0
  for _, run in ipairs(runs) do n = n + width(run.text) end
  return n
end

--- The blocks as lines `opts.width` wide (78 by default). `opts.heading_tag(block)`
--- gives the tag that shows at the right of a heading (as the help of Vim
--- shows `*tag*`). Returns `{ lines, anchors }`. An anchor is `{ row, kind =
--- "heading" | "tags" | "code" | "lead", ... }` ("lead": the bold words at
--- the start of a paragraph).
function M.render(blocks: {Block}, opts?: M.RenderOptions): M.Document
  opts = opts or {}
  local W = opts.width or 78
  local lines: {Line} = {}
  local anchors: {Anchor} = {}
  local function push(line: Line) lines[#lines + 1] = line end
  local function blank()
    if #lines > 0 and lines[#lines].text ~= "" then push(new_line()) end
  end
  local function codes_of(from: integer)
    for row = from, #lines do
      for _, code in ipairs(lines[row].codes) do
        anchors[#anchors + 1] = { row = row, col = code[1], kind = "code", text = code[3], first = code[4] }
      end
    end
  end
  local pause = opts.pause
  for _, block in ipairs(blocks) do
    if pause then pause() end
    local from = #lines + 1
    local t = block.type
    if t == "blank" then
      blank()
    elseif t == "heading" then
      blank()
      if block.level == 2 then push(new_line(string.rep("─", W), "HelpRule")) end
      local tag = opts.heading_tag and opts.heading_tag(block)
      local style = block.level == 1 and "HelpTitle" or "HelpHeading"
      local runs = inline(block.text, style)
      for _, run in ipairs(runs) do if run.code then run.style = style end end
      local room = W - (tag and width(tag) + 3 or 0)
      local body = fill(runs, math.max(20, room), "", "")
      for k, line in ipairs(body) do
        if k == #body and tag then
          local pad = math.max(1, W - width(line.text) - width(tag) - 2)
          append(line, string.rep(" ", pad) .. "*" .. tag .. "*", "HelpTag")
        end
        push(line)
      end
      anchors[#anchors + 1] = { row = from + (block.level == 2 and 1 or 0), kind = "heading", level = block.level, text = M.plain(block.text) }
    elseif t == "para" or t == "quote" then
      -- A paragraph that starts in bold is named by those words.
      local lead = t == "para" and block.text:match("^%*%*(.-)%*%*")
      if lead then anchors[#anchors + 1] = { row = from, kind = "lead", text = lead:gsub("[%.:]$", "") } end
      local indent = string.rep(" ", (block.depth or 0) * 4)
      local prefix = t == "quote" and indent .. "│ " or indent
      for _, line in ipairs(fill(inline(block.text), W, prefix, prefix)) do push(line) end
    elseif t == "item" then
      local pad = string.rep("    ", block.depth - 1)
      local bullet: string
      if block.marker:match("%d") then
        bullet = string.format("%3s ", block.marker)
      else
        bullet = "  • "
      end
      local first = pad .. bullet
      for k, line in ipairs(fill(inline(block.text), W, first, string.rep(" ", width(first)), nil, "lead")) do
        if k == 1 then line.spans[#line.spans + 1] = { width(pad), width(first), "HelpBullet" } end
        push(line)
      end
    elseif t == "code" then
      local indent = string.rep(" ", 4 + (block.depth or 0) * 4)
      for _, text in ipairs(block.lines) do
        local line = new_line(indent)
        append(line, text, "HelpCode")
        push(line)
      end
    elseif t == "rule" then
      blank()
      push(new_line(string.rep("─", W), "HelpRule"))
    elseif t == "tags" then
      anchors[#anchors + 1] = { row = #lines + 1, kind = "tags", names = block.names }
    elseif t == "table" then
      local indent = string.rep(" ", (block.depth or 0) * 4)
      local rows: {{{Run}}} = {}
      local natural: {integer} = {}
      for r, row in ipairs(block.rows) do
        rows[r] = {}
        for c, cell in ipairs(row) do
          rows[r][c] = inline(cell)
          natural[c] = math.max(natural[c] or 1, runs_width(rows[r][c]))
        end
      end
      local widths = column_widths(natural, W - #indent)
      local laid: {{{Line}}} = {}
      local tall = false
      for r, row in ipairs(rows) do
        laid[r] = {}
        for c = 1, #widths do
          laid[r][c] = fill(row[c] or {}, widths[c], "", "", r == 1 and "HelpTableHead" or nil, c == 1 and "all" or nil)
          if r > 1 and #laid[r][c] > 1 then tall = true end
        end
      end
      for r = 1, #laid do
        if r > 2 and tall then push(new_line()) end
        local height = 0
        for c = 1, #widths do height = math.max(height, #laid[r][c]) end
        for k = 1, height do
          local line = new_line(indent)
          for c = 1, #widths do
            local part = laid[r][c][k]
            local at = line.w
            if part then
              line.text, line.w = line.text .. part.text, line.w + part.w
              for _, s in ipairs(part.spans) do line.spans[#line.spans + 1] = { s[1] + at, s[2] + at, s[3] } end
              for _, l in ipairs(part.links) do line.links[#line.links + 1] = { l[1] + at, l[2] + at, l[3] } end
              for _, code in ipairs(part.codes) do line.codes[#line.codes + 1] = { code[1] + at, code[2] + at, code[3], code[4] and k == 1 } end
            end
            if c < #widths then
              local pad = widths[c] - (part and part.w or 0) + 2
              line.text, line.w = line.text .. string.rep(" ", pad), line.w + pad
            end
          end
          line.text = line.text:gsub("%s+$", "")
          line.w = width(line.text)
          push(line)
        end
        if r == 1 then
          local parts: {string} = {}
          for c, cw in ipairs(widths) do parts[c] = string.rep("─", cw) end
          push(new_line(indent .. table.concat(parts, "  "), "HelpRule"))
        end
      end
    end
    if t ~= "heading" then codes_of(from) end
  end
  while #lines > 0 and lines[#lines].text == "" do lines[#lines] = nil end
  return { lines = lines, anchors = anchors }
end

return M
