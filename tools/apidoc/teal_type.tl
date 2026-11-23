-- The types of the model in Teal's notation, for the writers of the Teal
-- declarations: the parameters of a kernel function (paw/api.d.tl, and
-- another name of one in paw.d.tl) and the fields of a record of the
-- kernel's data (events/kernel.tl, paw/role_props.d.tl).
local model = require("apidoc.model")
local names = require("apidoc.names")

local type Type = model.Type

local record teal_type
end

-- The Teal type of each named type of an argument of a kernel function.
local KERNEL: {string: string} = {
  String = "string",
  f64 = "number",
  f32 = "number",
  i64 = "integer",
  u64 = "integer",
  u32 = "integer",
  i32 = "integer",
  usize = "integer",
  u8 = "integer",
  u16 = "integer",
  Id = "integer",
  bool = "boolean",
  LuaValue = "any",
  Table = "{any:any}",
  Function = "function(...: any): any...",
  LuaString = "string",
  LuaText = "string",
}

-- The Teal type of each named type of a field of a record.
local FIELD: {string: string} = {
  String = "string",
  PathBuf = "string",
  ["&'a str"] = "string",
  f64 = "number",
  f32 = "number",
  i64 = "integer",
  u64 = "integer",
  u32 = "integer",
  i32 = "integer",
  usize = "integer",
  u8 = "integer",
  Id = "integer",
  bool = "boolean",
}

--- The Teal type of an argument of a kernel function, and whether the
--- argument may be left out (an `Option` at the top). A type Teal has no
--- name for is `any`.
function teal_type.argument(t: Type): string, boolean
  if t.kind == "optional" then
    return (teal_type.argument(t.of)), true
  elseif t.kind == "list" then
    return "{" .. (teal_type.argument(t.of)) .. "}"
  end
  return t.kind == "named" and KERNEL[t.text] or "any"
end

--- The Teal types of a kernel function: of each `@type function(...)` line
--- of its comment, which gives the whole type of each form of a function
--- whose result follows from its arguments (`track_get(id)` and
--- `track_get(id, key)`); else of one form, from the types of its
--- arguments and its `@return` line. With no `@return`, it returns `any...`.
function teal_type.signatures(f: model.KernelFunction): {string}
  if #f.forms > 0 then
    return f.forms
  end
  local params: {string} = {}
  for _, p in ipairs(f.params) do
    local t, optional: string, boolean
    if p.teal then
      t, optional = p.teal, p.optional
    else
      t, optional = teal_type.argument(p.type)
    end
    params[#params + 1] = (names.KEYWORDS[p.name] and p.name .. "_" or p.name) .. (optional and "?: " or ": ") .. t
  end
  local ret = f.returns == nil and ": any..." or (f.returns == "nil" and "" or ": " .. f.returns)
  return {"function(" .. table.concat(params, ", ") .. ")" .. ret}
end

--- The Teal type of a field of a record: a record of the same file by its
--- name (`records`), a list, a tuple as a list of its parts. An `Option`
--- is the type it holds. Nil for a type that has no Teal type.
function teal_type.field(t: Type, records: {string: boolean}): string
  if t.kind == "optional" then
    return teal_type.field(t.of, records)
  elseif t.kind == "list" then
    local inner = teal_type.field(t.of, records)
    return inner and "{" .. inner .. "}"
  elseif t.kind == "tuple" then
    local parts: {string} = {}
    for i, item in ipairs(t.items) do
      parts[i] = teal_type.field(item, records)
      if not parts[i] then
        return nil
      end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  local name = t.text:match("^([%w_]+)") or t.text
  if records[name] then
    return name
  end
  return FIELD[t.text]
end

--- The fields of a record of `file` as Teal lines at `pad`, into `out`, each
--- under its comment; an error for a field whose type has no Teal type and
--- no `/// @type` line.
function teal_type.fields(out: {string}, record: model.Record, pad: string, file: model.RustFile)
  local records: {string: boolean} = {}
  for _, r in ipairs(file.records) do
    records[r.name] = true
  end
  for _, f in ipairs(record.fields) do
    for _, line in ipairs(f.doc) do
      out[#out + 1] = pad .. "--- " .. line
    end
    local t = f.teal or teal_type.field(f.type, records)
    if not t then
      error(
        file.path
          .. ": "
          .. record.name
          .. "."
          .. f.name
          .. " ("
          .. f.type.text
          .. ") has no Teal type: give it a `/// @type` line"
      )
    end
    out[#out + 1] = pad .. (names.KEYWORDS[f.name] and '["' .. f.name .. '"]' or f.name) .. ": " .. t
  end
end

return teal_type
