-- LV2 properties (`patch:writable`): listed and set through `device_call`,
-- and a preset load made of a call (`device_load{ call = }`). Needs the dev
-- shell's test plugins (`tests/tools/suite.sh plugins`).
local T = ...
local test, eq, fails, fresh = T.test, T.eq, T.fails, T.fresh
local api = paw.api

local function kind_of(format, pattern)
  for _, info in ipairs(paw.device_types()) do
    if info.format == format and info.name:find(pattern) then return info.kind end
  end
end

test("LV2 properties are listed, set as one undo step, and refused with a reason", function()
  local kind = kind_of("lv2", "^LSP Impulse Responses Stereo$")
  if not kind then return "skipped: test plugins not found" end
  fresh()
  local track = paw.add_track({ name = "ir" })
  local fx = track:add_device(kind)
  paw.flush()
  api.undo_checkpoint()
  local list = paw.json.decode(api.device_call(fx.id, "properties", ""))
  eq(#list, 2, "two impulse files")
  eq(list[1].type, "path", "a file")
  eq(list[1].writable, true, "that the host can set")
  eq(list[1].label, "Impulse file 1", "with the plugin's label")
  eq(list[1].key, "ifn0", "and a short key")

  -- Any file the plugin takes: this one only needs to be there.
  local file = T.scratch .. "/ir.wav"
  T.write_file(file, "RIFF")
  api.device_load(fx.id, {
    name = "ir",
    params = fx:get().params,
    call = { method = "property.set", data = paw.json.encode({ property = "ifn0", value = file }) },
  })
  api.undo_checkpoint()
  -- The plugin tells the value back from its own thread, after it has loaded the file.
  T.until_(function() return paw.json.decode(api.device_call(fx.id, "properties", ""))[1].value == file end,
    "the plugin to tell the value back")
  eq(paw.json.decode(api.device_call(fx.id, "properties", ""))[1].value, file, "the value is told back")
  eq(fx:get().meta.preset, "ir", "the load is named")
  paw.undo()
  eq(fx:get().meta.preset, nil, "undo takes it back")

  local function set(data) return function() api.device_call(fx.id, "property.set", data) end end
  fails(set('{"property":"nothing","value":"x"}'), "no property `nothing` %(it has: ifn0, ifn1%)", "an unknown property")
  fails(set('{"property":"ifn0","value":"/no/such/file.wav"}'), "there is no file /no/such/file.wav", "a file that is not there")
  fails(set('{"property":"ifn0","value":"ir.wav"}'), "absolute path", "a relative path")
  fails(set('{"property":"ifn0","value":3}'), "must be a text", "a number for a path")
  fails(set("ifn0"), "property", "not JSON")
  fails(function() api.device_load(fx.id, { factory = "x", call = { method = "properties", data = "" } }) end,
    "not both", "a preset and a call at once")

  local synth = track:add_device("synth")
  fails(function() api.device_call(synth.id, "properties", "") end, "takes no calls", "a built-in device has no properties")
end)
