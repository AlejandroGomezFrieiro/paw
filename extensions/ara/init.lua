-- ARA plugins for paw: a plugin that reads a whole clip (Melodyne-style
-- editors, audio-to-MIDI) gets the audio clips of its track and the song's
-- tempo, plays them, and keeps its edits in the project. See README.md.
paw.option.define("ara_bridge", "") -- where paw-ara.so is; `lib/` beside the extension when empty
paw.option.define("ara_unpitched_key", 60, { min = 0, max = 127 }) -- the key of a note the plugin heard without a pitch

local api = paw.api
local ara = require("ara")
package.loaded["paw.ara"] = ara

-- The attachment is loaded before the project's plugins are made, so that
-- an ARA plugin in a saved project gets its clips again.
local loaded, why = ara.attach()
if not loaded then api.log("ara: " .. tostring(why)) end

local command = paw.command

--- The first ARA device on the cursor's track, or a warning.
local function cursor_device()
  local track = paw.cursor.track_id()
  local device = track and ara.devices(track)[1]
  if not device then paw.notify("ara: no ARA plugin on this track: `:ara.add` puts one there", "warn") end
  return device, track
end

local function add(track, kind)
  local id, err = ara.add(track, kind)
  if not id then return paw.notify("ara: " .. tostring(err), "error") end
  paw.notify("ara: " .. ara.summary(id))
end

command("ara.add", function(ctx)
  local track = paw.cursor.track_id()
  if not track then return paw.notify("ara: no track", "warn") end
  local kind = tostring(ctx.args[1] or ""):match("^%s*(.-)%s*$")
  if kind ~= "" then
    if not kind:find(":", 1, true) then kind = "clap:" .. kind end
    return add(track, kind)
  end
  local kinds = ara.kinds()
  if #kinds == 0 then return paw.notify("ara: paw knows no ARA plugin (`:plugins.rescan` reads the plugin files again)", "warn") end
  paw.pick({
    title = "ARA plugins",
    items = function() return kinds end,
    format = function(t) return string.format("%-28s %s", t.name, t.vendor or "") end,
    on_choose = function(t) add(track, t.kind) end,
  })
end, {
  desc = "Put an ARA plugin first on the track of the cursor, to play and edit its audio clips: `ara.add org.ara-audio.examples.testplugin.clap`",
  complete = function()
    local out = {}
    for _, t in ipairs(ara.kinds()) do out[#out + 1] = (t.kind:gsub("^clap:", "")) end
    return out
  end,
})

command("ara.status", function()
  local device = cursor_device()
  if device then paw.notify("ara: " .. ara.summary(device)) end
end, { desc = "Say what the ARA plugin of the track has: the plugin, its clips, its edits" })

--- Ask again until the plugin has found the notes, then make the clip in
--- one turn, so that it is one undo step.
local function notes_into_clip(device, track, tries)
  local ok, notes, progress = pcall(ara.notes, device)
  if not ok then return paw.notify("ara: " .. tostring(notes), "error") end
  if not notes then
    if tries <= 0 then return paw.notify("ara: the plugin did not finish its analysis", "warn") end
    if tries % 10 == 0 then paw.notify(string.format("ara: the plugin listens to the clips (%d%%)", math.floor(progress * 100))) end
    return paw.defer(function() notes_into_clip(device, track, tries - 1) end, 100)
  end
  if #notes == 0 then return paw.notify("ara: the plugin found no notes", "warn") end
  local first, last = math.huge, 0
  for _, n in ipairs(notes) do
    first = math.min(first, n.start)
    last = math.max(last, n.start + n.length)
  end
  local start = math.floor(first)
  for _, n in ipairs(notes) do n.start = n.start - start end
  local name = api.track_get(track).name .. " notes"
  local index = 1
  for i, id in ipairs(api.track_list()) do
    if id == track then index = i + 1 end
  end
  local midi = paw.add_track({ name = name, index = index })
  midi:add_clip({ start = start, length = math.ceil(last - start), notes = notes, name = name })
  api.undo_label("ara.notes")
  paw.notify(string.format("ara: %d notes on the track %s", #notes, name))
end

command("ara.notes", function()
  local device, track = cursor_device()
  if device then notes_into_clip(device, track, 600) end
end, { desc = "Make a MIDI clip of the notes that the ARA plugin heard in the clips, on a new track under this one" })

command("ara.edit", function()
  local device = cursor_device()
  if not device then return end
  local ok, err = pcall(api.device_editor, device, true)
  if not ok then paw.notify("ara: the plugin has no window: " .. tostring(err), "warn") end
end, { desc = "Open the window of the ARA plugin of the track" })

local keymap = paw.keymap
keymap.set("<localleader>aa", "ara.add", { view = "arrange", desc = "Put an ARA plugin first on the track" })
keymap.set("<localleader>an", "ara.notes", { view = "arrange", desc = "A MIDI clip of the notes the ARA plugin heard" })
keymap.set("<localleader>ae", "ara.edit", { view = "arrange", desc = "Open the window of the ARA plugin" })
keymap.set("<localleader>as", "ara.status", { view = "arrange", desc = "What the ARA plugin of the track has" })

-- `:checkhealth ara`: the attachment found and loaded.
paw.health.register("ara", function(h)
  local path = ara.bridge_path()
  if not path then
    return h.error("paw-ara.so not found", { "it is built with the extension's package (extensions/ara/nix)",
      "or set paw.opt.ara_bridge to where it is" })
  end
  if paw.plugins.attached.ara then h.ok("the attachment " .. path) else h.error("paw-ara.so did not load", path) end
  local kinds = ara.kinds()
  if #kinds == 0 then h.info("no ARA plugin found: `:plugins.rescan` reads the plugin files again")
  else for _, t in ipairs(kinds) do h.ok("ARA plugin: " .. t.name) end end
end, { desc = "ARA plugins" })
