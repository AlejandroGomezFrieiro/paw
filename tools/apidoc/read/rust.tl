-- The reader of the Rust source: the functions of `paw.api` with the types
-- of their arguments and their `//` comments, and the records of the data
-- that crosses to Lua (the `pub struct`s that serde reads or writes, and the
-- variants of the `pub enum`s), with their `///` comments.
--
-- It reads the text with patterns. When the kernel describes its API from
-- typed structs, a reader of that description fills the same records of the
-- model, and this one gets smaller.
local api = require("paw.api")
local model = require("apidoc.model")
local source = require("apidoc.source")

local type KernelFunction = model.KernelFunction
local type Param = model.Param
local type Type = model.Type
local type Field = model.Field
local type Record = model.Record

local record rust
  --- The files that define `paw.api` with `define!`: mod.rs and one file
  --- for each area, by name.
  API_DIR: string
  --- The other files that add functions to `paw.api`, each with
  --- `api.set("name", lua.create_function(guarded!("name", |lua, args:
  --- Types| ...)))` (or tempo_api.rs's `reader!` and `nest_reader!`, whose
  --- closures leave out the first argument, `clip`) under its `//` comment.
  KERNEL_FILES: {string}
end

rust.API_DIR = "crates/paw-core/src/api"
rust.KERNEL_FILES = {
  "crates/paw-core/src/fs_api.rs",
  "crates/paw-core/src/tempo_api.rs",
  "crates/paw-core/src/luadev_api.rs",
  "crates/paw-core/src/scene.rs",
  "crates/paw-core/src/measure/mod.rs",
}

--- Split `text` at the commas that are not inside `()` or `<>`.
function rust.split_top(text: string): {string}
  local list: {string} = {}
  local depth, cur = 0, ""
  for ch in text:gmatch(".") do
    if ch == "<" or ch == "(" then
      depth = depth + 1
    elseif ch == ">" or ch == ")" then
      depth = depth - 1
    end
    if ch == "," and depth == 0 then
      list[#list + 1] = cur
      cur = ""
    else
      cur = cur .. ch
    end
  end
  if cur:match("%S") then
    list[#list + 1] = cur
  end
  return list
end

--- The type that a Rust type's text spells: `Option<T>`, `Vec<T>` and a
--- slice `&'a [T]`, a tuple `(A, B)`, else a named type (`String`, `Id`,
--- `HashMap<String, BString>`), by its text.
function rust.type_of(text: string): Type
  local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
  local inner = trimmed:match("^Option<(.*)>$")
  if inner then
    return {kind = "optional", text = text, of = rust.type_of(inner)}
  end
  local list = trimmed:match("^Vec<(.*)>$") or trimmed:match("^&'a %[(.*)%]$")
  if list then
    return {kind = "list", text = text, of = rust.type_of(list)}
  end
  local tuple = trimmed:match("^%((.*)%)$")
  if tuple then
    local items: {Type} = {}
    for i, part in ipairs(rust.split_top(tuple)) do
      items[i] = rust.type_of(part)
    end
    return {kind = "tuple", text = text, items = items}
  end
  return {kind = "named", text = trimmed}
end

-- A kernel function from its argument pattern (`(a, b)`, `a`, `()`), their
-- Rust types (`(String, f64)`, `String`) and the lines of its comment: the
-- prose, and the types of its `@param`, `@return` and `@type` lines.
local function kernel_function(name: string, args: string, types: string, comment: {string}): KernelFunction
  local names: {string} = {}
  if args ~= "()" then
    for p in args:gsub("^%(", ""):gsub("%)$", ""):gmatch("[%w_]+") do
      names[#names + 1] = p
    end
  end
  local listed = rust.split_top(types:match("^%((.*)%)$") or types)
  local f: KernelFunction = {name = name, params = {}, doc = {}, forms = {}}
  local typed: {string: Param} = {}
  for i, p in ipairs(names) do
    -- An argument the pattern names and the types do not: a Lua value.
    f.params[i] = {name = p, type = rust.type_of(listed[i] or "LuaValue")}
    typed[p] = f.params[i]
  end
  for _, line in ipairs(comment) do
    local form = line:match("^@type%s+(function.+)$")
    if form then
      f.forms[#f.forms + 1] = form
    end
    local p, opt, t = line:match("^@param%s+([%w_]+)(%??)%s+(.+)$")
    if p and typed[p] then
      typed[p].teal, typed[p].optional = t, opt == "?"
    end
    f.returns = line:match("^@return%s+(.+)$") or f.returns
    if not line:match("^@") then
      f.doc[#f.doc + 1] = line
    end
  end
  return f
end

-- The functions that a file of `KERNEL_FILES` adds, into `out`.
local function kernel_file(path: string, out: {string: KernelFunction})
  local lines = source.lines(path) or {}
  for i, line in ipairs(lines) do
    local name = line:match('^%s*"([%w_]+)",%s*$') or line:match('^%s*[%w_]*reader!%(lua, api, shared, "([%w_]+)"')
    if name and type((api as {string: any})[name]) == "function" and not out[name] then
      -- The closure's arguments: the last one, `pattern: Types`.
      local text = table.concat(lines, " ", i, math.min(i + 3, #lines))
      local closure = text:match('"' .. name .. '",.-|([^|]*)|')
      local args, types = "()", "()"
      local parts = closure and rust.split_top(closure)
      local last = parts and parts[#parts]
      if last and last:find(":") then
        args, types = last:match("^%s*(.-)%s*:%s*(.-)%s*$")
      end
      -- A `nest_reader` passes its first argument, the block, before them.
      if line:match("nest_reader!%(") or (lines[i - 4] or ""):match("^%s*nest_reader!%($") then
        local function first(list: string, item: string): string
          local inner = list:match("^%((.*)%)$") or list
          return "(" .. item .. (inner ~= "" and (", " .. inner) or "") .. ")"
        end
        args, types = first(args, "clip"), first(types, "Id")
      end
      -- The comment over it, past the lines that start the call.
      local n = i - 1
      while
        n > 0
        and (
          lines[n]:match("^%s*api%.set%($")
          or lines[n]:match("^%s*[%w_]*reader!%($")
          or lines[n]:match("^%s*lua,%s*$")
          or lines[n]:match("^%s*api,%s*$")
          or lines[n]:match("^%s*shared,%s*$")
          or lines[n]:match("^%s*let .*;%s*$")
        )
      do
        n = n - 1
      end
      local comment: {string} = {}
      while n > 0 and lines[n]:match("^%s*//") and not lines[n]:match("^%s*//!") do
        table.insert(comment, 1, (lines[n]:gsub("^%s*// ?", "")))
        n = n - 1
      end
      out[name] = kernel_function(name, args, types, comment)
    end
  end
end

--- The `paw.api` functions as api/ and `KERNEL_FILES` show them, by name.
function rust.kernel_functions(): {string: KernelFunction}
  local out: {string: KernelFunction} = {}
  local files: {string} = {}
  for _, entry in ipairs(api.read_dir(rust.API_DIR)) do
    if not entry.is_dir and entry.name:match("%.rs$") then
      files[#files + 1] = rust.API_DIR .. "/" .. entry.name
    end
  end
  for _, path in ipairs(files) do
    local comment: {string} = {}
    for _, line in ipairs(source.lines(path) or {}) do
      local name, args, types = line:match("^%s+fn ([%w_]+)%([%w_]+, [%w_]+, (.-) => (.-)%)%s*{")
      if name then
        out[name] = kernel_function(name, args, types, comment)
        comment = {}
      elseif line:match("^%s+//") then
        comment[#comment + 1] = (line:gsub("^%s+// ?", ""))
      elseif not line:match("^%s*$") or #comment > 0 then
        comment = {}
      end
    end
  end
  for _, path in ipairs(rust.KERNEL_FILES) do
    kernel_file(path, out)
  end
  return out
end

-- The prose of a field's comment, and the type of its `@type T` line.
local function typed(item: Field)
  local prose: {string} = {}
  for _, line in ipairs(item.doc) do
    local t = line:match("^@type%s+(.+)$")
    if t then
      item.teal = t
    else
      prose[#prose + 1] = line
    end
  end
  item.doc = prose
end

--- The `pub struct`s of a Rust file that serde writes or reads (also
--- `pub(crate)`), in order, and the variants of its `pub enum`s, by the
--- enum's name.
function rust.records(path: string): model.RustFile
  local records: {Record} = {}
  local enums: {string: {Field}} = {}
  local doc: {string} = {}
  local serde: string
  local derive = ""
  local current: Record
  local enum: {Field}
  for _, raw in ipairs(source.lines(path) or {}) do
    -- An item private to the crate (`pub(crate)`, `pub(super)`) crosses to
    -- Lua as a `pub` item does.
    local line = raw:gsub("^(%s*)pub%(%w+%) ", "%1pub ")
    local comment = line:match("^%s*///%s?(.*)$")
    if comment then
      doc[#doc + 1] = comment
    elseif line:match("^%s*#%[") then
      serde = line:match('rename%s*=%s*"([^"]+)"') or serde
      derive = line:match("^%s*#%[derive%((.*)%)%]") or derive
    else
      local name, rest = line:match("^pub struct ([%w_]+)[^{]*{(.*)$")
      local ename = line:match("^pub enum ([%w_]+)")
      if name then
        -- Only what crosses to Lua: a struct that serde writes or reads.
        current = {name = name, doc = doc, fields = {}}
        if derive:match("Serialize") or derive:match("Deserialize") then
          records[#records + 1] = current
        end
        if rest:match("}") then
          current = nil
        end
      elseif ename then
        enum = {}
        enums[ename] = enum
      elseif line:match("^}") then
        current, enum = nil, nil
      elseif current then
        local fname, text = line:match("^%s+pub ([%w_]+): (.-),?%s*$")
        if fname then
          current.fields[#current.fields + 1] = {name = serde or fname, type = rust.type_of(text), doc = doc}
        end
      elseif enum then
        local vname, text = line:match("^%s+([%w_]+)%((.-)%),%s*$")
        if vname then
          enum[#enum + 1] = {name = vname, type = rust.type_of(text), doc = doc, serde = serde}
        end
      end
      doc, serde = {}, nil
      if not line:match("^%s*$") then
        derive = ""
      end
    end
  end
  for _, r in ipairs(records) do
    for _, f in ipairs(r.fields) do
      typed(f)
    end
  end
  for _, list in pairs(enums) do
    for _, v in ipairs(list) do
      typed(v)
    end
  end
  return {path = path, records = records, enums = enums}
end

return rust
