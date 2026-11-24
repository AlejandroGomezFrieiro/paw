-- tools/apidoc.lua's work: the readers fill the model, and each writer
-- makes one file from it. `write` writes the files; `check` says what is
-- out of date, what function has no doc comment and what `any` the
-- allow-list does not allow.
local api = require("paw.api")
local model = require("apidoc.model")
local source = require("apidoc.source")
local anys = require("apidoc.anys")
local rust = require("apidoc.read.rust")
local lua = require("apidoc.read.lua")
local teal = require("apidoc.read.teal")
local schema = require("apidoc.read.schema")

local record run
  --- The writers, in the order they run: the allow-list's writer last, as
  --- it reads the count of `any` that the other writers make.
  WRITERS: {model.Writer}
end

run.WRITERS = {
  require("apidoc.write.meta"),
  require("apidoc.write.page"),
  require("apidoc.write.paw_d"),
  require("apidoc.write.api_d"),
  require("apidoc.write.untyped_d"),
  require("apidoc.write.partial_d"),
  require("apidoc.write.opts_d"),
  require("apidoc.write.kernel_events"),
  require("apidoc.write.role_props"),
  require("apidoc.write.types_schema"),
  require("apidoc.write.mcp_schema"),
  require("apidoc.write.events_page"),
  require("apidoc.write.any_allowed"),
}

--- The model, from every reader.
function run.model(): model.Model
  local paw_global = (_G as {string: model.Table}).paw
  local m: model.Model = {paw = paw_global}
  m.kernel = lua.kernel(rust.kernel_functions())
  m.modules = lua.modules()
  m.functions = lua.functions(m.modules, m.kernel)
  m.teal_modules = teal.modules(m.modules, paw_global)
  m.teal_values = teal.values(m.teal_modules)
  m.lua_types = lua.types(m.modules, m.teal_modules, m.teal_values)
  m.options = lua.options()
  m.events_rs = rust.records("crates/paw-core/src/events.rs")
  m.props_rs = rust.records("crates/paw-scene/src/props.rs")
  m.schema = schema.read()
  m.runtime_events = teal.events(m.modules)
  m.has_types = source.read("runtime/lua/paw/types.tl") ~= nil
  m.record_anys = teal.record_anys()
  return m
end

--- A file that a writer makes: its path, its text now, and the new text.
local record Made
  path: string
  current: string
  text: string
end

--- The text of each file, from the model, and the count of `any` in them.
--- Each writer gets its file as it is now: all are read before any is written.
function run.make(m: model.Model): {Made}, anys.Counts
  local counts = anys.new(m.record_anys)
  local out: {Made} = {}
  for _, writer in ipairs(run.WRITERS) do
    local current = source.read(writer.path)
    out[#out + 1] = {path = writer.path, current = current, text = writer.text(m, {anys = counts, current = current})}
  end
  return out, counts
end

--- The public functions with no `---` comment: their names and where they are.
function run.undocumented(m: model.Model): {string}
  local out: {string} = {}
  for _, f in ipairs(m.functions) do
    if not f.alias_of and f.path and #f.doc == 0 then
      out[#out + 1] = f.name .. "  " .. f.path .. ":" .. f.line
    end
  end
  return out
end

--- Write every file. Returns the exit code.
function run.write(): integer
  os.execute("mkdir -p runtime/types/paw runtime/lua/paw/events")
  local made = run.make(run.model())
  local paths: {string} = {}
  for _, file in ipairs(made) do
    local f = assert(io.open(file.path, "w"))
    f:write(file.text)
    f:close()
    paths[#paths + 1] = file.path
  end
  print("wrote " .. table.concat(paths, ", "))
  return 0
end

--- Say what is out of date, undocumented or not allowed. Returns the exit
--- code: 1 when there is any.
function run.check(): integer
  local m = run.model()
  local gaps = run.undocumented(m)
  local made, counts = run.make(m)
  local stale: {string} = {}
  for _, file in ipairs(made) do
    if file.current ~= file.text then
      stale[#stale + 1] = file.path
    end
  end
  local loose = anys.problems(counts, source.read(anys.PATH))
  for _, gap in ipairs(gaps) do
    print("undocumented: " .. gap)
  end
  for _, path in ipairs(stale) do
    print("out of date: " .. path .. " (run tools/apidoc.lua)")
  end
  for _, line in ipairs(loose) do
    print(line)
  end
  return (#gaps == 0 and #stale == 0 and #loose == 0) and 0 or 1
end

--- Run as `paw -l tools/apidoc.lua [check]`: quit with the exit code.
function run.main(mode: string)
  api.quit(mode == "check" and run.check() or run.write())
end

return run
