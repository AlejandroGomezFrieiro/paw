-- The model of paw's API that tools/apidoc.lua makes its files from. The
-- readers (apidoc/read/) fill it from the source and from the running
-- program, and each writer (apidoc/write/) makes one file from it. A
-- writer reads no file and no module: what it needs is a field here.
--
-- The kernel's functions and the records of its data have their types as
-- the source gives them (`Type`), not as a file writes them: each writer
-- writes them in its own notation (Teal, LuaLS). A reader of another
-- source of the same shapes (a description that Rust writes, or a JSON
-- Schema) fills the same records.
local type anys = require("apidoc.anys")

local record model
  --- A table of the running program, walked by its keys. Reflection gives
  --- its keys and values no shape. A map keyed by `any` below is keyed by
  --- such a value (a table of a module, a function), only to know one
  --- value under two names.
  type Table = {any: any}

  --- The kinds of `Type`.
  enum TypeKind
    "named"
    "optional"
    "list"
    "tuple"
  end

  --- A type as the source spells it: `Option<Vec<Id>>` is an optional
  --- list of the named type `Id`. `text` is the spelling of the source.
  record Type
    kind: TypeKind
    text: string
    --- What an optional or a list holds.
    of: Type
    --- The parts of a tuple.
    items: {Type}
  end

  --- A parameter of a kernel function. `teal` and `optional` come from a
  --- `@param name T` line of its comment, which overrides `type`.
  record Param
    name: string
    type: Type
    teal: string
    optional: boolean
  end

  --- A function of `paw.api` as the source shows it. `doc` is the prose
  --- of its comment; `returns` the type of a `@return` line (nil when it
  --- has none); `forms` the whole type of each `@type function(...)` line.
  record KernelFunction
    name: string
    params: {Param}
    doc: {string}
    returns: string
    forms: {string}
  end

  --- A plain value of `paw.api` (`version`, `limit_async`) by its Lua type.
  record Plain
    name: string
    type: string
  end

  --- `paw.api`: its version, the names of its functions (sorted), what the
  --- source shows of each, and its other plain values (sorted by name).
  record Kernel
    version: string
    names: {string}
    functions: {string: KernelFunction}
    plain: {Plain}
    --- The name of each function, by the function.
    name_of: {any: string}
  end

  --- A field of a record, or a variant of an enum, of a Rust file. `teal`
  --- is the type of a `/// @type T` line, which overrides `type`.
  record Field
    name: string
    type: Type
    teal: string
    doc: {string}
    --- The name serde gives a variant (`rename`).
    serde: string
  end

  --- A `pub struct` that serde reads or writes.
  record Record
    name: string
    doc: {string}
    fields: {Field}
  end

  --- A type of string choices of the kernel's schema.
  record SchemaEnum
    name: string
    doc: {string}
    values: {string}
  end

  --- What the kernel's schema (`paw.api.api_schema`) gives: records whose
  --- fields have their Teal type in `teal`, and enums, each sorted by name.
  record Schema
    records: {Record}
    --- The JSON text as the kernel gives it.
    json: string
    enums: {SchemaEnum}
  end

  --- What a Rust file of data gives: its records in order, and the
  --- variants of each `pub enum` by the enum's name.
  record RustFile
    path: string
    records: {Record}
    enums: {string: {Field}}
  end

  --- A module of the runtime as `paw` reaches it, by its shortest name
  --- (`paw.option`), with the name `require` gives it (nil for a class,
  --- `paw.Part`).
  record Module
    name: string
    table: Table
    module: string
  end

  --- A public function of a module of the runtime. A function reached
  --- under two names is written once: the other has `alias_of`.
  record Function
    name: string
    module: string
    key: string
    alias_of: string
    --- Its `---` comment, tags included; nil for a function the runtime
    --- did not write.
    doc: {string}
    path: string
    line: integer
    params: {string}
    --- Written with `:`: its `self` is not in `params`.
    method: boolean
  end

  --- A module of the runtime in Teal. `hidden` when it is no value of
  --- `paw` itself, but its values are (paw.objects gives `paw.Part`).
  record TealModule
    name: string
    module: string
    file: string
    hidden: boolean
  end

  --- What the doc comments of a module in Lua type: its record's name in
  --- partial.d.tl, its fields as `{ key, type }` and the type of a call.
  record LuaRecord
    name: string
    table: Table
    record: string
    lines: {{string}}
    call: string
  end

  --- What the doc comments of the modules in Lua type.
  record LuaTypes
    records: {LuaRecord}
    --- The forms of each typed function, by the function.
    forms: {any: {string}}
    --- The types of the typed values of `paw` itself, by key.
    top: {string: {string}}
  end

  --- An option that the runtime defines: the Lua types it takes, and
  --- whether a number is whole.
  record Option
    name: string
    types: {string}
    integer: boolean
  end

  --- An event that a module of the runtime sends, as a row of
  --- docs/reference/events.md.
  record Event
    event: string
    payload: string
    when: string
    teal: string
  end

  --- The model: each reader fills its fields.
  record Model
    --- The global `paw`, which the declarations walk.
    paw: Table
    modules: {Module}
    functions: {Function}
    kernel: Kernel
    teal_modules: {TealModule}
    --- The Teal type of each value of a module in Teal, by the value.
    teal_values: {any: string}
    lua_types: LuaTypes
    options: {Option}
    events_rs: RustFile
    props_rs: RustFile
    schema: Schema
    runtime_events: {Event}
    --- Whether runtime/lua/paw/types.tl is there.
    has_types: boolean
    --- The `any` of the records of the kernel's data (types.tl,
    --- contracts.tl), by the name of what has them.
    record_anys: {string: integer}
  end

  --- What a writer gets besides the model: the count of the `any` that
  --- the Teal declarations write, and the text of its file as it is now
  --- (nil when there is none), for a file it changes only in part.
  record Run
    anys: anys.Counts
    current: string
  end

  --- A writer: the file it makes, and its text from the model.
  record Writer
    path: string
    text: function(m: Model, run: Run): string
  end
end

return model
