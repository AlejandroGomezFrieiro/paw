-- `:checkhealth`, as in Neovim: each part of the program and each extension
-- registers a check, and the checks say what is well (OK), what may not be
-- (WARN) and what is wrong (ERROR), with advice on what to do.
--
--   paw.health.register("utau", function(h)
--     local engine = require("utau.engine").find()
--     if engine then h.ok("engine at " .. engine)
--     else h.error("no engine", { "set paw.opt.utau_engine", "or build it: nix build .#paw-utau" }) end
--   end, { desc = "Singing synthesis" })
--
-- `h.ok(text)`, `h.info(text)`, `h.warn(text, advice)`, `h.error(text,
-- advice)`; advice is a line or a list of them. A check that fails is
-- reported as an error of its own, and the others go on.
local api = paw.api
local M = { checks = {} }

local LEVELS = { ok = "OK", info = "INFO", warn = "WARN", error = "ERROR" }
local STYLES = { ok = "DiffAdd", info = "Normal", warn = "Warn", error = "Error" }

--- Register a check under `name`. It replaces a check with the same name.
--- `fn(h)` reports through `h`. `opts.desc` tells in a few words what it checks.
--- @type function(name: string, fn: contracts.HealthCheck, opts?: contracts.HealthOptions)
function M.register(name, fn, opts)
  assert(type(name) == "string" and type(fn) == "function", "usage: paw.health.register(name, function(h) ... end)")
  M.checks[name] = { name = name, fn = fn, desc = opts and opts.desc, ext = paw.commands.owner() }
end

--- The names of the checks, sorted.
function M.names()
  local out = {}
  for name in pairs(M.checks) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

--- Run one check: `{ name, desc, items }`, each item `{ level, text, advice }`.
function M.run(name)
  local check = M.checks[name]
  local result = { name = name, desc = check and check.desc, items = {} }
  local function add(level)
    return function(text, advice)
      if type(advice) == "string" then advice = { advice } end
      result.items[#result.items + 1] = { level = level, text = tostring(text), advice = advice }
    end
  end
  if not check then
    add("error")("no check named " .. tostring(name), { ":checkhealth with no name runs them all" })
    return result
  end
  local h = { ok = add("ok"), info = add("info"), warn = add("warn"), error = add("error") }
  local ok, err = pcall(paw.limit.named, "the health check " .. name, check.fn, h)
  if not ok then h.error("the check failed: " .. tostring(err):match("^[^\n]*")) end
  return result
end

--- Run the checks named (all when none), each a result of `run`.
function M.check(names)
  local out = {}
  for _, name in ipairs(names and #names > 0 and names or M.names()) do
    out[#out + 1] = M.run(name)
  end
  return out
end

--- The worst level among results: "ok", "warn" or "error".
function M.worst(results)
  local worst = "ok"
  for _, r in ipairs(results) do
    for _, item in ipairs(r.items) do
      if item.level == "error" then return "error" end
      if item.level == "warn" then worst = "warn" end
    end
  end
  return worst
end

--- Results as lines of text with their styles, for a page.
function M.lines(results)
  local lines = {}
  for i, r in ipairs(results) do
    if i > 1 then lines[#lines + 1] = "" end
    lines[#lines + 1] = { text = r.name .. (r.desc and ": " .. r.desc or ""), style = "Title" }
    for _, item in ipairs(r.items) do
      lines[#lines + 1] = { text = "- " .. LEVELS[item.level] .. " " .. item.text, style = STYLES[item.level] }
      for _, advice in ipairs(item.advice or {}) do
        lines[#lines + 1] = { text = "    - " .. advice, style = "Dim" }
      end
    end
    if #r.items == 0 then lines[#lines + 1] = { text = "- nothing to report", style = "Dim" } end
  end
  return lines
end

--- An executable on the PATH, or at a path: where it is, or nil.
function M.executable(name) return paw.api.which(name) end

-- The core's own checks ----------------------------------------------------------

M.register("paw", function(h)
  h.ok("paw " .. paw.version .. ", Lua API " .. api.version)
  local env = api.env()
  h.info(
    env.runtime_dir and "the Lua runtime is read from " .. env.runtime_dir or "the Lua runtime is the one built in"
  )
  if api.limit_async then
    h.ok("Lua that runs away is stopped, in compiled code too (LUAJIT_ENABLE_CHECKHOOK)")
  else
    h.warn(
      "LuaJIT was built without LUAJIT_ENABLE_CHECKHOOK: code that is not the runtime's runs uncompiled, to be stoppable",
      "build with the repository's .cargo/config.toml"
    )
  end
  if (paw.opt.lua_limit or 0) == 0 then
    h.warn("no time limit on Lua (paw.opt.lua_limit = 0)", "a loop that does not end will hang the program")
  end
end, { desc = "the program and its Lua" })

M.register("audio", function(h)
  local e = api.engine_get()
  if e.backend == "null" or e.backend == "step" then
    h.warn("the null audio backend: nothing is heard", { "start without --audio null", ":audio picks a device" })
  else
    h.ok(
      string.format(
        "%s on %s, %d Hz, %d frames a block",
        tostring(e.backend),
        tostring(e.device or "the default device"),
        e.sample_rate or 0,
        e.buffer_size or e.block or 0
      )
    )
  end
  if (e.xruns or 0) > 0 then
    h.warn(
      e.xruns .. " dropouts (xruns) so far",
      { "a larger block (:audio.device) or fewer plugins", ":doctor runs a guided check" }
    )
  end
  if (e.devices_stopped or 0) > 0 then
    h.error(e.devices_stopped .. " devices stopped working", "`:fx` shows which; restart them from the devices view")
  end
  local inputs = api.midi_inputs()
  h.info(#inputs == 0 and "no MIDI inputs" or (#inputs .. " MIDI inputs"))
end, { desc = "the audio engine and MIDI" })

M.register("plugins", function(h)
  local by = {}
  for _, t in ipairs(api.device_types()) do
    local format = t.format or "built in"
    by[format] = (by[format] or 0) + 1
  end
  local parts, plugins = {}, 0
  for format, n in pairs(by) do
    parts[#parts + 1] = n .. " " .. format
    if format ~= "built in" and format ~= "lua" then plugins = plugins + n end
  end
  table.sort(parts)
  h.info("devices: " .. table.concat(parts, ", "))
  if plugins == 0 then
    h.warn("no plugins found", {
      "they are looked for where CLAP, LV2 and VST3 plugins are installed, and in CLAP_PATH, LV2_PATH, VST3_PATH",
      "`--no-plugins` leaves them out",
      ":plugins.rescan looks again",
    })
  else
    h.ok(plugins .. " plugins")
  end
end, { desc = "plugin hosting" })

M.register("ffmpeg", function(h)
  local path = M.executable(paw.opt.ffmpeg or "ffmpeg")
  if path then
    h.ok("ffmpeg at " .. path)
  else
    h.warn("ffmpeg not found (paw.opt.ffmpeg = " .. tostring(paw.opt.ffmpeg) .. ")", {
      "renders to MP3, Ogg and Opus need it; WAV and FLAC do not",
      "install ffmpeg, or set paw.opt.ffmpeg to its path",
    })
  end
end, { desc = "renders to compressed formats" })

M.register("git", function(h)
  if not M.executable("git") then return h.info("git not found: project folders work without it") end
  local pipe = io.popen("git config --get diff.paw-midi2.textconv 2>/dev/null")
  local driver = pipe and pipe:read("*l")
  if pipe then pipe:close() end
  if driver and driver ~= "" then
    h.ok("git shows MIDI clip files as text with `" .. driver .. "`")
  else
    h.warn(
      "git shows the MIDI clip files (.midi2) of a project as binary",
      { 'set it one time: git config --global diff.paw-midi2.textconv "paw clip cat"' }
    )
  end
end, { desc = "project folders in version control" })

-- A few characters of each way to draw a curve in cells (paw.draw.curve_glyphs).
local CURVE_SAMPLES = {
  sextant = function() return paw.draw.sextant(48) .. paw.draw.sextant(12) .. paw.draw.sextant(3) end,
  braille = function() return paw.draw.braille(0xC0) .. paw.draw.braille(0x24) .. paw.draw.braille(0x09) end,
  line = function() return paw.opt.ascii and "_-'" or "▁─▔" end,
}

--- Whether the characters of curves show depends on the font of the
--- terminal, which paw cannot read: the check shows them, and the person
--- sees whether they are drawn.
local function curve_glyphs(h)
  local kind = paw.draw.curve_glyphs()
  local advice = {
    "a box, a question mark or a gap means that the font of the terminal does not have them",
    "then `:set curve_glyphs=braille` or `:set curve_glyphs=line` (`:set ascii` for plain ASCII)",
  }
  if kind == "line" then advice = nil end
  h.info(string.format("automation lanes draw curves with %s characters: %s", kind, CURVE_SAMPLES[kind]()), advice)
end

M.register("terminal", function(h)
  curve_glyphs(h)
  if not api.ui_attached() then return h.info("no terminal attached (headless, or a script)") end
  local caps = api.ui_caps()
  if caps.graphics then
    h.ok(
      string.format(
        "pictures through the kitty graphics protocol, cells of %dx%d pixels",
        caps.cell and caps.cell.w or 0,
        caps.cell and caps.cell.h or 0
      )
    )
  else
    h.warn("this terminal shows no pictures: curves and waveforms are drawn in cells", {
      "kitty, WezTerm, Ghostty and Konsole show them",
      "not inside tmux",
      "paw.opt.graphics turns them off by choice",
    })
  end
  if paw.opt.graphics == false then h.info("paw.opt.graphics is off") end
end, { desc = "the terminal interface" })

M.register("window", function(h)
  local r = paw.frontend.window_renderer
  if not r then return h.info("no graphical window has started (paw-gui)") end
  if r.software then
    -- The likely cause first, then the others.
    local advice, causes = {}, { "asked", "libgl", "driver", "no-card" }
    local first = paw.frontend.software_advice[r.cause]
    if first then advice[1] = first end
    for _, cause in ipairs(causes) do
      if cause ~= r.cause then advice[#advice + 1] = paw.frontend.software_advice[cause] end
    end
    h.warn("the window draws on the processor, not on a graphics card: " .. tostring(r.renderer), advice)
  else
    h.ok("the window draws on the graphics card: " .. tostring(r.renderer))
  end
  local fps = paw.opt.window_fps
  if fps == "auto" then fps = r.software and 15 or 30 end
  h.info("while the song plays, the window draws " .. tostring(fps) .. " frames a second (paw.opt.window_fps)")
end, { desc = "the graphical window and the OpenGL that draws it" })

--- The name of a font for Japanese and Chinese text on this computer, or nil.
--- `:checkhealth fonts` reports it.
function M.cjk_font()
  -- A field of the module: a test puts a fake in it and reads no font of the machine.
  local p = io.popen("fc-list ':lang=ja:outline=true' family 2>/dev/null")
  local found = p and p:read("*l")
  if p then p:close() end
  if found and found ~= "" then return found end
end

M.register("fonts", function(h)
  local found = M.cjk_font()
  if found then
    h.ok("a font for Japanese and Chinese text in the window: " .. found)
  else
    h.warn(
      "no font for Japanese or Chinese text found by fontconfig",
      { "lyrics in those scripts show as boxes in the window", "install Noto Sans CJK, or any CJK font" }
    )
  end
end, { desc = "fonts the window falls back on" })

M.register("extensions", function(h)
  local list = paw.ext.list()
  if #list == 0 then h.info("no extensions loaded") end
  for _, e in ipairs(list) do
    local name = e.name .. (e.version and " " .. e.version or "")
    if e.ok then
      local wants = e.manifest and e.manifest.requires
      local needs = {}
      for other, want in pairs(wants or {}) do
        needs[#needs + 1] = other .. " " .. tostring(want)
      end
      table.sort(needs)
      h.ok(name .. (#needs > 0 and " (requires " .. table.concat(needs, ", ") .. ")" or ""))
      for _, o in ipairs(e.overrides or {}) do
        h.warn(
          string.format("%s replaces the %s %s of %s", e.name, o.kind, o.what, o.of),
          { "the extension loaded last wins: load them in the other order, or map it again in init.lua" }
        )
      end
      -- A key of the core given another meaning. A wrap that keeps what the
      -- key does (and so its description) is not.
      for _, item in ipairs(e.owned and e.owned.keys or {}) do
        local old, new = item.old, item.value
        if old and new and not old.ext and old.desc ~= new.desc then
          h.warn(
            string.format(
              "%s replaces the key %s of the core: “%s” becomes “%s”",
              e.name,
              new.lhs .. " (" .. new.mode .. (new.scope ~= "global" and ", " .. new.scope or "") .. ")",
              tostring(old.desc),
              tostring(new.desc)
            ),
            { "a key means the same in every view: give the extension's action a key of its own" }
          )
        end
      end
    elseif e.needs_unmet then
      h.error(name .. ": " .. e.error, { "a build of paw with these features loads it (`paw.api.build()`)" })
    else
      h.error(
        name .. ": " .. tostring(e.error):match("^[^\n]*"),
        { ":messages has the whole error", ":ext.load " .. e.name .. " tries again once it is fixed" }
      )
    end
  end
end, { desc = "extensions, their versions and what they require" })

M.register("teal", function(h)
  local files = {}
  for file in pairs(paw.lang.problems) do
    files[#files + 1] = file
  end
  table.sort(files)
  if #files == 0 then h.ok("no type errors in the files in Teal loaded") end
  for _, file in ipairs(files) do
    local list = paw.lang.problems[file]
    h.warn(string.format("%s: %d type error%s; it loads as it is", file, #list, #list == 1 and "" or "s"), list)
  end
end, { desc = "the types of the configuration and extensions written in Teal" })

M.register("events", function(h)
  local names = paw.events.undeclared()
  if #names == 0 then
    h.ok("each event that a handler waits for by its name or its family is one that paw or an extension declares")
  end
  for _, name in ipairs(names) do
    h.warn(
      "a handler waits for `" .. name .. "`, which matches no event that a part of paw or an extension declares",
      { "check the name for a typo", "an extension declares its own events with paw.events.event(name)" }
    )
  end
end, { desc = "the names of the events that handlers wait for" })

M.register("derived", function(h) require("paw.derived").health(h) end, {
  desc = "the data paw derives from the project (the chords of the song): values, memory and limits",
})

paw.command("checkhealth", function(ctx)
  local names = {}
  for _, name in ipairs(ctx.args) do
    names[#names + 1] = tostring(name)
  end
  local results = M.check(names)
  paw.ui.page("Health", M.lines(results))
  return M.worst(results)
end, {
  desc = "Check the program and the extensions, and say what to do about what is wrong: `checkhealth audio`",
  complete = function() return M.names() end,
})

return M
