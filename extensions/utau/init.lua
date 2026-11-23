-- UTAU singing for paw: vocal tracks sung by OpenUtau's engines through
-- its own engine, paw-utau-engine (engine/). See README.md beside this file.
local api = paw.api

paw.option.define("utau_engine", "") -- path to paw-utau-engine; found by itself when empty
paw.option.define("utau_openutau_dir", "") -- OpenUtau's data folder (Singers, Resamplers); read only
paw.option.define("utau_data_dir", "") -- the engine's own data folder; its default when empty
paw.option.define("utau_cache_dir", "") -- the engine's render cache; its default when empty
paw.option.define("utau_log_level", "info")
paw.option.define("utau_default_lyric", "a") -- sung by notes that have no lyric
paw.option.define("utau_drafts", true) -- quick drafts of DiffSinger phrases before final quality
paw.option.define("utau_final_delay", 1500) -- ms of quiet after an edit before rendering final quality
paw.option.define("utau_render_timeout", 600) -- seconds an offline render waits for the singing
paw.option.define("utau_openutau", "") -- command that opens a .ustx in OpenUtau; `OpenUtau` when empty

local utau = require("utau")

utau.engine.reset_stale()

-- Any edit may change what is sung; the sync works out what did.
for _, pattern in ipairs({ "clip.*", "track.*", "device.*", "lane.*", "project.changed", "project.loaded" }) do
  paw.on(pattern, function() utau.schedule() end)
end
paw.on("project.loaded", function() utau.clear_voices() end)
-- The curves under a vocal clip go where the clip goes, in the same undo step.
require("utau.follow").attach()
paw.on("device.added", function() utau.assign_voices() end)
for _, name in ipairs({ "transport.play", "transport.stop", "transport.seek" }) do
  paw.on(name, function() utau.send_transport() end)
end

-- An offline render is only deterministic once every phrase is final.
paw.on("render.before", function()
  local ok, why = utau.finish(paw.opt.utau_render_timeout)
  if not ok then paw.notify("utau: rendering without finished singing: " .. tostring(why), "warn") end
end)

paw.every(25, function()
  if utau.engine.pump() then api.ui_redraw() end
end)

require("utau.editor")
require("utau.gui")
require("utau.commands")
require("utau.editor_keys")

utau.schedule()

-- `:checkhealth utau`: the engine, and whether it is up.
paw.health.register("utau", function(h)
  local engine = utau.engine.find()
  if engine then
    h.ok("the engine at " .. engine)
  else
    h.error(
      "paw-utau-engine not found",
      { "set paw.opt.utau_engine or $PAW_UTAU_ENGINE to it", "or run the program built with it: nix run .#paw-utau" }
    )
  end
  local state = utau.engine.state
  if state == "failed" then
    h.error("the engine failed: " .. tostring(utau.engine.reason), ":messages has more")
  elseif state then
    h.info("the engine is " .. state)
  end
end, { desc = "singing synthesis" })
