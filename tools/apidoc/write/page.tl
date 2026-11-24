-- The writer of docs/reference/api.md, the reference that `:help` shows
-- (`:help paw.commands.define`): each public function of the `paw` modules
-- with the comment from its source, then the functions of `paw.api`.
local model = require("apidoc.model")
local names = require("apidoc.names")

local type Function = model.Function

-- A run of prose or of an example in a comment.
local record Run
  code: boolean
  lines: {string}
end

-- How a function is called: `paw.Part:clips(...)` for a method.
local function signature(f: Function): string
  local name = f.method and (f.name:gsub("%.([%w_]+)$", ":%1")) or f.name
  return name .. "(" .. table.concat(f.params or {}, ", ") .. ")"
end

-- The item of a function: its signature and the first prose of its
-- comment, then the rest under it.
local function item(f: Function, add: function(string))
  local doc: {string} = {}
  for _, line in ipairs(f.doc or {}) do
    if not line:match("^@") then
      doc[#doc + 1] = line
    end
  end
  -- Runs of prose and of examples (the lines indented in the comment), in
  -- order. An empty line ends a paragraph of prose.
  local runs: {Run} = {}
  local ended = false
  for _, line in ipairs(doc) do
    local code = line:match("^  ") ~= nil
    local last = runs[#runs]
    if line == "" then
      ended = true
    else
      if not last or last.code ~= code or ended then
        last = {code = code, lines = {}}
        runs[#runs + 1] = last
      end
      ended = false
      last.lines[#last.lines + 1] = code and (line:gsub("^  ", "")) or line
    end
  end
  local first = runs[1] and not runs[1].code and table.remove(runs, 1)
  add("- `" .. signature(f) .. "`" .. (first and ": " .. table.concat(first.lines, " ") or ""))
  for _, run in ipairs(runs) do
    add("")
    if run.code then
      add("  ```lua")
      for _, line in ipairs(run.lines) do
        add("  " .. line)
      end
      add("  ```")
    else
      add("  " .. table.concat(run.lines, " "))
    end
  end
end

local function text(m: model.Model): string
  local out: {string} = {
    "# Lua API reference",
    "",
    "<!-- " .. names.HEADER .. " -->",
    "",
    "Each public function of the `paw` modules, module by module, with the",
    "comment from its source. [Scripts](scripting.md) and",
    "[Extensions](extensions.md) tell how the functions work together. The",
    "functions of the kernel (`paw.api`, plain data in and out) are at the end.",
    "`runtime/types/paw.lua` contains the same data for editors (LuaLS).",
    "",
  }
  local function add(line: string)
    out[#out + 1] = line
  end
  local by_module: {string: {Function}} = {}
  for _, f in ipairs(m.functions) do
    by_module[f.module] = by_module[f.module] or {}
    table.insert(by_module[f.module], f)
  end
  for _, mod in ipairs(m.modules) do
    local list = by_module[mod.name]
    if list then
      add("## Module " .. mod.name)
      add("")
      for _, f in ipairs(list) do
        if f.alias_of then
          add("- `" .. f.name .. "`: the same as `" .. f.alias_of .. "`.")
        else
          item(f, add)
        end
      end
      add("")
    end
  end
  add("## Module paw.api")
  add("")
  for _, name in ipairs(m.kernel.names) do
    local k = m.kernel.functions[name]
    local params = "..."
    if k then
      local list: {string} = {}
      for i, p in ipairs(k.params) do
        list[i] = p.name
      end
      params = table.concat(list, ", ")
    end
    local prose = k and k.doc or {}
    local doc = #prose > 0 and ": " .. table.concat(prose, " ") or ""
    add("- `paw.api." .. name .. "(" .. params .. ")`" .. doc)
  end
  add("")
  return table.concat(out, "\n")
end

local writer: model.Writer = {path = "docs/reference/api.md", text = text}

return writer
