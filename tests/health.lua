-- `:checkhealth`: the core's checks, an extension's, and how they are
-- reported. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq

local function pager_text()
  local out = {}
  for _, line in ipairs(paw.ui.views:get("pager").lines) do
    out[#out + 1] = line.text
  end
  return table.concat(out, "\n")
end

local function levels(result)
  local out = {}
  for _, item in ipairs(result.items) do
    out[#out + 1] = item.level
  end
  return table.concat(out, " ")
end

--- The fonts of the machine are not read: the fonts check gets `family`.
local real_cjk_font = paw.health.cjk_font
local function cjk_font(family)
  paw.health.cjk_font = function() return family end
  T.after(function() paw.health.cjk_font = real_cjk_font end)
end

-- The errors a test means to cause are read, as `:messages` reads them,
-- so that the key line of the tests after it does not point at them.
local function read_errors()
  paw.commands.exec("messages")
  paw.ui.close()
end

test("checkhealth: the core's checks each report, with a level and advice", function()
  cjk_font(nil)
  for _, name in ipairs({ "paw", "audio", "plugins", "ffmpeg", "terminal", "window", "fonts", "extensions" }) do
    local r = paw.health.run(name)
    eq(#r.items > 0, true, name .. " says something")
    for _, item in ipairs(r.items) do
      eq(
        ({ ok = true, info = true, warn = true, error = true })[item.level],
        true,
        name .. "'s level " .. tostring(item.level)
      )
    end
  end
  local paw_check = paw.health.run("paw")
  eq(paw_check.items[1].text:find("Lua API " .. paw.api.version, 1, true) ~= nil, true, "the API version")
  local audio = paw.health.run("audio")
  eq(audio.items[1].level, "warn", "the null backend the suite runs on is a warning")
  eq(#audio.items[1].advice > 0, true, "with advice")
end)

test("checkhealth fonts: names the font for Japanese and Chinese text, or warns that there is none", function()
  cjk_font("Noto Sans CJK JP")
  local found = paw.health.run("fonts").items[1]
  eq(
    found.level .. " " .. found.text,
    "ok a font for Japanese and Chinese text in the window: Noto Sans CJK JP",
    "a font"
  )
  cjk_font(nil)
  local none = paw.health.run("fonts").items[1]
  eq(none.level .. " " .. none.text, "warn no font for Japanese or Chinese text found by fontconfig", "no font")
end)

test("checkhealth: the command shows every check, or the ones named", function()
  cjk_font(nil)
  paw.cmd("checkhealth")
  local text = pager_text()
  paw.ui.close()
  for _, name in ipairs({ "paw", "audio", "plugins", "extensions" }) do
    eq(
      text:find("\n" .. name .. ": ", 1, true) ~= nil or text:sub(1, #name + 2) == name .. ": ",
      true,
      name .. " is in it"
    )
  end
  eq(text:find("- WARN the null audio backend", 1, true) ~= nil, true, "levels shown as Neovim shows them")
  eq(text:find("    - start without --audio null", 1, true) ~= nil, true, "advice under its item")
  local worst = paw.cmd("checkhealth", { "ffmpeg" })
  eq(pager_text():match("^ffmpeg: ") ~= nil, true, "one check by name")
  eq(pager_text():find("audio:", 1, true), nil, "and only it")
  eq(worst == "ok" or worst == "warn", true, "it returns the worst level")
  paw.ui.close()
  local completions = paw.commands.complete("checkhealth au")
  local found = false
  for _, c in ipairs(completions) do
    found = found or (c.text or ""):match("audio$") ~= nil
  end
  eq(found, true, "names complete")
end)

test("checkhealth: the window says whether it draws on a graphics card, and why not", function()
  local was = paw.frontend.window_renderer
  paw.frontend.window_renderer = nil
  local r = paw.health.run("window")
  eq(levels(r), "info", "no window yet")
  paw.frontend.window_renderer_set({ renderer = "AMD Radeon 890M (radeonsi)", version = "4.6", software = false })
  r = paw.health.run("window")
  eq(levels(r), "ok info", "on the card, and the frames a second")
  eq(r.items[2].text:find("draws 30 frames a second", 1, true) ~= nil, true, r.items[2].text)
  eq(r.items[1].text:find("AMD Radeon 890M", 1, true) ~= nil, true, "it names the renderer")
  -- On the processor: said once when the window starts, with what to do.
  local before = paw.ui.messages[#paw.ui.messages]
  paw.frontend.window_renderer_set({
    renderer = "llvmpipe (LLVM 19.1.7, 256 bits)",
    version = "4.5",
    software = true,
    cause = "asked",
  })
  local said = paw.ui.messages[#paw.ui.messages]
  eq(paw.ui.messages[#paw.ui.messages - 1], before, "one message (the list keeps the last 500)")
  eq(said.level, "warn", "a warning")
  eq(said.text:find("draws on the processor (llvmpipe)", 1, true) ~= nil, true, "in words: " .. said.text)
  eq(said.text:find("PAW_GUI_RENDERER", 1, true) ~= nil, true, "with the fix for its cause")
  r = paw.health.run("window")
  eq(levels(r), "warn info", "a warning in :checkhealth")
  eq(r.items[2].text:find("draws 15 frames a second", 1, true) ~= nil, true, "fewer on the processor")
  eq(r.items[1].advice[1]:find("PAW_GUI_RENDERER", 1, true) ~= nil, true, "the likely cause first")
  eq(#r.items[1].advice, 4, "and the other usual causes")
  paw.frontend.window_renderer_set({
    renderer = "llvmpipe (LLVM 19.1.7, 256 bits)",
    version = "4.5",
    software = true,
    cause = "driver",
  })
  eq(paw.health.run("window").items[1].advice[1]:find("driver", 1, true) ~= nil, true, "no driver or DRI3 first")
  paw.frontend.window_renderer = was
  read_errors()
end)

test("checkhealth: an extension's check is its own, and a check that fails is an error of its own", function()
  local dir = T.scratch .. "/health-ext"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(
    dir .. "/healthy.lua",
    [[
    paw.health.register("healthy", function(h)
      h.ok("all well")
      h.warn("but this", { "do that", "or the other" })
    end, { desc = "a test" })
    paw.health.register("broken", function(h) error("oops") end)
  ]]
  )
  paw.ext.load(dir .. "/healthy.lua")
  local r = paw.health.run("healthy")
  eq(levels(r), "ok warn", "what it reported")
  eq(r.items[2].advice[2], "or the other", "with advice")
  eq(r.desc, "a test", "and what it checks")
  local b = paw.health.run("broken")
  eq(levels(b), "error", "a check that fails")
  eq(b.items[1].text:find("oops", 1, true) ~= nil, true, "says why")
  eq(levels(paw.health.run("nowhere")), "error", "a name with no check")
  local owned = ""
  for _, group in ipairs(paw.ext.provides("healthy")) do
    if group.kind == "health" then owned = table.concat(group.items, " ") end
  end
  eq(owned, "broken healthy", "the extension owns its checks")
  eq(paw.health.run("extensions").items[1] ~= nil, true, "the extensions check runs")
  paw.ext.unload("healthy")
  eq(paw.health.checks.healthy, nil, "and they go with it")
end)

test("checkhealth: the extensions check lists versions and requirements, and a failed one is an error", function()
  T.after(read_errors)
  T.write_file(T.scratch .. "/health-bad.lua", "error('cannot start')")
  local bad = paw.ext.load(T.scratch .. "/health-bad.lua")
  eq(bad.ok, false, "it failed")
  local found
  for _, item in ipairs(paw.health.run("extensions").items) do
    if item.text:find("^health%-bad") then found = item end
  end
  eq(found and found.level, "error", "the failed extension is an error")
  eq(found.text:find("cannot start", 1, true) ~= nil, true, "with its error")
  paw.ext.unload("health-bad")
  for _, name in ipairs({ "utau", "sampler" }) do
    if paw.health.checks[name] then eq(#paw.health.run(name).items > 0, true, name .. "'s own check reports") end
  end
end)

test(
  "checkhealth: a handler that waits for an event by a misspelled name or family is in the log once and in the check",
  function()
    T.start()
    local function logged(name)
      local count = 0
      for _, line in ipairs(paw.api.log_get()) do
        if line:find("`" .. name .. "`", 1, true) then count = count + 1 end
      end
      return count
    end
    local typo, real = paw.on("projct.saved", function() end), paw.on("project.saved", function() end)
    local again, option = paw.on("projct.saved", function() end), paw.on("option.changed", function() end)
    -- Patterns: a family with no declared event in it, one with, and every event.
    local empty, family, every =
      paw.on("undo.*", function() end), paw.on("track.*", function() end), paw.on("*", function() end)
    T.after(function()
      for _, id in ipairs({ typo, real, again, option, empty, family, every }) do
        paw.off(id)
      end
    end)
    eq(logged("projct.saved"), 1, "the misspelled name, one time for two handlers")
    eq(logged("undo.*"), 1, "the family that holds no event (the events are undo and redo)")
    eq(logged("project.saved") + logged("option.changed"), 0, "not the names that paw declares")
    eq(logged("track.*") + logged("*"), 0, "not a family of declared events, or every event")
    T.keys(":checkhealth events<CR>")
    local text = pager_text()
    paw.ui.close()
    eq(text:find("- WARN a handler waits for `projct.saved`", 1, true) ~= nil, true, ":checkhealth events names it")
    eq(text:find("- WARN a handler waits for `undo.*`", 1, true) ~= nil, true, "and the empty family")
    eq(text:find("project.saved", 1, true), nil, "and only the misspelled ones")
  end
)
