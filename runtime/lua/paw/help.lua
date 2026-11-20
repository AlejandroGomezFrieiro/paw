-- Help, as Vim's: the manual inside the program. docs/reference/help.md says how
-- it is used, docs/reference/lua-views.md how an extension ships help of its own.
--
--   :help                the contents
--   :help gU             a key        :help :s           a command
--   :help 'timebind'     an option    :help paw.qf       a Lua module
--   :help key-rule       a section    :helpgrep stretch  every line that says it
--
-- The pages are the Markdown under docs/ (the manual, by kind: tutorials,
-- how-to guides, reference and explanation, as docs/README.md lists them),
-- every extension's README.md and doc/*.md (bundled beside the program or in
-- the configuration, loaded or not), and what `paw.help.add` names, made into
-- text by paw/markdown.lua and shown in text buffers (`help://help.md`)
-- that cannot be changed. Their keys are the text buffers' own (motions,
-- `v`, `y`, `/`), with `Ctrl-]` (or `Enter`, or a double click) to follow
-- the link or look up the word under the cursor, `K` to look a word up,
-- `Ctrl-o` and `Ctrl-t` to go back.
--
-- Tags are made, the first time help is asked for, from the headings (the
-- page's name for its title, the heading's words joined by `-` below it,
-- after the extension's name or `course-N` in theirs), from `<!-- tags: a b
-- -->` comments, and from every key, command (`:s`), option (`'timebind'`),
-- Lua name (`paw.qf.feed`) and address (`paw://tracks`) written as code:
-- each at the first place it is described (a table's first column, the
-- start of a list item), else where it is first named.
local api = paw.api
local util = paw.util
local md = paw.markdown
local layout = paw.layout

local M = { width = 78, extra = {} }

-- Files -------------------------------------------------------------------------

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function list_dir(dir)
  local ok, items = pcall(api.read_dir, dir)
  return ok and items or {}
end

local exists = paw.api.fs_exists

--- A path without `.` and `..`, made absolute from the current directory.
local function normalize(path)
  if not path:match("^/") then path = (os.getenv("PWD") or ".") .. "/" .. path end
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      parts[#parts] = nil
    elseif part ~= "." then
      parts[#parts + 1] = part
    end
  end
  return "/" .. table.concat(parts, "/")
end
M.normalize = normalize

local function dir_of(path) return path:match("^(.*)/[^/]*$") or "." end

--- The directories that can be a copy of the source tree, with the manual
--- and the bundled extensions in it. These are `$PAW_HOME` (where an
--- installed program keeps them), the parent of the runtime (`--runtime`),
--- the tree of a loaded extension, and the current directory.
function M.roots()
  local out, seen = {}, {}
  local function add(dir)
    if not dir or dir == "" then return end
    dir = normalize(dir)
    if not seen[dir] then
      seen[dir] = true
      out[#out + 1] = dir
    end
  end
  add(os.getenv("PAW_HOME"))
  local env = api.env()
  if env.runtime_dir then add(env.runtime_dir .. "/..") end
  for _, entry in ipairs(paw.ext.list()) do
    local tree = normalize(entry.path):match("^(.*)/extensions/[^/]+$")
    add(tree)
  end
  add(os.getenv("PWD"))
  return out
end

-- The manual's four kinds of page, each in its folder of docs/ and under its
-- heading in docs/README.md and in the contents, in the order shown there.
M.kinds = {
  { name = "tutorials", title = "Tutorials" },
  { name = "how-to", title = "How-to guides" },
  { name = "reference", title = "Reference" },
  { name = "explanation", title = "Explanation" },
}

local function ext_loaded(name)
  local entry = paw.ext.loaded[name]
  return entry ~= nil and entry.ok ~= false
end

--- What docs/README.md says of the pages it links: the kind of the section
--- each is listed under, and the order they are listed in. Paths are
--- absolute.
local function readme_order(docs)
  local kind_of, rank = {}, {}
  local by_title = {}
  for _, kind in ipairs(M.kinds) do by_title[kind.title:lower()] = kind.name end
  local kind, n = nil, 0
  for line in (read_file(docs .. "/README.md") or ""):gmatch("[^\n]*") do
    local heading = line:match("^##%s+(.-)%s*$")
    if heading then kind = by_title[heading:lower()] end
    for target in line:gmatch("%]%(([^)#%s]+%.md)[^)]*%)") do
      if kind and not target:match("^%a+:") then
        local path = normalize(docs .. "/" .. target)
        if not rank[path] then
          n = n + 1
          kind_of[path], rank[path] = kind, n
        end
      end
    end
  end
  return kind_of, rank
end

--- Every Markdown file under `dir`, as paths relative to it; `images` is skipped.
local function markdown_files(dir, rel, out)
  out = out or {}
  for _, item in ipairs(list_dir(dir .. (rel and "/" .. rel or ""))) do
    local path = rel and rel .. "/" .. item.name or item.name
    if item.is_dir then
      if path ~= "images" then markdown_files(dir, path, out) end
    elseif item.name:match("%.md$") then
      out[#out + 1] = path
    end
  end
  return out
end

--- A file name as it sorts in its folder: the folder's README first, numbered
--- pages (lessons) by number, the rest by name after them.
local function sort_key(rel)
  return (rel:gsub("[^/]+$", function(file)
    return file == "README.md" and "" or file:match("^%d") and file or "~" .. file
  end))
end

--- The pages of the manual: each Markdown file under docs/. The kind of a
--- page is the kind of its folder (docs/reference/...). If not, it is the
--- section of docs/README.md that lists it, or the README of its folder.
--- The name of a page is its base name (`help://options.md`, tags
--- `options`). When two kinds have pages with the same name, the kind
--- comes before the name (`how-to/x.md`, `how-to-x`). A page in a separate
--- folder has its path in its kind as name (`course/05-grammar.md`). Its
--- tags come after the folder: `course` for the README of the folder, and
--- `course-5` and `course-grammar` for a numbered page.
local function manual_sources(docs)
  local kind_of, rank = readme_order(docs)
  local is_kind = {}
  for _, kind in ipairs(M.kinds) do is_kind[kind.name] = true end
  local pages, bases = {}, {}
  for _, rel in ipairs(markdown_files(docs)) do
    if rel ~= "README.md" then
      local path = docs .. "/" .. rel
      local top, rest = rel:match("^([^/]+)/(.+)$")
      local kind, inner
      if top and is_kind[top] then
        kind, inner = top, rest
      else
        inner = rel
        kind = kind_of[path] or (top and kind_of[docs .. "/" .. top .. "/README.md"]) or "reference"
      end
      local page = { path = path, kind = kind, inner = inner, rank = rank[path] or (top and rank[docs .. "/" .. top .. "/README.md"]) }
      pages[#pages + 1] = page
      if not inner:find("/") then
        local base = inner:gsub("%.md$", "")
        bases[base] = (bases[base] or 0) + 1
      end
    end
  end
  local out = {}
  for _, page in ipairs(pages) do
    local inner, kind = page.inner, page.kind
    local folder, file = inner:match("^(.+)/([^/]+)$")
    local name, aliases, prefix
    if folder then
      local tag = folder:gsub("/", "-")
      local n, rest = file:match("^(%d+)%-(.+)%.md$")
      name = inner
      if n then
        aliases, prefix = { tag .. "-" .. tonumber(n), tag .. "-" .. rest }, tag .. "-" .. tonumber(n)
        page.lesson = tonumber(n)
      elseif file == "README.md" then
        aliases, prefix = { tag }, tag
        -- The course was found as the tutor's too.
        if tag == "course" then aliases[2] = "tutor-course" end
      else
        local base = file:gsub("%.md$", "")
        aliases, prefix = { tag .. "-" .. base }, tag .. "-" .. base
      end
    else
      local base = inner:gsub("%.md$", "")
      if bases[base] > 1 then
        name, aliases = kind .. "/" .. inner, { kind .. "-" .. base, kind .. "/" .. inner }
      else
        name, aliases = inner, { base, inner }
      end
      -- The key table's sections are named as the pages that describe
      -- the same keys at length: those keep the plain tags.
      prefix = inner == "keys.md" and "keys" or ""
    end
    out[#out + 1] = {
      path = page.path, name = name, aliases = aliases, prefix = prefix, group = kind, manual = true,
      lesson = page.lesson, rank = page.rank, key = sort_key(inner),
      -- The key table is where every key is described in one line.
      keytable = inner:match("[^/]+$") == "keys.md",
    }
  end
  -- Pages that describe come before those that teach, so that where two
  -- name a thing alike, the reference's is found first.
  local weight = { reference = 1, ["how-to"] = 2, explanation = 3, tutorials = 4 }
  table.sort(out, function(a, b)
    if a.group ~= b.group then return (weight[a.group] or 5) < (weight[b.group] or 5) end
    local ra, rb = a.rank or math.huge, b.rank or math.huge
    if ra ~= rb then return ra < rb end
    return a.key < b.key
  end)
  return out
end
M.manual_sources = manual_sources

--- Each page of help, in order: the contents, the manual (reference, how-to
--- guides, explanation, tutorials), the extensions (each with a flag that
--- tells if it is loaded) and the added pages. A page is `{ path, name,
--- aliases, prefix, group, ext? }`. `name` is the name of its buffer
--- (`help://name`). `aliases` is its tags (its title shows the first).
--- `prefix` is the start of the tags of its headings. `group` is the kind
--- of page in the manual, or `extensions` or `added`.
function M.sources()
  local out = { { name = "index", aliases = { "help", "index", "contents" }, prefix = "help", index = true } }
  local roots = M.roots()
  local docs
  for _, root in ipairs(roots) do
    if not docs and exists(root .. "/docs/README.md") then docs = root .. "/docs" end
  end
  if docs then
    -- A link to the manual's contents page goes to help's.
    out[1].readme = docs .. "/README.md"
    for _, source in ipairs(manual_sources(docs)) do out[#out + 1] = source end
  end
  -- Extensions: a loaded one where it was loaded from, then those in the
  -- configuration, then those bundled in the source tree.
  local exts, order = {}, {}
  local function add_ext(name, path)
    if exts[name] then return end
    exts[name] = path
    order[#order + 1] = name
  end
  for _, entry in ipairs(paw.ext.list()) do
    if not entry.path:match("%.lua$") then add_ext(entry.name, normalize(entry.path)) end
  end
  for _, item in ipairs(list_dir(api.env().config_dir .. "/extensions")) do
    if item.is_dir then add_ext(item.name, normalize(api.env().config_dir .. "/extensions/" .. item.name)) end
  end
  for _, root in ipairs(roots) do
    for _, item in ipairs(list_dir(root .. "/extensions")) do
      if item.is_dir then add_ext(item.name, root .. "/extensions/" .. item.name) end
    end
  end
  table.sort(order)
  for _, name in ipairs(order) do
    local dir = exts[name]
    if exists(dir .. "/README.md") then
      out[#out + 1] = { path = dir .. "/README.md", name = name .. "/README.md", aliases = { name }, prefix = name, ext = name, dir = dir, group = "extensions" }
    end
    local files = {}
    for _, item in ipairs(list_dir(dir .. "/doc")) do
      if item.name:match("%.md$") then files[#files + 1] = item.name end
    end
    table.sort(files)
    for _, file in ipairs(files) do
      local base = file:gsub("%.md$", "")
      local tag = (base == name or base == "README") and name or name .. "-" .. base
      out[#out + 1] = { path = dir .. "/doc/" .. file, name = name .. "/doc/" .. file, aliases = { tag }, prefix = tag, ext = name, dir = dir, group = "extensions" }
    end
  end
  for _, extra in ipairs(M.extra) do out[#out + 1] = extra end
  return out
end

--- Add a page of help: a Markdown file in any folder. `opts.tag` is its tag
--- and the start of the tags of its headings (the name of the file by
--- default). `opts.ext` is the extension that it is about, and `opts.dir`
--- is the folder of that extension. The page shows a note while the
--- extension is not loaded. You do not add the README.md and doc/*.md of
--- an extension.
---   paw.help.add("/path/to/mine/notes.md", { tag = "mine-notes" })
function M.add(path, opts)
  opts = opts or {}
  path = normalize(path)
  local tag = opts.tag or path:match("([^/]+)%.md$") or path:match("([^/]+)$")
  for i, extra in ipairs(M.extra) do
    if extra.path == path then table.remove(M.extra, i) break end
  end
  M.extra[#M.extra + 1] = { path = path, name = tag .. ".md", aliases = { tag }, prefix = tag, ext = opts.ext, dir = opts.dir and normalize(opts.dir), group = "added" }
  M.dirty = true
end

-- Tags ----------------------------------------------------------------------------

--- A heading's words as a tag: `Ex: ranges, :s and :g` is `ex-ranges-s-and-g`.
local function slug(text)
  local s = md.plain(text):lower():gsub("[^%w%.]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  s = s:gsub("^the%-", ""):gsub("^an?%-", "")
  return s
end
M.slug = slug

--- A heading as GitHub makes its anchor, for links written `page.md#anchor`.
local function anchor(text)
  return (md.plain(text):lower():gsub("[^%w%s%-_]", ""):gsub("%s", "-"))
end

--- The command an Ex line runs: `:%s/a/b/g` runs `s`, `:5,8co 17` `co`.
local function ex_name(line)
  local s = line:gsub("^:", "")
  local before
  repeat
    before = s
    s = s:gsub("^%s+", ""):gsub("^%%", ""):gsub("^[%d%.]+", ""):gsub("^[,;]", ""):gsub("^%$", "")
    s = s:gsub("^'[%a<>]", ""):gsub("^[+%-]%d*", ""):gsub("^t[%d%.%$%*]+", ""):gsub("^t/[^/]*/", ""):gsub("^t'<,'>", "")
  until s == before
  -- Names may hold `-` (`:notation.apply-marks`).
  return s:match("^([%a][%w%._%-]*!?)")
end
M.ex_name = ex_name

local known_keys
local function keys_known()
  if known_keys then return known_keys end
  known_keys = {}
  for _, map in ipairs(paw.keymap.every()) do
    known_keys[map.lhs] = true
    known_keys[paw.keymap.human(map.lhs)] = true
  end
  return known_keys
end

local known_options
local function option_known(name)
  if not known_options then
    known_options = {}
    for _, o in ipairs(paw.option.list()) do known_options[o.name] = true end
  end
  return known_options[name] == true
end

--- The tags that a piece of code names. A command line names its command,
--- and `:set x` also names the option. A Lua name names itself and its
--- modules. An address, an option, the name of a command and a key name
--- themselves. With `first`, the code is where an item is described (the
--- first column of a table), so each short word in it is a tag.
local function tags_of_code(text, first)
  local out = {}
  if #text > 48 then return out end
  if text:match("^:") then
    local cmd = ex_name(text)
    if cmd then
      out[#out + 1] = ":" .. cmd:gsub("!$", "")
      local opt = (cmd == "set" or cmd == "setlocal") and text:match("^:set%a*%s+([%w_]+)")
      if opt then
        if not option_known(opt) and opt:match("^no") and option_known(opt:sub(3)) then opt = opt:sub(3) end
        out[#out + 1] = "'" .. opt .. "'"
      end
    end
    return out
  end
  local opt = text:match("^paw%.opt%.([%w_]+)")
  if opt then
    out[#out + 1] = "'" .. opt .. "'"
    return out
  end
  local lua = text:match("^(paw[%.:][%w_%.:]*[%w_])")
  if lua then
    out[#out + 1] = lua
    local parent = lua
    while true do
      parent = parent:match("^(.+)[%.:][^%.:]+$")
      if not parent or parent == "paw" then break end
      out[#out + 1] = parent
    end
    return out
  end
  if text:match("^paw://") then
    out[#out + 1] = text:match("^(paw://[%w_/%.%*]+)")
    return out
  end
  if text:match("^'[%w_]+'$") then
    out[#out + 1] = text
    return out
  end
  if text:match("^[%w_]+$") and option_known(text) and text:find("_") then out[#out + 1] = "'" .. text .. "'" end
  -- A command's dotted name, alone or with its arguments (`drums.track [name]`).
  local word = text:match("^([%a][%w%._%-]*!?)")
  local cmd = word and word:find("%.") and paw.commands.get((word:gsub("!$", "")))
  if cmd and (word == text or text:sub(#word + 1, #word + 1) == " ") then
    out[#out + 1] = ":" .. word:gsub("!$", "")
  end
  -- Keys after the leader are named as they are typed (`<leader>SL` is `,SL`).
  if text:match("^<leader>") or text:match("^<localleader>") then text = paw.keymap.human(text) end
  -- Keys written as mappings write them (`<C-w>o`) are named as people
  -- write them (`Ctrl-w o`), as the docs do.
  if text:match("^<%a%-.->") or text:match("^<%u%a+>$") then text = paw.keymap.human(text) end
  local short = #text <= 16 and not text:find("  ") and not text:find("^%s")
  local keyish = short and (not text:find(" ") or text:match("^%u%l+%-%S+ %S+$"))
  if keyish and (keys_known()[text] or first) then out[#out + 1] = text end
  return out
end
M.tags_of_code = tags_of_code

-- Building ------------------------------------------------------------------------

local built           -- { sources, tags = name -> tag, list = { tag }, by_name = source by name, by_path }
local parsed = {}     -- path -> { text, blocks }

--- The contents page, as Markdown.
local function index_text(sources)
  local out = {
    "# paw help",
    "",
    "This page is the contents of the help. Each line below is a link to a page or to a section.",
    "",
    "The keys of a text move the cursor in this page: `j` and `k` move it, `/` searches, "
      .. "`v` selects and `y` copies. `Ctrl-]` follows the link or the word under the cursor. "
      .. "`Enter` and a double click do the same. `Ctrl-o` and `Ctrl-t` return to the previous place. "
      .. "`K` finds the word under the cursor in the help. `-` shows this page again.",
    "",
    "`:help` with a topic shows that topic, and `Tab` completes the topic. A topic is a key "
      .. "(`:help gU`), a command (`:help :s`), an option (`:help 'timebind'`), a Lua module "
      .. "(`:help paw.qf`) or a section (`:help key-rule`). `:helpgrep` with words puts each "
      .. "line of help that contains the words in the quickfix list. `]q` moves to the next line "
      .. "of that list. `?` shows the keys of the current view. `:q` closes this window.",
  }
  local has_manual = false
  for _, source in ipairs(sources) do has_manual = has_manual or source.manual == true end
  if not has_manual then
    out[#out + 1] = ""
    out[#out + 1] = "paw did not find the manual (`docs/`). Run paw from its source tree, or set `PAW_HOME` to a directory that contains `docs/`."
  end
  local groups = {}
  for _, kind in ipairs(M.kinds) do groups[#groups + 1] = { kind.name, kind.title } end
  groups[#groups + 1] = { "extensions", "Extensions" }
  groups[#groups + 1] = { "added", "Added" }
  for _, group in ipairs(groups) do
    local any = false
    for _, source in ipairs(sources) do
      if source.group == group[1] then
        if not any then
          out[#out + 1] = ""
          out[#out + 1] = "## " .. group[2]
          out[#out + 1] = ""
          any = true
        end
        local title = source.title or source.name
        local note = ""
        if source.ext and not ext_loaded(source.ext) then note = " (not loaded)" end
        out[#out + 1] = "- [" .. title:gsub("[%[%]]", "") .. "](help:" .. source.aliases[1] .. ")" .. note
        for _, heading in ipairs(source.headings or {}) do
          if heading.level == 2 then
            out[#out + 1] = "    - [" .. md.plain(heading.text):gsub("[%[%]]", "") .. "](help:" .. heading.tag .. ")"
          end
        end
      end
    end
  end
  return table.concat(out, "\n")
end

--- The note at the top of the page of an extension that is not loaded.
local function unloaded_note(source)
  local env = api.env()
  -- A bundled extension is loaded by its name.
  local bundled = paw.ext.bundled_dir and paw.ext.bundled_dir()
  local by_name = bundled and normalize(bundled) == dir_of(source.dir)
  local now = by_name and ":ext.load " .. source.ext or ":lua paw.ext.load(\"" .. source.dir .. "\")"
  return table.concat({
    "**This extension is not loaded.** For this session:",
    "",
    "    " .. now,
    "",
    "To have it every time, link it into your configuration:",
    "",
    "    ln -s " .. source.dir .. " " .. env.config_dir .. "/extensions/",
  }, "\n")
end

local function heading_tags(sources)
  local used = {}
  local function take(name)
    if used[name] then return nil end
    used[name] = true
    return name
  end
  for _, source in ipairs(sources) do
    for _, alias in ipairs(source.aliases) do used[alias] = used[alias] or source end
  end
  for _, source in ipairs(sources) do
    source.headings = {}
    for _, block in ipairs(source.blocks) do
      if block.type == "heading" then
        local base = slug(block.text)
        if block.level == 1 and not source.title then
          source.title = md.plain(block.text)
          block.tag = source.aliases[1]
        else
          local name = source.prefix ~= "" and source.prefix .. "-" .. base or base
          block.tag = take(name) or take(source.aliases[1] .. "-" .. base)
          local n = 2
          while not block.tag do
            block.tag = take(name .. "-" .. n)
            n = n + 1
          end
        end
        source.headings[#source.headings + 1] = block
      end
    end
  end
end

--- Read every page, give its headings their tags, make it into lines and
--- gather the tags. Done again when a page changed, an extension was loaded
--- or a page was added.
local function build()
  -- The files are looked at again at most every two seconds.
  local loaded = {}
  for _, entry in ipairs(paw.ext.list()) do loaded[#loaded + 1] = entry.name .. tostring(entry.ok) end
  loaded = table.concat(loaded, " ")
  if built and not M.dirty and built.loaded == loaded and api.now() - built.checked < 2000 then return built end
  local sources = M.sources()
  local signature = {}
  for _, source in ipairs(sources) do
    -- docs/README.md orders the contents.
    if source.readme then signature[#signature + 1] = read_file(source.readme) or "" end
    if not source.index then
      local text = read_file(source.path) or ""
      local cached = parsed[source.path]
      if not (cached and cached.text == text) then
        cached = { text = text, blocks = md.parse(text) }
        parsed[source.path] = cached
      end
      source.blocks = cached.blocks
      source.loaded = not source.ext or ext_loaded(source.ext)
      signature[#signature + 1] = source.path .. "\0" .. tostring(cached) .. "\0" .. tostring(source.loaded)
    end
  end
  signature = table.concat(signature, "\n")
  if built and built.signature == signature and not M.dirty then
    built.checked, built.loaded = api.now(), loaded
    return built
  end
  M.dirty = false
  known_keys, known_options = nil, nil
  -- The contents are made from the pages' titles and headings.
  sources[1].blocks = {}
  heading_tags(sources)
  sources[1].blocks = md.parse(index_text(sources))
  sources[1].title = nil
  heading_tags({ sources[1] })
  local tags = {}
  -- Each extension's pages' own tags too, for what the extension owns
  -- (`ext_tags[name][tag]`): its commands and keys are found there even
  -- where the manual names them first.
  local ext_tags = {}
  local function add(name, source, row, col, prio)
    if not name or name == "" then return end
    local tag = { name = name, source = source, row = row, col = col or 0, prio = prio, order = source.order }
    if source.ext then
      local own = ext_tags[source.ext] or {}
      ext_tags[source.ext] = own
      if not own[name] or own[name].prio > prio then own[name] = tag end
    end
    local old = tags[name]
    if old and old.prio <= prio then return end
    tags[name] = tag
  end
  local by_name, by_path = {}, {}
  for i, source in ipairs(sources) do
    source.order = i
    by_name[source.name] = source
    if source.path then by_path[source.path] = source end
    if source.readme then by_path[source.readme] = source end
    local blocks = source.blocks
    if source.ext and not source.loaded and source.dir then
      blocks = util.merge({}, blocks)
      local note = md.parse(unloaded_note(source))
      local at = 1
      while blocks[at] and blocks[at].type ~= "heading" do at = at + 1 end
      table.insert(blocks, at + 1, { type = "blank" })
      for i, block in ipairs(note) do table.insert(blocks, at + 1 + i, block) end
      table.insert(blocks, at + 2 + #note, { type = "blank" })
    end
    source.doc = md.render(blocks, { width = M.width, heading_tag = function(block) return block.tag end })
    source.anchors = {}
    for _, alias in ipairs(source.aliases) do add(alias, source, 1, 0, 0) end
    local heading_at = 0
    for _, a in ipairs(source.doc.anchors) do
      if a.kind == "heading" then
        heading_at = heading_at + 1
        local block = source.headings[heading_at]
        if block then
          add(block.tag, source, a.row, 0, 1)
          source.anchors[anchor(block.text)] = a.row
        end
      elseif a.kind == "tags" then
        for _, name in ipairs(a.names) do add(name, source, a.row, 0, 1) end
      elseif a.kind == "lead" then
        local base = slug(a.text)
        add(source.prefix ~= "" and source.prefix .. "-" .. base or base, source, a.row, 0, 3)
      elseif a.kind == "code" then
        -- Where the manual describes or uses a thing comes before where a
        -- tutorial or an extension's page does.
        local after = source.manual and source.group ~= "tutorials" and 0 or 3
        -- A row of the key table is a one-line entry for its keys: it beats
        -- every mention in prose, and a key's own heading.
        local prio = (a.first and 2 or 4) + after
        if a.first and source.keytable then prio = 1 end
        -- The generated reference (docs/reference/api.md) lists every Lua
        -- name: it is where a name goes that the manual does not mention.
        if source.name == "api.md" then prio = 5 end
        for _, name in ipairs(tags_of_code(a.text, a.first)) do add(name, source, a.row, a.col, prio) end
      end
    end
  end
  local list = {}
  for _, tag in pairs(tags) do list[#list + 1] = tag end
  table.sort(list, function(a, b) return a.name < b.name end)
  built = { checked = api.now(), loaded = loaded, signature = signature, sources = sources, tags = tags, list = list, by_name = by_name, by_path = by_path,
    ext_tags = ext_tags }
  return built
end

--- What help knows: `{ sources, tags = name -> { name, source, row, col }, list }`.
function M.index() return build() end

-- Finding ---------------------------------------------------------------------------

--- How well `name` matches `q` (lowercase both), lower is better, or nil:
--- whole, start, inside, then the letters in order (fewer gaps first).
local function score(name, q)
  local lower = name:lower()
  if lower == q then return 1 end
  if lower:sub(1, #q) == q then return 2 + #name / 1000 end
  local at = lower:find(q, 1, true)
  if at then return 3 + #name / 1000 end
  local pos, gaps = 0, 0
  for i = 1, #q do
    local found = lower:find(q:sub(i, i), pos + 1, true)
    if not found then return nil end
    if found > pos + 1 and pos > 0 then gaps = gaps + 1 end
    pos = found
  end
  return 4 + gaps / 100 + #name / 100000
end

--- The tags that a topic finds, best first, in the order of the `:help` of
--- Vim. First the tag itself, then the tags that start with it, the tags
--- that contain it, and the tags that contain its letters in order. You can
--- write keys in the two ways: `<C-w>o` finds `Ctrl-w o`.
function M.find(topic, limit)
  local index = build()
  topic = (topic or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if topic == "" then return { index.tags.help } end
  local exact = index.tags[topic]
  if not exact and topic:match("^<.+>") then exact = index.tags[paw.keymap.human(topic)] end
  exact = M.owned(index, topic, exact)
  local q = topic:lower()
  local found = {}
  for _, tag in ipairs(index.list) do
    if tag ~= exact then
      local s = score(tag.name, q)
      if s then found[#found + 1] = { tag = tag, score = s } end
    end
  end
  table.sort(found, function(a, b)
    if a.score ~= b.score then return a.score < b.score end
    if a.tag.prio ~= b.tag.prio then return a.tag.prio < b.tag.prio end
    if a.tag.order ~= b.tag.order then return a.tag.order < b.tag.order end
    return a.tag.name < b.tag.name
  end)
  local out = { exact }
  for _, f in ipairs(found) do
    if limit and #out >= limit then break end
    out[#out + 1] = f.tag
  end
  return out
end

--- The extensions that own what a topic names: the command's (`:name`),
--- or a key's when only extensions map it (a key the core maps is the
--- core's). A list, empty for the core's.
function M.owners(topic)
  local cmd = topic:match("^:(.+)$")
  if cmd then
    local spec = paw.commands.get(cmd)
    return spec and spec.ext and { spec.ext } or {}
  end
  local out, seen = {}, {}
  for _, map in ipairs(paw.keymap.every()) do
    if map.lhs == topic or paw.keymap.human(map.lhs) == topic then
      if not map.ext then return {} end
      if not seen[map.ext] then
        seen[map.ext] = true
        out[#out + 1] = map.ext
      end
    end
  end
  return out
end

--- The tag a topic an extension owns goes to: its place in the owner's
--- pages (where `exact` is not already), else the owner's first page.
function M.owned(index, topic, exact)
  local owners = M.owners(topic)
  if #owners == 0 then return exact end
  for _, ext in ipairs(owners) do
    if exact and exact.source.ext == ext then return exact end
  end
  local human = topic:match("^<.+>") and paw.keymap.human(topic)
  -- `:name!` is described with `:name`.
  local plain = topic:match("^(:.+)!$")
  for _, ext in ipairs(owners) do
    local own = index.ext_tags[ext]
    local tag = own and (own[topic] or (human and own[human]) or (plain and own[plain]))
    if tag then return tag end
  end
  for _, ext in ipairs(owners) do
    local page = index.tags[ext]
    if page and page.source.ext == ext then return page end
  end
  return exact
end

--- The tag a topic goes to, or nil.
function M.lookup(topic) return M.find(topic, 1)[1] end

-- The buffers -------------------------------------------------------------------------

--- True if a buffer is a page of help.
local function is_help(buf) return buf and buf.type == "textbuf" and buf.state and buf.state.kind and buf.state.kind.name == "help" end
M.is_help = is_help

local function source_of(buf)
  local name = buf.name:match("^help://(.+)$")
  return name and build().by_name[name]
end

--- The window showing help in this tab, if any.
local function help_window()
  local cur = layout.current()
  if cur and is_help(layout.buf_of(cur)) then return cur end
  for _, win in ipairs(layout.windows()) do
    if is_help(layout.buf_of(win)) then return win end
  end
end

--- Put the cursor of a help window at a row and column, the row near the
--- top as a tag jump does.
local function place(win, row, col)
  local s = win.state
  s.row, s.col, s.want = row, col or 0, col or 0
  -- A section's rule stays in sight above its heading.
  s.top = math.max(1, row - 1)
  api.ui_redraw()
end

-- Where tag jumps came from, for `Ctrl-t`.
local stack = {}
paw.seats.keep("help.tagstack", function() return stack end, function(s) stack = s end, function() return {} end)

--- Show a page at a row. It shows in the help window, or in a window split
--- from the current window (as the `:help` of Vim splits). In a graphical
--- frontend, it shows as a docked pane (`gw` moves it to a separate window).
--- Returns the window.
function M.show(source, row, col)
  local name = "help://" .. source.name
  local buf = layout.buf_create("textbuf", name)
  local win = help_window()
  if win then
    layout.enter(win)
    win = layout.show_in(win, "textbuf", buf.id)
  else
    local new = layout.split({ view = "textbuf", buf = buf.id })
    -- Help takes half the screen, as Vim gives it 'helpheight' rows, whatever
    -- else shares the column.
    if new then
      local _, height = paw.ui.size()
      new.size, new.weight = math.max(8, math.floor(height / 2)), nil
    end
    win = new or layout.show_in(layout.current(), "textbuf", buf.id)
  end
  place(win, row, col)
  return win
end

--- Go to a tag: remember where from (for `Ctrl-t` and `Ctrl-o`) and show it.
function M.jump(tag)
  local win, buf, _, s = paw.textbuf.here()
  if win and buf then
    stack[#stack + 1] = { name = buf.name, row = s.row, col = s.col }
    if #stack > 50 then table.remove(stack, 1) end
    paw.keymap.push_jump()
  end
  local source = tag.source
  if source.ext and not source.loaded then paw.notify(source.ext .. " is not loaded: the page says how to load it", "warn") end
  return M.show(source, tag.row, tag.col)
end

--- `:help topic`: go to the best tag for it, or say there is none.
function M.open(topic)
  local tag = M.lookup(topic)
  if not tag then return paw.notify("no help for " .. tostring(topic), "warn") end
  return M.jump(tag)
end

--- Back along the tags followed (`Ctrl-t`).
function M.back(n)
  local win
  for _ = 1, n or 1 do
    local last = table.remove(stack)
    if not last then
      if not win then paw.notify("at the bottom of the tag stack", "warn") end
      return win
    end
    local source = source_of({ name = last.name })
    if source then win = M.show(source, last.row, last.col) end
  end
  return win
end

--- Where a link's target leads from a page: a tag (`help:tag`), another
--- page (`mixing.md`, `../docs/reference/ex.md#flags`), or a place on the web.
local function link_target(source, target)
  local tag = target:match("^help:(.+)$")
  if tag then return build().tags[tag] end
  if target:match("^%a+:") then return nil, target end
  local path, frag = target:match("^([^#]*)#?(.*)$")
  local dest = source
  if path ~= "" then
    if not source.path then return nil end
    dest = build().by_path[normalize(dir_of(source.path) .. "/" .. path)]
    if not dest then return nil, path end
  end
  local row = frag ~= "" and dest.anchors[frag] or 1
  return { name = frag, source = dest, row = row, col = 0 }
end

--- The word under the cursor as help reads it: the run of characters that
--- are not blanks, `*`, `|` or `"`.
local function word_at(text, col)
  local chars = {}
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
  local function part(ch) return ch and not ch:match("^[%s%*|\"]$") end
  local i = col + 1
  if not part(chars[i]) then return nil end
  local a, b = i, i
  while part(chars[a - 1]) do a = a - 1 end
  while part(chars[b + 1]) do b = b + 1 end
  return table.concat(chars, "", a, b)
end

--- Look a word up: as written, then without the punctuation around it.
local function lookup_word(word)
  local tags = build().tags
  local tries = { word, (word:gsub("[%.,;:!%?%)%]}]+$", "")), (word:gsub("^[%(%[{]+", ""):gsub("[%.,;:!%?%)%]}]+$", "")) }
  for _, w in ipairs(tries) do
    if tags[w] then return tags[w] end
  end
  for _, w in ipairs(tries) do
    if w ~= "" then
      local tag = M.lookup(w)
      if tag then return tag end
    end
  end
end

--- What is under the cursor of a help window: a link, code, or a word.
local function under_cursor()
  local win, buf, t, s = paw.textbuf.here()
  if not (win and is_help(buf)) then return nil end
  local source = source_of(buf)
  local line = source and source.doc.lines[s.row]
  if line then
    for _, link in ipairs(line.links) do
      if s.col >= link[1] and s.col < link[2] then return { link = link[3], source = source } end
    end
    for _, code in ipairs(line.codes) do
      if s.col >= code[1] and s.col < code[2] then return { code = code[3], source = source } end
    end
  end
  return { word = word_at(t:line(s.row), s.col), source = source }
end

--- `Ctrl-]`: follow the link under the cursor, or find the code or the word there.
function M.follow()
  local here = under_cursor()
  if not here then return paw.notify("Ctrl-] follows links in help: `:help` opens it", "warn") end
  if here.link then
    local tag, other = link_target(here.source, here.link)
    if tag then return M.jump(tag) end
    return paw.notify(other and ("not a page of help: " .. other) or "the link leads nowhere", "warn")
  end
  local text = here.code or here.word
  if not text then return end
  local tag
  if here.code then
    for _, name in ipairs(tags_of_code(text, true)) do tag = tag or build().tags[name] end
  end
  tag = tag or lookup_word(text)
  if not tag then return paw.notify("no help for " .. text, "warn") end
  return M.jump(tag)
end

--- `K`: find the word under the cursor in help. It works in a page of help and in other text.
function M.keyword()
  local win, buf, t, s = paw.textbuf.here()
  if not win then return end
  local here = is_help(buf) and under_cursor() or { word = word_at(t:line(s.row), s.col) }
  local text = here.code or here.word
  if not text then return end
  local tag = lookup_word(text)
  if not tag then return paw.notify("no help for " .. text, "warn") end
  return M.jump(tag)
end

--- `:helpgrep`: every line of help that holds the words, in the quickfix list.
function M.grep(pattern)
  pattern = (pattern or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if pattern == "" then return paw.notify("usage: helpgrep words", "warn") end
  -- Case counts only when the words have a capital, as with 'smartcase'.
  local fold = not pattern:find("%u")
  local needle = fold and pattern:lower() or pattern
  local entries = {}
  for _, source in ipairs(build().sources) do
    for row, line in ipairs(source.doc.lines) do
      local text = fold and line.text:lower() or line.text
      local at = text:find(needle, 1, true)
      if at then
        entries[#entries + 1] = {
          location = { uri = "paw://help/" .. source.name, selector = { line = row, col = md.width(line.text:sub(1, at - 1)) } },
          text = (line.text:gsub("^%s+", "")), source = "helpgrep",
        }
      end
    end
  end
  if #entries == 0 then return paw.notify("no help holds " .. pattern, "warn") end
  paw.qf.set(entries, { title = "helpgrep " .. pattern })
  paw.qf.jump(1)
  return entries
end

-- Help as a kind of text buffer, and where its entries in the quickfix list go.
paw.textbuf.kind("help", {
  pattern = "^help://(.+)$",
  readonly = "help cannot be changed: its pages are the Markdown files under docs/ and in the extensions",
  gutter = false,
  static = true,
  read = function(ctx)
    local source = build().by_name[ctx.args[1]]
    if not source then return nil, "no page of help " .. tostring(ctx.args[1]) end
    local items = {}
    for i, line in ipairs(source.doc.lines) do items[i] = { id = i, text = line.text } end
    return items
  end,
  format = function(item) return { item.text } end,
  parse = function() return {} end,
  title = function(ctx)
    local source = build().by_name[ctx.args[1]]
    return "Help · " .. (source and source.title or tostring(ctx.args[1]))
  end,
  hint = "Ctrl-] follows a link or looks up the word · Ctrl-o back · K looks up · :helpgrep searches · - contents",
  paint = function(canvas, x, y, text, _, maxw, row, buf)
    local chars = {}
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    canvas:text(x, y, table.concat(chars, "", 1, math.min(#chars, maxw)), "Normal")
    local source = source_of(buf)
    local line = source and source.doc.lines[row]
    if not (line and line.text == text) then return end
    for _, span in ipairs(line.spans) do
      local part = table.concat(chars, "", span[1] + 1, math.min(span[2], maxw, #chars))
      if part ~= "" then canvas:text(x + span[1], y, part, span[3]) end
    end
  end,
  open = function() M.follow() end,
  parent = function(ctx) return ctx.args[1] ~= "index" and "help://index" or nil end,
})

paw.address.scheme("help", {
  resolve = function(uri) return build().by_name[uri:match("^paw://help/(.+)$") or ""] end,
  where = function(loc)
    local name = loc.uri:match("^paw://help/(.+)$") or "?"
    return name .. ":" .. tostring(loc.selector and loc.selector.line or 1)
  end,
  go = function(loc)
    local source = build().by_name[loc.uri:match("^paw://help/(.+)$") or ""]
    if not source then return false end
    local sel = loc.selector or {}
    M.show(source, sel.line or 1, sel.col or 0)
    return true
  end,
})

-- Keys and commands ------------------------------------------------------------------

local map = paw.keymap.set
map("<C-]>", M.follow, { view = "textbuf", desc = "Help: follow the link, or look up the word, under the cursor", repeatable = false })
map("<C-t>", function(ctx) M.back(ctx.count or 1) end, { view = "textbuf", desc = "Help: back to where the last link was followed from", repeatable = false })
map("K", function()
  if is_help(paw.textbuf.buf()) then return M.keyword() end
  paw.commands.run("info")
end, { view = "textbuf", role = "describe", desc = "Look up the word under the cursor in help (`:help`)", repeatable = false })

--- The first line of help that names `text` as code, the manual's first.
local function mention(text)
  for _, source in ipairs(build().sources) do
    for row, line in ipairs(source.doc.lines) do
      for _, code in ipairs(line.codes) do
        if code[3] == text or code[3]:sub(1, #text + 1) == text .. " " then
          return { name = text, source = source, row = row, col = code[1] }
        end
      end
    end
  end
end

--- Where the help of the first of `names` is: a tag, else where it is
--- named. Nil when there is none.
local function place_for(names)
  local tags = build().tags
  for _, name in ipairs(names) do
    if tags[name] then return tags[name] end
  end
  for _, name in ipairs(names) do
    local place = mention(name)
    if place then return place end
  end
end

--- Go to the help of the first of `names` that is a tag, else to where the
--- first of them is named; say so when none is.
local function help_for(names, shown)
  local place = place_for(names)
  if place then return M.jump(place) end
  paw.notify("no help for " .. shown .. ": `:helpgrep " .. shown .. "` searches every page", "warn")
end

local function names_of(map)
  local human = paw.keymap.human(map.lhs)
  local names = { human, map.lhs }
  if type(map.rhs) == "string" then names[#names + 1] = ":" .. map.rhs:match("^%S+") end
  return names, human
end

--- The help for a key mapping: of its keys, else of the command it runs
--- (what `Ctrl-]` does in the keys picker).
function M.for_map(map)
  return help_for(names_of(map))
end

--- A line cut into pieces of at most `width` columns at spaces.
local function wrapped(text, width)
  local out, line = {}, ""
  for word in text:gmatch("%S+") do
    if line ~= "" and api.str_width(line .. " " .. word) > width then
      out[#out + 1], line = line, word
    else
      line = line == "" and word or line .. " " .. word
    end
  end
  out[#out + 1] = line
  return out
end

--- The section of help that `for_map` would go to, as at most `rows` lines
--- `{ text, style }` wrapped to `width`. It is for a pane next to a list of keys.
--- The name of the page comes first. Nil when there is no help for the key.
function M.excerpt_for_map(map, width, rows)
  local place = place_for((names_of(map)))
  if not place then return nil end
  local out = { { text = place.source.title or place.source.name, style = "HelpSection" }, { text = "" } }
  local blank = 0
  for row = place.row, #place.source.doc.lines do
    local text = place.source.doc.lines[row].text
    blank = text:match("%S") and 0 or blank + 1
    if blank == 2 then break end
    for _, part in ipairs(wrapped(text, width)) do
      if #out >= rows then return out end
      out[#out + 1] = { text = part }
    end
  end
  return out
end

--- The help for a command (what `Ctrl-]` does in the commands picker).
function M.for_command(name)
  return help_for({ ":" .. name, name }, ":" .. name)
end

-- The key line of a help window: its own keys, not those that edit.
local text_keys = paw.ui.keybar.lines.textbuf and paw.ui.keybar.lines.textbuf.n
paw.ui.keybar.set("textbuf", "n", function()
  if is_help(paw.textbuf.buf()) then
    return {
      { "<C-]>", "follow" }, { "<C-t>", "back" }, { "K", "look up" }, { "-", "contents" }, { "v", "select" }, { "y", "yank" },
      { "?", "keys" },
    }
  end
  return type(text_keys) == "function" and text_keys() or text_keys or {}
end)

paw.command("helpgrep", function(ctx) M.grep(ctx.args[1]) end, {
  desc = "Every line of help that holds the words, in the quickfix list: `helpgrep stretch`",
  raw = true,
})

--- What `:help` completes: the tags, ranked as `:help` ranks them.
function M.complete(rest)
  local out = { ranked = true }
  if not rest:match("%S") then return out end
  for _, tag in ipairs(M.find(rest, 200)) do out[#out + 1] = { text = tag.name, desc = tag.source.title or tag.source.name } end
  return out
end

--- The topic of help for a view, for the key line: its `help` field, a
--- section of the manual, or the page of its extension.
function M.topic_of(view)
  if view == "textbuf" and is_help(paw.textbuf.buf()) then return "help" end
  local v = paw.ui.views[view]
  if v and v.help then return v.help end
  return M.view_topics[view] or (paw.ext.loaded[view] and view) or nil
end

M.view_topics = {
  arrange = "arrange-view", pianoroll = "piano-roll", mixer = "mixer", devices = "device-panel",
  textbuf = "lists-edited-as-text", qflist = "quickfix-list",
}

return M
