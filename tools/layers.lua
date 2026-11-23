-- The check of the order of layers in the runtime (runtime/lua/paw). It reads
-- the `require` calls and the `paw.x` references of each module, and fails on
-- a reference from a lower layer to a higher layer that is not on the
-- allow-list. It reads text only, so plain LuaJIT runs it (the flake's
-- `layers` check), and so does paw (the suite's tests/layers.lua).
--
--   luajit tools/layers.lua          check the runtime against the two lists below
--   luajit tools/layers.lua graph    print the graph: one edge on each line (see M.format_graph)
--   luajit tools/layers.lua counts   print the upward references of today, in the format of the allow-list
--
-- tools/layers.txt gives the layers, from low to high, and the modules in
-- each layer. tools/layers-allowed.txt holds one line `<from> <to> <count>`
-- for each upward reference that is there today. A count that goes up
-- fails. A count that goes down also fails, until its line is made smaller,
-- so the list only gets shorter. .claude/skills/paw-code/layers.md tells why
-- the layers are what they are and how to remove an upward reference.
local M = {}

M.RUNTIME = "runtime/lua"
M.TYPES = "runtime/types"
M.LAYERS = "tools/layers.txt"
M.ALLOWED = "tools/layers-allowed.txt"

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function lines_of(cmd)
  local out = {}
  local pipe = assert(io.popen(cmd))
  for line in pipe:lines() do
    out[#out + 1] = line
  end
  pipe:close()
  return out
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

-- The modules ---------------------------------------------------------------------

--- The modules of the runtime under `root`: `{ [name] = file }`, with the
--- file relative to `root`. `paw/x/init.tl` is the module `paw.x`. A
--- declaration of runtime/types/paw (`paw.api`, the kernel, and the types
--- that tools/apidoc.lua makes) is a module too, with its `.d.tl` file: other
--- modules read it, but it reads nothing (M.graph does not scan it).
function M.modules(root)
  local modules = {}
  local function add(folder, pattern)
    local cmd = "cd '" .. root .. "/" .. folder .. "' 2>/dev/null && find paw " .. pattern .. " | sort"
    for _, path in ipairs(lines_of(cmd)) do
      local name = path:gsub("%.d%.tl$", ""):gsub("%.tl$", ""):gsub("%.lua$", ""):gsub("/", "."):gsub("%.init$", "")
      modules[name] = modules[name] or folder .. "/" .. path
    end
  end
  add(M.RUNTIME, "\\( -name '*.lua' -o -name '*.tl' \\) ! -name '*.d.tl'")
  add(M.TYPES, "-name '*.d.tl'")
  return modules
end

-- The text of a module ----------------------------------------------------------

--- The code of a Lua or Teal file with its comments made blank and each
--- string replaced by `"<n>"`, where `strings[n]` is its text. The lines
--- stay where they are, so a position in the code is a position in the file.
function M.strip(text)
  local out, strings = {}, {}
  local i, n = 1, #text
  -- The level of a long bracket at `at` (`[[` is "", `[==[` is "=="), or nil.
  local function long_open(at) return text:match("^%[(=*)%[", at) end
  -- The end of the long bracket of level `eqs` that opens before `from`.
  local function long_close(eqs, from) return select(2, text:find("]" .. eqs .. "]", from, true)) or n end
  -- A comment keeps its newlines and its columns, a long string only its newlines.
  local function blank(part) return (part:gsub("[^\n]", " ")) end
  local function newlines(part) return (part:gsub("[^\n]", "")) end
  while i <= n do
    local c = text:sub(i, i)
    local eqs = c == "[" and long_open(i)
    if c == "-" and text:sub(i + 1, i + 1) == "-" then
      local level = long_open(i + 2)
      local stop = level and long_close(level, i + 4 + #level) or (text:find("\n", i, true) or n + 1) - 1
      out[#out + 1] = blank(text:sub(i, stop))
      i = stop + 1
    elseif eqs then
      local stop = long_close(eqs, i + 2 + #eqs)
      strings[#strings + 1] = text:sub(i + 2 + #eqs, stop - 2 - #eqs)
      out[#out + 1] = '"' .. #strings .. '"' .. newlines(text:sub(i, stop))
      i = stop + 1
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = text:sub(j, j)
        if d == "\\" then
          j = j + 2
        elseif d == c or d == "\n" then
          break
        else
          j = j + 1
        end
      end
      strings[#strings + 1] = text:sub(i + 1, j - 1)
      out[#out + 1] = '"' .. #strings .. '"'
      i = j + 1
    else
      local stop = (text:find("[%-%[\"']", i) or n + 1) - 1
      if stop < i then stop = i end
      out[#out + 1] = text:sub(i, stop)
      i = stop + 1
    end
  end
  return table.concat(out), strings
end

--- The references of a file's text: a list of `{ name, line, kind }`.
--- `kind` is `require` for `require("paw.x")` (also through a cast:
--- `(require as function(string): X)("paw.x")`), `type` for `local type X =
--- require("paw.x")`, and `paw` for a `paw.x.y` in the code (also through a
--- cast: `(paw.x as T).y`), which the caller resolves to a module.
function M.references(text)
  local code, strings = M.strip(text)
  local refs = {}
  local line = 0
  for row in (code .. "\n"):gmatch("(.-)\n") do
    line = line + 1
    -- `require`, then the first string after it on the line.
    local at = 1
    while true do
      local s, e = row:find("%f[%w_]require%f[^%w_]", at)
      if not s then break end
      local index = row:match('^[^"]-"(%d+)"', e + 1)
      local name = index and strings[tonumber(index)]
      if name and name:match("^paw[%w_%.]*$") then
        name = name:gsub("%.$", "")
        local kind = row:sub(1, s - 1):match("local%s+type%s+[%w_]+%s*=%s*$") and "type" or "require"
        refs[#refs + 1] = { name = name, line = line, kind = kind }
      end
      at = e + 1
    end
    -- `paw.x.y`, not `t.paw.x` and not `require("paw.x")` (a string).
    -- A Teal cast, `(paw.x as T).y`, reads `paw.x.y`.
    for start, name, stop in row:gmatch("()(paw%.[%a_][%w_%.]*)()") do
      if start == 1 or not row:sub(start - 1, start - 1):match("[%w_%.:]") then
        local field = row:match("^%s+as%s+[^()]-%)%.([%a_][%w_]*)", stop)
        name = name:gsub("%.$", "") .. (field and "." .. field or "")
        refs[#refs + 1] = { name = name, line = line, kind = "paw" }
      end
    end
  end
  return refs
end

-- Names of `paw` to modules ------------------------------------------------------

--- The owner of each name that a module puts in `paw`: `{ ["paw.x"] =
--- module }`.
---
--- - `paw.x = require("m")` gives `m`.
--- - `paw.x = paw.y.z` gives the owner of `paw.y.z`, and `paw.x = m.y` the
---   owner of `m.y`, where `m` is a local of `require("m")`.
--- - `function paw.x(` and other `paw.x = ...` give the module of the file.
---
--- A line can set several names: `paw.on, paw.off = events.on, events.off`.
function M.names(root, modules)
  local names, copies = {}, {}
  for _, module in ipairs(sorted_keys(modules)) do
    local code, strings = M.strip(read(root .. "/" .. modules[module]) or "")
    local locals = {}
    for name, index in code:gmatch('local%s+([%w_]+)%s*=%s*require%s*%(?%s*"(%d+)"') do
      locals[name] = strings[tonumber(index)]
    end
    -- What one value on the right of `=` copies: a `paw.y.z`, or the name of
    -- a field of a required module. Nil for any other value.
    local function copied(value)
      if value:match("^paw%.[%w_%.]+$") then return value end
      local head, rest = value:match("^([%w_]+)(%.?[%w_%.]*)$")
      return head and locals[head] and locals[head] .. rest
    end
    for row in (code .. "\n"):gmatch("(.-)\n") do
      local left, right = row:match("^%s*(paw%.[%w_]+[%w_%.,%s]*)=([^=].-)%s*$")
      if not left then left = row:match("^%s*function%s+(paw%.[%w_]+)%s*%(") end
      if left then
        local values = {}
        for value in (right or ""):gmatch("[^,]+") do
          values[#values + 1] = value:match("^%s*(.-)%s*$")
        end
        local i = 0
        for name in left:gmatch("paw%.[%w_]+") do
          i = i + 1
          local value = values[i] or ""
          local index = value:match('^require%s*%(?%s*"(%d+)"')
          local copy = copied(value)
          if index then
            names[name] = strings[tonumber(index)]
          elseif copy and copy ~= name then
            copies[name] = copy
          elseif not names[name] then
            names[name] = module
          end
        end
      end
    end
  end
  -- A copy goes to the owner of what it copies. A copy can copy a copy, so
  -- each round resolves one more step.
  for _ = 1, 3 do
    for name, copy in pairs(copies) do
      local owner = M.resolve(copy, modules, names)
      if owner then names[name] = owner end
    end
  end
  return names
end

--- The module that `name` (`paw.x.y.z`) reads, or nil, and the prefix of
--- `name` that names it: the longest prefix that is a module or a name that a
--- module owns. `paw` alone is the global table, not paw/init.lua.
--- `paw.ui.views.<view>` is the view module (the views register themselves
--- in `paw.ui.views`).
function M.resolve(name, modules, names)
  local view = name:match("^paw%.ui%.views%.([%w_]+)")
  if view and modules["paw.views." .. view] then return "paw.views." .. view, "paw.ui.views." .. view end
  local prefix = name
  while prefix and prefix ~= "paw" do
    if modules[prefix] then return prefix, prefix end
    if names[prefix] then return names[prefix], prefix end
    prefix = prefix:match("^(.+)%.[^%.]+$")
  end
  return nil
end

-- The layers --------------------------------------------------------------------

-- Whether `module` is under `prefix`: `paw.x.y` is under `paw.x`, `paw.x` is not.
local function is_under(module, prefix) return module:sub(1, #prefix + 1) == prefix .. "." end

--- The layers of tools/layers.txt: `{ order = { layer names }, layer = {
--- [layer] = { index, line } }, exact = { [module] = entry }, prefixes = {
--- entries } }`, where an entry is `{ module, layer, line }`. A line
--- `[name]` starts a layer. A line `paw.x` puts that module in the layer, and
--- `paw.x.*` each module under `paw.x`. Or nil and an error.
function M.read_layers(path)
  local text = read(path)
  if not text then return nil, path .. " is missing" end
  local layers = { order = {}, layer = {}, exact = {}, prefixes = {} }
  local current
  local n = 0
  for row in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local line = row:gsub("%s*#.*$", ""):match("^%s*(.-)%s*$")
    if line ~= "" then
      local layer = line:match("^%[([%w_%-]+)%]$")
      local prefix = line:match("^(paw[%w_%.]*)%.%*$")
      if layer then
        layers.order[#layers.order + 1] = layer
        layers.layer[layer] = { index = #layers.order, line = n }
        current = layer
      elseif not current then
        return nil, string.format("%s:%d: a module before the first `[layer]`: %s", path, n, line)
      elseif prefix then
        table.insert(layers.prefixes, { module = prefix, layer = current, line = n })
      elseif line:match("^paw[%w_%.]*$") then
        layers.exact[line] = { module = line, layer = current, line = n }
      else
        return nil, string.format("%s:%d: not `[layer]`, `paw.x` or `paw.x.*`: %s", path, n, line)
      end
    end
  end
  -- The longest prefix wins.
  table.sort(layers.prefixes, function(a, b) return #a.module > #b.module end)
  return layers
end

--- The entry of tools/layers.txt that gives `module` its layer, or nil.
function M.layer_of(layers, module)
  if layers.exact[module] then return layers.exact[module] end
  for _, entry in ipairs(layers.prefixes) do
    if is_under(module, entry.module) then return entry end
  end
  return nil
end

-- The graph ---------------------------------------------------------------------

--- The graph of the runtime at `root`: `{ modules, edges }`. `edges[from][to]`
--- is `{ count, names = { [name] = true }, kinds = { [kind] = count }, line }`.
---
--- `names` holds the distinct names that `from` reads of `to`: the prefix
--- that names `to` and one more part (`paw.ui.notify`,
--- `paw.ui.views.pianoroll.state`). A `require` gives the name of the module.
--- The name of the module stays only when it is the only one: a `local type
--- X = require("paw.x")` next to reads of `paw.x.y` adds no name, so a type
--- that replaces a stand-in record costs nothing. `count` is the number of
--- names, so one more use of a name that `from` reads already does not
--- change it.
---
--- `line` is the first line in `from`'s file that reads `to`. A module that
--- reads itself is no edge. A declaration (`.d.tl`) is not read.
function M.graph(root)
  local modules = M.modules(root)
  local names = M.names(root, modules)
  local edges = {}
  for _, from in ipairs(sorted_keys(modules)) do
    local file = modules[from]
    local refs = file:match("%.d%.tl$") and {} or M.references(read(root .. "/" .. file) or "")
    for _, ref in ipairs(refs) do
      local to, prefix = M.resolve(ref.name, modules, names)
      if to and to ~= from then
        local name = ref.name:match("^" .. prefix:gsub("%p", "%%%0") .. "%.?[%w_]*")
        edges[from] = edges[from] or {}
        local edge = edges[from][to]
        if not edge then
          edge = { count = 0, names = {}, kinds = {}, line = ref.line }
          edges[from][to] = edge
        end
        edge.names[name] = true
        edge.kinds[ref.kind] = (edge.kinds[ref.kind] or 0) + 1
      end
    end
  end
  -- The name of the module goes when other names are there.
  for _, targets in pairs(edges) do
    for to, edge in pairs(targets) do
      if next(edge.names, next(edge.names)) then edge.names[to] = nil end
      edge.count = #sorted_keys(edge.names)
    end
  end
  return { modules = modules, edges = edges }
end

--- The layer index of a module, or nil.
local function index_of(layers, module)
  local entry = M.layer_of(layers, module)
  return entry and layers.layer[entry.layer].index
end

--- The graph as text, one edge on each line, sorted, for other tools (the
--- architecture map of the architecture map reads it):
---
---   <from> <to> <count> <kinds> <from layer> <to layer> <up|down|same> <file>:<line>
---
--- `<kinds>` is `require=2,paw=5` (sorted). A module with no layer has the
--- layer `-`.
function M.format_graph(graph, layers)
  local out = {}
  for _, from in ipairs(sorted_keys(graph.edges)) do
    for _, to in ipairs(sorted_keys(graph.edges[from])) do
      local edge = graph.edges[from][to]
      local kinds = {}
      for _, kind in ipairs(sorted_keys(edge.kinds)) do
        kinds[#kinds + 1] = kind .. "=" .. edge.kinds[kind]
      end
      local a, b = M.layer_of(layers, from), M.layer_of(layers, to)
      local ia, ib = index_of(layers, from), index_of(layers, to)
      local direction = (not ia or not ib) and "-" or ib > ia and "up" or ib < ia and "down" or "same"
      out[#out + 1] = string.format(
        "%s %s %d %s %s %s %s %s:%d",
        from,
        to,
        edge.count,
        table.concat(kinds, ","),
        a and a.layer or "-",
        b and b.layer or "-",
        direction,
        graph.modules[from],
        edge.line
      )
    end
  end
  return table.concat(out, "\n") .. "\n"
end

--- The upward references: `{ [from] = { [to] = count } }`.
function M.upward(graph, layers)
  local up = {}
  for from, targets in pairs(graph.edges) do
    for to, edge in pairs(targets) do
      local ia, ib = index_of(layers, from), index_of(layers, to)
      if ia and ib and ib > ia then
        up[from] = up[from] or {}
        up[from][to] = edge.count
      end
    end
  end
  return up
end

-- The allow-list ------------------------------------------------------------------

--- The lines of the allow-list as `{ [from] = { [to] = { count, line } } }`,
--- or nil and an error.
function M.read_allowed(path)
  local text = read(path)
  if not text then return nil, path .. " is missing" end
  local allowed = {}
  local n = 0
  for row in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    if not (row:match("^%s*#") or row:match("^%s*$")) then
      local from, to, count = row:match("^(%S+) (%S+) (%d+)$")
      if not from then return nil, string.format("%s:%d: not `<from> <to> <count>`: %s", path, n, row) end
      allowed[from] = allowed[from] or {}
      allowed[from][to] = { count = tonumber(count), line = n }
    end
  end
  return allowed
end

--- The lines of the allow-list for `up` (from M.upward), sorted.
function M.format_allowed(up)
  local out = {}
  for _, from in ipairs(sorted_keys(up)) do
    for _, to in ipairs(sorted_keys(up[from])) do
      out[#out + 1] = string.format("%s %s %d", from, to, up[from][to])
    end
  end
  return table.concat(out, "\n") .. "\n"
end

--- The sum of the counts of an allow-list (from M.read_allowed).
function M.total(allowed)
  local sum = 0
  for _, targets in pairs(allowed) do
    for _, entry in pairs(targets) do
      sum = sum + entry.count
    end
  end
  return sum
end

-- The check ---------------------------------------------------------------------

--- The problems of the tree at `root` (default "."): a list of lines, empty
--- when the layers, the allow-list and the code agree. Each problem names the
--- line of tools/layers.txt or tools/layers-allowed.txt to change.
function M.check(root)
  root = root or "."
  local layers, err = M.read_layers(root .. "/" .. M.LAYERS)
  if not layers then return { err } end
  local allowed, err2 = M.read_allowed(root .. "/" .. M.ALLOWED)
  if not allowed then return { err2 } end
  local graph = M.graph(root)
  local problems = {}
  local function add(...) problems[#problems + 1] = string.format(...) end

  -- Each module has a layer, and each line of the layers names a module.
  for _, module in ipairs(sorted_keys(graph.modules)) do
    if not M.layer_of(layers, module) then
      add(
        "%s: %s has no layer: add the line `%s` under the right `[layer]` of %s",
        graph.modules[module],
        module,
        module,
        M.LAYERS
      )
    end
  end
  local function has_modules_under(prefix)
    for module in pairs(graph.modules) do
      if is_under(module, prefix) then return true end
    end
    return false
  end
  for _, entry in pairs(layers.exact) do
    if not graph.modules[entry.module] then
      add("%s:%d: no module `%s` now: remove the line", M.LAYERS, entry.line, entry.module)
    end
  end
  for _, entry in ipairs(layers.prefixes) do
    if not has_modules_under(entry.module) then
      add("%s:%d: no module under `%s` now: remove the line", M.LAYERS, entry.line, entry.module)
    end
  end

  -- More upward references than the list allows.
  local up = M.upward(graph, layers)
  for from, targets in pairs(up) do
    for to, n in pairs(targets) do
      local limit = allowed[from] and allowed[from][to] and allowed[from][to].count or 0
      if n > limit then
        local a, b = M.layer_of(layers, from), M.layer_of(layers, to)
        local entry = allowed[from] and allowed[from][to]
        local where = entry and string.format("%s:%d", M.ALLOWED, entry.line) or M.ALLOWED
        add(
          "%s:%d: %s (layer %s, %s:%d) reads %d names of %s (layer %s, %s:%d), %d allowed: %s."
            .. " Give %s what it needs through an event or a callback."
            .. " If %s belongs higher, move %s:%d."
            .. " If the names moved here from another module, move their count to the line `%s %s %d` of %s",
          graph.modules[from],
          graph.edges[from][to].line,
          from,
          a.layer,
          M.LAYERS,
          a.line,
          n,
          to,
          b.layer,
          M.LAYERS,
          b.line,
          limit,
          table.concat(sorted_keys(graph.edges[from][to].names), ", "),
          from,
          from,
          M.LAYERS,
          a.line,
          from,
          to,
          n,
          where
        )
      end
    end
  end

  -- Fewer than the list allows: the list gets shorter with the code.
  for from, targets in pairs(allowed) do
    for to, entry in pairs(targets) do
      local n = up[from] and up[from][to] or 0
      if n < entry.count then
        if n == 0 then
          add("%s:%d: no upward `%s %s` now: remove the line", M.ALLOWED, entry.line, from, to)
        else
          add("%s:%d: %d now: make the line `%s %s %d`", M.ALLOWED, entry.line, n, from, to, n)
        end
      end
    end
  end
  table.sort(problems)
  return problems, M.total(allowed)
end

-- Run as a program ---------------------------------------------------------------------

if arg and arg[0] and arg[0]:match("layers%.lua$") then
  local layers, err = M.read_layers(M.LAYERS)
  if arg[1] == "graph" or arg[1] == "counts" then
    if not layers then
      io.stderr:write(err, "\n")
      os.exit(1)
    end
    local graph = M.graph(".")
    io.write(arg[1] == "graph" and M.format_graph(graph, layers) or M.format_allowed(M.upward(graph, layers)))
    os.exit(0)
  end
  local problems, total = M.check(".")
  for _, line in ipairs(problems) do
    print(line)
  end
  if #problems > 0 then
    print(string.format("layers: %d problems", #problems))
    os.exit(1)
  end
  print(string.format("layers: no upward reference beyond the %d of %s", total, M.ALLOWED))
end

return M
