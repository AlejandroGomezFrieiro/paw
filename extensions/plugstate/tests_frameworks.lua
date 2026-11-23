-- Tests of the framework layer of plugstate (`plugstate.frameworks`):
-- states recorded from real plugins in `tests_states/` (made by test runs,
-- with the plugins' defaults), states made here by the rules of each
-- framework, and the real plugins when a variable names them.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api

local function load()
  paw.ext.load("extensions/plugstate")
  return require("plugstate.frameworks")
end

--- The changes between two documents.
local function juce_diff(_, a, b) return require("plugstate.juce").diff(a.root, b.root) end

local function fixture(name) return (T.read_file("extensions/plugstate/tests_states/" .. name .. ".b64"):gsub("%s", "")) end

test(
  "plugstate: each framework's state from a real plugin opens as a tree and is written back byte for byte",
  function()
    local fw = load()
    local cases = {
      { "dpf-dragonfly-hall.clap", "clap", "dpf", "/DPF/Parameters@size", 24 },
      { "dpf-dragonfly-hall.vst3", "vst3", "dpf", "/DPF/Parameters@size", 24 },
      { "dpf-dragonfly-hall.lv2", "lv2", "dpf", "/DPF/Parameters@size", 24 },
      { "lsp-compressor-mono.clap", "clap", "lsp", "/LSP/Parameters@cr", 4 },
      { "lsp-compressor-mono.vst3", "vst3", "lsp", "/LSP/Parameters@cr", 4 },
      { "lsp-compressor-mono.lv2", "lv2", "lsp", "/LSP/Parameters@cr", 4 },
      { "lv2-ratatouille.lv2", "lv2", "lv2", "/LV2/Parameters@ENABLE", 1 },
      { "lv2-sfizz.lv2", "lv2", "lv2", "/LV2/State@cc010", 0.5 },
      { "juce-neuralnote.vst3", "vst3", "juce", "/NEURAL_NOTE_FULL_STATE/PARAMETERS/PARAM[id=MIX]@value", "0.5" },
      -- The float, and the bytes that hold it.
      { "binary-mt-powerdrumkit.vst3", "vst3", "binary", "/State/Floats@at8", nil, 2 },
    }
    for _, c in ipairs(cases) do
      local state = fixture(c[1])
      local doc = fw.open(state, c[2])
      eq(doc.framework, c[3], c[1] .. ": the framework")
      eq(doc:write(), state, c[1] .. ": nothing changed, the same bytes")
      local v = doc:get(c[4])
      if c[5] ~= nil then
        eq(
          type(v) == "number" and math.abs(v - c[5]) < 1e-5 or v == c[5],
          true,
          c[1] .. ": " .. c[4] .. " = " .. tostring(v)
        )
      end
      -- Change one value; the state reads it back, and the rest stays.
      local new = type(v) == "number" and v + 1 or "0.75"
      doc:set(c[4], new)
      local again = fw.open(doc:write(), c[2])
      local got = again:get(c[4])
      eq(
        type(new) == "number" and math.abs(got - new) < 1e-4 or got == new,
        true,
        c[1] .. ": the change is written: " .. tostring(got)
      )
      eq(#again:params(), #doc:params(), c[1] .. ": the same parameters")
      eq(#juce_diff(fw, fw.open(state, c[2]), again), c[6] or 1, c[1] .. ": only that value differs")
    end
  end
)

test("plugstate: DPF and LSP states have the same paths in CLAP, VST3 and LV2, and a preset goes into each", function()
  local fw = load()
  local js = require("plugstate.jucestate")
  local clap, vst3, lv2 =
    fixture("dpf-dragonfly-hall.clap"), fixture("dpf-dragonfly-hall.vst3"), fixture("dpf-dragonfly-hall.lv2")
  for _, s in ipairs({ { clap, "clap" }, { vst3, "vst3" }, { lv2, "lv2" } }) do
    local doc = fw.open(s[1], s[2])
    eq(doc:get("/DPF/State@preset"), "Small Clear Hall", s[2] .. ": a state key of DPF")
    eq(doc:param("dry_level"), 80, s[2] .. ": a parameter by its symbol")
  end
  -- CLAP and VST3 hold the same data.
  local doc = fw.open(clap, "clap")
  eq(doc:write_as("vst3", vst3), vst3, "the CLAP state as VST3 is the VST3 state")
  T.fails(function() doc:write_as("lv2") end, "Turtle", "the data of CLAP does not go into LV2")
  -- A preset of path edits goes into each format.
  local file = T.scratch .. "/hall.jucepreset"
  js.write_preset(file, {
    name = "Big",
    framework = "dpf",
    edits = {
      { path = "/DPF/Parameters@size", value = 40 },
      { param = "decay", value = 3 },
      { path = "/DPF/State@preset", value = "Large Clear Hall", kind = "string" },
    },
  })
  local preset = js.read_preset(file)
  for _, s in ipairs({ { clap, "clap" }, { vst3, "vst3" }, { lv2, "lv2" } }) do
    local made = fw.open(fw.generate(preset, s[2], s[1]), s[2])
    eq(made:get("/DPF/Parameters@size"), 40, s[2] .. ": the preset's size")
    eq(made:param("decay"), 3, s[2] .. ": its decay")
    eq(made:get("/DPF/State@preset"), "Large Clear Hall", s[2] .. ": its state key")
  end
  -- A DPF parameter that was a whole number is written as one.
  local d2 = fw.open(clap, "clap")
  d2:set_param("size", 30)
  eq(paw.bytes.unbase64(d2:write()):find("size\0" .. "30\0", 1, true) ~= nil, true, "size 30, as DPF writes it")
  T.fails(function() d2:set_param("none", 1) end, "no parameter", "a parameter that is not there")

  local lsp = fw.open(fixture("lsp-compressor-mono.clap"), "clap")
  local lsp2 = fw.open(fixture("lsp-compressor-mono.lv2"), "lv2")
  eq(lsp:get("/LSP/Parameters@g_out"), 1, "LSP in CLAP: a port by its id")
  eq(lsp2:get("/LSP/Parameters@g_out"), 1, "LSP in LV2: the same path")
  eq(type(lsp:get("/LSP/State@!preset_settings")), "table", "the preset settings stay a binary value")
end)

local bytes_of = function() return paw.bytes end

--- An iPlug2 chunk: strings (PutStr), the parameters as doubles, more data.
local function iplug_chunk(strings, values, extra)
  local ffi = require("ffi")
  local out = {}
  local i = ffi.new("int32_t[1]")
  local d = ffi.new("double[1]")
  for _, s in ipairs(strings) do
    i[0] = #s
    out[#out + 1] = ffi.string(i, 4) .. s
  end
  for _, v in ipairs(values) do
    d[0] = v
    out[#out + 1] = ffi.string(d, 8)
  end
  out[#out + 1] = extra or ""
  return table.concat(out)
end

test("plugstate: an iPlug2 state gives its parameters by name, with the host's list of them", function()
  local fw = load()
  local b = bytes_of()
  local info = {
    { id = "0", key = "gain" },
    { id = "1", key = "mix" },
    { id = "2", key = "mode" },
    { id = "65536", key = "cc0" },
    { id = "fx_gain", key = "fx_gain" },
  }
  -- NAM's form: a header, a version, two paths (one empty), the parameters.
  local chunk = iplug_chunk({ "###Amp###", "1.2.3", "/models/a.nam", "" }, { 0, -80, 2 }, "\1\2\3")
  local vst3 = b.base64(b.le32(#chunk + 4) .. chunk .. "\0\0\0\0" .. b.le32(0))
  local doc = fw.open(vst3, "vst3", { param_info = info })
  eq(doc.framework, "iplug2", "the header names iPlug2")
  eq(doc:get("/IPlug/Chunk@string3"), "/models/a.nam", "its strings")
  eq(doc:param("mix"), -80, "a parameter by its name, not its place")
  eq(#doc:params(), 3, "only the plugin's own parameters")
  eq(doc:get("/IPlug@bypass"), 0, "the bypass flag of VST3")
  eq(doc:write(), vst3, "written back the same")
  doc:set_param("mode", 1)
  doc:set("/IPlug/Chunk@string3", "/models/b.nam")
  local again = fw.open(doc:write(), "vst3", { param_info = info })
  eq(again:param("mode"), 1, "the parameter is written")
  eq(again:get("/IPlug/Chunk@string3"), "/models/b.nam", "and the string, with its new length")
  eq(again:get("/IPlug/Chunk@data").binary, "\1\2\3", "the plugin's own data after them stays")
  -- CLAP: the chunk alone, and the default `SerializeState` (the
  -- parameters only), found with the hint of the binary.
  local plain = b.base64(iplug_chunk({}, { 0.5, 1, 0 }))
  local c = fw.open(plain, "clap", { param_info = info, hint = "iplug2" })
  eq(c.framework, "iplug2", "the hint of the binary")
  eq(c:param("gain"), 0.5, "the first double is the first parameter")
  eq(c:write(), plain, "written back the same")
end)

test("plugstate: JUCE's VST3 wrapper that replaces a VST2 plugin (VstW and an FXB or FXP chunk)", function()
  local fw = load()
  local b = bytes_of()
  local juce = require("plugstate.juce")
  local function be(n)
    return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
  end
  local tree = juce.write(juce.tree("ControlData", { { "gain", 0.5 } }))
  local bank = "FBCh" .. be(2) .. "Bass" .. be(66050) .. be(0) .. ("\0"):rep(128) .. be(#tree) .. tree
  local program = "FPCh" .. be(1) .. "Bass" .. be(66050) .. be(1) .. ("Init"):rep(7) .. be(#tree) .. tree
  for _, chunk in ipairs({ bank, program }) do
    local data = "VstW" .. be(8) .. be(1) .. be(0) .. "CcnK" .. be(#chunk) .. chunk
    local state = b.base64(b.le32(#data) .. data .. b.le32(0))
    local doc = fw.open(state, "vst3")
    eq(doc.framework, "juce", "a JUCE state")
    eq(
      table.concat(doc:layer_names(), " "),
      "vst3 vstw valuetree",
      "the layers: " .. table.concat(doc:layer_names(), " ")
    )
    eq(doc:get("/ControlData@gain"), 0.5, "the tree in the chunk")
    eq(doc:write(), state, "written back the same")
    doc:set("/ControlData@name", "a longer value than before")
    local again = fw.open(doc:write(), "vst3")
    eq(again:get("/ControlData@name"), "a longer value than before", "a change, with the sizes of the chunk")
    eq(again:get("/ControlData@gain"), 0.5, "and the rest")
  end
end)

test("plugstate: a Dplug state gives its normalized parameters by name, and its own data", function()
  local fw = load()
  local b = bytes_of()
  local ffi = require("ffi")
  local f = ffi.new("float[1]")
  local function float(v)
    f[0] = v
    return ffi.string(f, 4)
  end
  -- preset.d `writeStateChunk`: magic, versions 1.0, plugin version, preset 2, 2 floats, its data.
  local chunk = "\11\32\186\146"
    .. b.le32(1)
    .. b.le32(0)
    .. b.le32(65536)
    .. b.le32(2)
    .. b.le32(2)
    .. float(0.25)
    .. float(1)
    .. b.le32(3)
    .. "abc"
  local state = b.base64(chunk)
  local info = { { id = "0", key = "drive" }, { id = "1", key = "mix" } }
  local doc = fw.open(state, "clap", { param_info = info })
  eq(doc.framework, "dplug", "the magic of Dplug")
  eq(doc:param("drive"), 0.25, "a parameter by its name")
  eq(doc:get("/Dplug/State@data").binary, "abc", "the plugin's own data")
  eq(doc:write(), state, "written back the same")
  doc:set_param("mix", 0.5)
  doc:set("/Dplug@preset", 0)
  local again = fw.open(doc:write(), "clap", { param_info = info })
  eq(again:param("mix"), 0.5, "the parameter is written")
  eq(again:get("/Dplug@preset"), 0, "and the current preset")
  eq(again:get("/Dplug/State@data").binary, "abc", "the data stays")
end)

test("plugstate: JSON states (nih-plug, Vital) change in place", function()
  local fw = load()
  local b = bytes_of()
  local text = '{"version":"0.1.0","params":{"gain":{"f32":-6.0},"mode":{"string":"fast"},"on":{"bool":true}},'
    .. '"fields":{"editor-state":"{\\"open\\":false}"}}'
  local state = b.base64(text)
  local doc = fw.open(state, "clap")
  eq(doc.framework, "nih-plug", "params and fields: nih-plug's PluginState")
  eq(doc:param("gain"), -6, "a parameter's value")
  eq(doc:param("mode"), "fast", "an enum by its id")
  eq(doc:write(), state, "written back the same")
  doc:set_param("gain", -3.5)
  eq(b.unbase64(doc:write()), text:gsub("%-6%.0", "-3.5"), "only that value changes in the text")
  T.fails(function()
    local d = fw.open(state, "clap")
    d:set("/state@new", 1)
    d:write()
  end, "only values", "a new key has no place")
  local vital = b.base64('{"author":"me","settings":{"osc_1_level":0.7,"osc_1_on":1.0},"synth_version":"1.5.5"}')
  local v = fw.open(vital, "clap")
  eq(v.framework, "vital", "Vital's preset JSON")
  eq(v:param("osc_1_level"), 0.7, "its settings are the parameters")
  -- In a VST3 state, with a zero byte at its end, as a JUCE plugin keeps text.
  local vst3 = b.base64(b.le32(#text + 1) .. text .. "\0" .. b.le32(0))
  eq(fw.open(vst3, "vst3"):write(), vst3, "JSON in VST3, back the same")
end)

test("plugstate: the bytes of an unknown state, and the floats in them", function()
  local fw = load()
  local state = fixture("binary-mt-powerdrumkit.vst3")
  local doc = fw.open(state, "vst3")
  eq(doc.framework, "binary", "no framework knows it")
  eq(#doc:params() > 100, true, "its words read as floats")
  local before = doc:get("/State/Floats@at8")
  doc:set("/State/Floats@at8", 0.25)
  local raw, raw2 = bytes_of().unbase64(state), bytes_of().unbase64(doc:write())
  eq(#raw2, #raw, "the same length")
  local differ = 0
  for i = 1, #raw do
    if raw:byte(i) ~= raw2:byte(i) then differ = differ + 1 end
  end
  eq(differ <= 4 and differ > 0, true, "only the four bytes of that float change")
  eq(fw.open(doc:write(), "vst3"):get("/State/Floats@at8"), 0.25, "it reads back")
  eq(before ~= 0.25, true, "it was another value")
end)

test("plugstate: the framework of a plugin from the marker strings of its binary", function()
  local fw = load()
  local function binary(name, text)
    local path = T.scratch .. "/" .. name
    T.write_file(path, "\127ELF" .. ("\0"):rep(64) .. text .. ("\0"):rep(16))
    return path
  end
  eq((fw.markers(binary("a.so", "JUCE v8.0.15 JucePlugin_Name"))), "juce", "JUCE")
  eq(select(2, fw.markers(binary("b.so", "JUCE v7.0.2"))), "7.0.2", "and its version")
  eq((fw.markers(binary("c.so", "DISTRHO::Plugin"))), "dpf", "DPF")
  eq((fw.markers(binary("d.so", "iPlug2 IPlugAPIBase"))), "iplug2", "iPlug2")
  eq((fw.markers(binary("e.so", "N4hise14MainControllerE JUCE v6.1.3"))), "hise", "HISE, made on JUCE")
  eq((fw.markers(binary("f.so", "VSTGUI::CFrame"))), "vstgui", "VSTGUI")
  eq((fw.markers(binary("g.so", "nothing"))), nil, "none")
end)

-- --- the real plugins ---------------------------------------------------------------
-- Each runs when its variable names the plugin's package (a store path) or
-- bundle; `tests/tools/suite.sh plugins` puts them in the plugin folders.
-- The plugins in the dev shell (LSP, Neural Amp Modeler) run without one.

local function kind_of(format, pattern)
  for _, info in ipairs(paw.device_types()) do
    if info.format == format and info.name:find(pattern) then return info.kind end
  end
end

local function level(from)
  local info = T.render({ tail = 0, bits = 16 })
  local data = T.read_file(info.path)
  local at = data:find("data", 1, true) + 8 + math.floor((from or 0) * info.sample_rate) * 4
  local sum, n = 0, 0
  for i = at, #data - 1, 2 do
    local lo, hi = data:byte(i, i + 1)
    local v = lo + hi * 256
    if v >= 32768 then v = v - 65536 end
    sum, n = sum + v * v, n + 1
  end
  return math.sqrt(sum / math.max(n, 1)) / 32768
end

local keys = T.keys

--- Wait until the plugin's state holds `value` at `path` (two seconds at
--- most): a state that paw loads reaches the plugin a moment later.
local function holds(fw, id, path, value)
  local got
  for _ = 1, 100 do
    paw.flush()
    local doc = require("plugstate.juceplugins").open(id)
    got = doc and doc:get(path)
    if got == value or (tonumber(got) and tonumber(value) and math.abs(tonumber(got) - tonumber(value)) < 1e-3) then
      return got
    end
    api.sleep(20)
  end
  return got
end

local live = {
  {
    var = "PAW_TEST_DRAGONFLY",
    format = "clap",
    name = "^Dragonfly Hall Reverb$",
    path = "/DPF/Parameters@dry_level",
    value = "0",
    louder = false,
  },
  {
    var = "PAW_TEST_DRAGONFLY",
    format = "vst3",
    name = "^Dragonfly Hall Reverb$",
    path = "/DPF/Parameters@dry_level",
    value = "0",
    louder = false,
  },
  {
    var = "PAW_TEST_DRAGONFLY",
    format = "lv2",
    name = "^Dragonfly Hall Reverb$",
    path = "/DPF/Parameters@dry_level",
    value = "0",
    louder = false,
  },
  { var = "PAW_TEST_ILDAEIL", format = "vst3", name = "^Ildaeil%-FX$", framework = "dpf" },
  { var = "PAW_TEST_ILDAEIL", format = "lv2", name = "^Ildaeil%-FX$", framework = "dpf" },
  {
    var = "-",
    format = "clap",
    name = "^Compressor Mono$",
    path = "/LSP/Parameters@g_out",
    value = "0.1",
    louder = false,
  },
  {
    var = "-",
    format = "vst3",
    name = "^Compressor Mono$",
    path = "/LSP/Parameters@g_out",
    value = "0.1",
    louder = false,
  },
  {
    var = "-",
    format = "lv2",
    name = "^LSP Compressor Mono$",
    path = "/LSP/Parameters@g_out",
    value = "0.1",
    louder = false,
  },
  {
    var = "-",
    format = "lv2",
    name = "^Neural Amp Modeler$",
    path = "/LV2/Parameters@output_level",
    value = "-20",
    louder = false,
  },
  -- VoLum takes a state that paw loads, then its controller gives the
  -- processor the parameters of before (the parameter echo of VST3 that
  -- STATEFIX fixes): only what paw writes is checked.
  {
    var = "PAW_TEST_VOLUM",
    format = "vst3",
    name = "^VoLum$",
    hint = "iplug2",
    path = "/IPlug/Parameters@output",
    value = "-20",
    echo = true,
  },
  {
    var = "PAW_TEST_NEURALNOTE",
    format = "vst3",
    name = "^NeuralNote$",
    framework = "juce",
    path = "/NEURAL_NOTE_FULL_STATE/PARAMETERS/PARAM[id=MASTER_GAIN]@value",
    value = "-12.0",
  },
  { var = "PAW_TEST_DECENTSAMPLER", format = "vst3", name = "^DecentSampler$", framework = "juce" },
  { var = "PAW_TEST_AMPLOCKER", format = "vst3", name = "^Amp Locker$", framework = "juce" },
  { var = "PAW_TEST_DRUMLOCKER", format = "vst3", name = "^Drum Locker$", framework = "juce" },
  {
    var = "PAW_TEST_UGRITONE",
    format = "vst3",
    name = "^Ugritone Drums$",
    framework = "juce",
    path = "/Root@FXChannelCompressorRatio",
    value = "2.0",
  },
  { var = "PAW_TEST_MTPDK", format = "vst3", name = "MT%-PowerDrumKit", framework = "binary" },
  -- Windows plugins through yabridge: the variable names a bundle whose
  -- Windows plugin is in a wine prefix made for the test (WINEPREFIX).
  {
    var = "PAW_TEST_GUITARCATCHER",
    format = "vst3",
    name = "^Guitarcatcher$",
    framework = "juce",
    path = "/GUITARTRACK/PARAM[id=GT_DELAY_MIX]@value",
    value = "0.5",
  },
  {
    var = "PAW_TEST_CIRCVIT",
    format = "vst3",
    name = "^Circvit Bass$",
    framework = "juce",
    path = "/ControlData/InterfaceData/Content/*[id=Master]@value",
    value = "0.5",
  },
  { var = "PAW_TEST_GUITARIX", format = "lv2", name = "^GxAmplifier%-X$", framework = "lv2" },
  { var = "PAW_TEST_RATATOUILLE", format = "lv2", name = "^Ratatouille$", framework = "lv2" },
}

for _, c in ipairs(live) do
  test(
    string.format(
      "plugstate live: %s %s: its state opens, a path changes the plugin, and nothing else changes",
      c.name:gsub("[%^%$%%]", ""),
      c.format
    ),
    function()
      if c.var ~= "-" and (os.getenv(c.var) or "") == "" then return "skipped: " .. c.var .. " names no plugin" end
      local kind = kind_of(c.format, c.name)
      if not kind then return "skipped: the plugin is not in the plugin folders" end
      local fw = load()
      T.fresh()
      local part = T.tone("in", 8, "A2")
      paw.cursor.set_part(part.id)
      local d = part:add_device(kind)
      paw.flush()
      api.undo_checkpoint()
      local state = api.device_state(d.id)
      local doc, why = require("plugstate.juceplugins").open(d.id, state)
      eq(doc ~= nil, true, "it opens: " .. tostring(why))
      if c.framework or c.hint then eq(doc.framework, c.framework or c.hint, "the framework") end
      eq(doc:write(), state, "written back byte for byte")
      eq(require("plugstate").adapter_of(d.id) ~= nil, true, "an adapter knows it")
      if not c.path then return end
      local before = c.louder ~= nil and level(1) or nil
      paw.ui.focus("devices")
      paw.fx.select(d.id)
      if c.echo then
        -- What `:plugstate.path` gives the plugin, as a state lane takes it.
        local edited = require("plugstate.juceplugins").open(d.id, state)
        edited:set(c.path, tonumber(c.value) or c.value)
        local back = fw.open(edited:write(), c.format, { param_info = api.device_get(d.id).param_info, hint = c.hint })
        eq(
          tostring(back:get(c.path)),
          tostring(tonumber(c.value) or c.value),
          "the state that paw writes holds the value"
        )
        return
      end
      keys(":plugstate.path " .. c.path .. " " .. c.value .. "<CR>")
      local got = holds(fw, d.id, c.path, c.value)
      eq(
        tonumber(got) and math.abs(tonumber(got) - tonumber(c.value)) < 1e-3 or got == c.value,
        true,
        "the plugin saves the new value: " .. tostring(got)
      )
      if before then
        local after = level(1)
        eq(after < before - 0.002, true, string.format("and it plays more quietly (%.4f, %.4f)", before, after))
      end
      -- What else changed: only that path (and what the plugin says of itself).
      local now = require("plugstate.juceplugins").open(d.id)
      local changes =
        now:diff(fw.open(state, c.format, { param_info = api.device_get(d.id).param_info, hint = c.hint }))
      local listed = {}
      for _, ch in ipairs(changes) do
        listed[#listed + 1] = ch.path
      end
      eq(
        table.concat(listed, " "):find(c.path:gsub("%[id=[^%]]*%]", ""):match("@(.*)$"), 1, true) ~= nil,
        true,
        "the path is among the changes: " .. table.concat(listed, " ")
      )
      keys("u")
      local back = holds(
        fw,
        d.id,
        c.path,
        (fw.open(state, c.format, { param_info = api.device_get(d.id).param_info, hint = c.hint }):get(c.path))
      )
      eq(back ~= nil, true, "u takes it back")
    end
  )
end

test(
  "plugstate live: a DPF plugin with keys: the tree, the changes after a mark, a preset of them and a state lane point",
  function()
    if (os.getenv("PAW_TEST_DRAGONFLY") or "") == "" then return "skipped: PAW_TEST_DRAGONFLY names no plugin" end
    local kind = kind_of("clap", "^Dragonfly Hall Reverb$")
    if not kind then return "skipped: the plugin is not in the plugin folders" end
    local fw = load()
    local plugstate = require("plugstate")
    local function said() return paw.ui.messages[#paw.ui.messages].text end
    T.fresh()
    local part = T.tone("in", 8, "A2")
    paw.cursor.set_part(part.id)
    local d = part:add_device(kind)
    paw.flush()
    api.undo_checkpoint()
    paw.ui.focus("devices")
    paw.fx.select(d.id)
    eq(plugstate.adapter_of(d.id).name, "state", "the adapter of every plugin knows it")
    keys(":plugstate.tree<CR>")
    eq(
      said():find("DPF", 1, true) ~= nil and said():find("@dry_level = 80", 1, true) ~= nil,
      true,
      "the tree: " .. said()
    )
    keys(":plugstate.info<CR>")
    eq(said():find("state: DPF", 1, true) ~= nil, true, ":plugstate.info names the framework: " .. said())
    local wet = level(1)
    keys(":plugstate.mark<CR>")
    api.device_set_param(d.id, "dry_level", 0)
    paw.flush()
    keys(":plugstate.changes<CR>")
    eq(said():find("set    /DPF/Parameters@dry_level", 1, true) ~= nil, true, "the change by its path: " .. said())
    local file = T.scratch .. "/dry.jucepreset"
    keys(":plugstate.preset_write " .. file .. "<CR>")
    eq(require("plugstate.jucestate").read_preset(file).framework, "dpf", "the preset names its framework")
    local dry = level(1)
    eq(dry < wet - 0.002, true, string.format("without the dry signal it is quieter (%.4f, %.4f)", wet, dry))

    -- The preset in a new device, in each format: the paths are the same.
    for _, format in ipairs({ "clap", "vst3", "lv2" }) do
      local k = kind_of(format, "^Dragonfly Hall Reverb$")
      if k then
        T.fresh()
        local t2 = T.tone(format, 8, "A2")
        paw.cursor.set_part(t2.id)
        local d2 = t2:add_device(k)
        paw.flush()
        api.undo_checkpoint()
        paw.ui.focus("devices")
        paw.fx.select(d2.id)
        keys(":plugstate.load " .. file .. "<CR>")
        eq(tonumber(holds(fw, d2.id, "/DPF/Parameters@dry_level", "0")), 0, format .. ": the preset sets dry_level")
        T.near(level(1), dry, 0.003, format .. ": and it sounds as the plugin that made it")
        keys("u")
        eq(tonumber(holds(fw, d2.id, "/DPF/Parameters@dry_level", "80")), 80, format .. ": u takes it back")
      end
    end

    -- A state lane point: the preset from the second bar on.
    T.fresh()
    local t3 = T.tone("lane", 8, "A2")
    paw.cursor.set_part(t3.id)
    local d3 = t3:add_device(kind)
    paw.flush()
    local state, why = plugstate.lane_state(d3.id, "preset", file)
    eq(state ~= nil and state.state ~= nil, true, "the preset as a state of the lane: " .. tostring(why))
    plugstate.snapshot(d3.id, "wet")
    plugstate.lane_point(d3.id, 0, (plugstate.lane_snapshot(d3.id, "wet")))
    local lane = plugstate.lane_point(d3.id, 4, state)
    eq(#lane:states(), 2, "the plugin as it was from the start, the preset from beat 4")
    local first, second = level(0.2), nil
    local info = T.render({ tail = 0, bits = 16 })
    -- The level of the second half (after the point) is the dry-less one.
    local data = T.read_file(info.path)
    local function rms(from, to)
      local sum, n = 0, 0
      local at = data:find("data", 1, true) + 8
      for i = at + math.floor(from * info.sample_rate) * 4, at + math.floor(to * info.sample_rate) * 4, 4 do
        local lo, hi = data:byte(i, i + 1)
        if not hi then break end
        local v = lo + hi * 256
        if v >= 32768 then v = v - 65536 end
        sum, n = sum + v * v, n + 1
      end
      return math.sqrt(sum / math.max(n, 1)) / 32768
    end
    local seconds = 4 * 60 / paw.tempo.at(0)
    second = rms(seconds + 0.5, 2 * seconds - 0.1)
    eq(
      second < rms(0.5, seconds - 0.1) - 0.002,
      true,
      string.format("after the point the preset plays (%.4f, %.4f, %.4f)", first, rms(0.5, seconds - 0.1), second)
    )
  end
)
