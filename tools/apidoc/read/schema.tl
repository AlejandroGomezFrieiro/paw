-- The reader of the JSON Schema that the kernel gives of its data
-- (`paw.api.api_schema`, from the Rust types by schemars): a record for
-- each definition with properties and an enum for each definition of
-- string choices, with the Teal type of each field. A definition of one
-- plain value (`NestId`) has no record: a field of it has the Teal type
-- of the value.
--
-- The keyword `x-teal` on a field or a definition gives its Teal type: a
-- name that types.tl defines by hand (`Meta`).
local api = require("paw.api")
local model = require("apidoc.model")

local type Record = model.Record
local type Field = model.Field

--- A schema as JSON gives it. The keys that are not names in Teal
--- (`$ref`, `x-teal`, `enum`) are read through `Keys`.
local record Schema
  type: string | {string}
  description: string
  properties: {string: Schema}
  items: Schema
  const: string
  anyOf: {Schema}
  oneOf: {Schema}
end

local record Keys
  ["$ref"]: string
  ["x-teal"]: string
  choices: {string}
  -- The schema of each value of a map, or true for any value.
  values: Schema | boolean
end

local function keys(s: Schema): Keys
  local words = s as {string: string}
  return {
    ["$ref"] = words["$ref"],
    ["x-teal"] = words["x-teal"],
    choices = (s as {string: {string}})["enum"],
    values = (s as {string: Schema | boolean})["additionalProperties"],
  }
end

local record schema
end

-- The lines of a description.
local function lines(text: string): {string}
  local out: {string} = {}
  if text then
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      out[#out + 1] = line
    end
  end
  return out
end

-- The string choices of a definition: its `enum`, or a `oneOf` of `const`s
-- and `enum`s (schemars puts the choices with no comment in one `enum`).
local function choices(s: Schema): {string}
  local listed = keys(s).choices
  if listed then
    return listed
  elseif s.oneOf then
    local out: {string} = {}
    for _, variant in ipairs(s.oneOf) do
      if variant.const then
        out[#out + 1] = variant.const
      elseif keys(variant).choices then
        for _, value in ipairs(keys(variant).choices) do
          out[#out + 1] = value
        end
      else
        return nil
      end
    end
    return out
  end
  return nil
end

local PLAIN: {string: string} = {
  integer = "integer",
  number = "number",
  boolean = "boolean",
  string = "string",
}

-- The Teal type of a schema; `defs` are the definitions by name.
local function teal_of(s: Schema, defs: {string: Schema}, where: string): string
  local k = keys(s)
  if k["x-teal"] then
    return k["x-teal"]
  elseif k["$ref"] then
    local name = k["$ref"]:match("^#/%$defs/(.+)$")
    local def = defs[name]
    if keys(def)["x-teal"] then
      return keys(def)["x-teal"]
    elseif def.properties or choices(def) then
      return name
    end
    return teal_of(def, defs, where)
  end
  local alternatives = s.anyOf or s.oneOf
  if alternatives then
    local kept: {Schema} = {}
    for _, alternative in ipairs(alternatives) do
      if alternative.type ~= "null" then
        kept[#kept + 1] = alternative
      end
    end
    if #kept == 1 then
      return teal_of(kept[1], defs, where)
    end
    -- A choice of plain types is their union: `boolean | number | string`.
    local union: {string} = {}
    for i, alternative in ipairs(kept) do
      union[i] = PLAIN[alternative.type as string]
      if not union[i] or alternative.properties then
        error(where .. ": a choice of types has no Teal type: give it `x-teal`")
      end
    end
    return table.concat(union, " | ")
  end
  local kind = s.type
  if kind is {string} then
    kind = kind[1] ~= "null" and kind[1] or kind[2]
  end
  if kind == "array" then
    return "{" .. teal_of(s.items, defs, where) .. "}"
  end
  local values = k.values
  if kind == "object" and values is Schema then
    return "{string: " .. teal_of(values, defs, where) .. "}"
  end
  local plain = PLAIN[kind as string]
  if not plain then
    error(where .. ": the JSON type `" .. tostring(kind) .. "` has no Teal type: give it `x-teal`")
  end
  return plain
end

-- The properties of a definition. A definition of a tagged union (serde's
-- `tag` on a flattened enum: `oneOf` of objects) has the properties of
-- each variant too, and its tag (a property that is a `const` in each
-- variant) is a field of an enum of the consts, named by the definition
-- and the tag: `Control` and `type` give `ControlType`. Gives the
-- properties and the enums of the tags.
local function properties_of(name: string, def: Schema): {string: Schema}, {model.SchemaEnum}
  local props: {string: Schema} = {}
  for field, property in pairs(def.properties or {}) do
    props[field] = property
  end
  local tags: {string: {string}} = {}
  local order: {string} = {}
  for _, variant in ipairs(def.oneOf or {}) do
    for field, property in pairs(variant.properties or {}) do
      if property.const then
        if not tags[field] then
          tags[field] = {}
          order[#order + 1] = field
        end
        table.insert(tags[field], property.const)
      elseif not props[field] then
        props[field] = property
      end
    end
  end
  table.sort(order)
  local enums: {model.SchemaEnum} = {}
  for _, field in ipairs(order) do
    local enum_name = name .. field:sub(1, 1):upper() .. field:sub(2)
    enums[#enums + 1] = {name = enum_name, doc = {}, values = tags[field]}
    local tagged: Schema = {}
    (tagged as {string: string})["x-teal"] = enum_name
    props[field] = tagged
  end
  return props, enums
end

--- The records and the enums of the kernel's schema, each sorted by name.
function schema.read(): model.Schema
  local json = api.api_schema()
  local decoded, err = api.json_decode(json)
  if err then
    error("paw.api.api_schema: " .. err)
  end
  local defs = decoded as {string: Schema}
  local names: {string} = {}
  for name in pairs(defs) do
    names[#names + 1] = name
  end
  table.sort(names)
  local out: model.Schema = {records = {}, enums = {}, json = json}
  for _, name in ipairs(names) do
    local def = defs[name]
    local values = choices(def)
    if keys(def)["x-teal"] then
      -- types.tl defines it by hand.
    elseif values then
      out.enums[#out.enums + 1] = {name = name, doc = lines(def.description), values = values}
    elseif def.properties or def.oneOf then
      local props, enums = properties_of(name, def)
      for _, enum in ipairs(enums) do
        out.enums[#out.enums + 1] = enum
      end
      local record: Record = {name = name, doc = lines(def.description), fields = {}}
      local fields: {string} = {}
      for field in pairs(props) do
        fields[#fields + 1] = field
      end
      table.sort(fields)
      for _, field in ipairs(fields) do
        local property = props[field]
        local f: Field = {
          name = field,
          teal = teal_of(property, defs, name .. "." .. field),
          doc = lines(property.description),
        }
        record.fields[#record.fields + 1] = f
      end
      out.records[#out.records + 1] = record
    end
  end
  table.sort(out.enums, function(a: model.SchemaEnum, b: model.SchemaEnum): boolean return a.name < b.name end)
  return out
end

return schema
