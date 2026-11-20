-- The sampler's kind of track, its commands, and the instrument picker.
local api = paw.api
local sampler = require("sampler")
local command = paw.command

local exists = paw.api.fs_exists

--- Whether words name a file rather than words to find an instrument by:
--- a path, or a name with an instrument's extension.
local function file_like(text)
  return text:find("/", 1, true) ~= nil or text:lower():match("%.sfz$") ~= nil or text:lower():match("%.dspreset$") ~= nil
end

--- The sampler device of the cursor's track, or a warning.
local function cursor_device()
  local id = paw.cursor.track_id()
  local device = id and sampler.device_of(id)
  if not device then paw.notify("not a sampler track: `:sampler.track` adds one", "warn") end
  return device, id
end

local function loaded(d)
  paw.notify("sampler: " .. sampler.summary(d))
  for _, w in ipairs(d.warnings or {}) do
    paw.notify("sampler: " .. w, "warn")
  end
end

local function load(device, path)
  local d, err = sampler.load(device, path)
  if not d then return paw.notify("sampler: " .. tostring(err), "error") end
  loaded(d)
  return d
end

--- Choose the instrument of a track's sampler from the library folders,
--- each heard as the selection rests on it: loaded as a trial and played
--- a short phrase through the track. Escape puts back what was there.
function sampler.pick(track_id, query)
  local device = sampler.device_of(track_id)
  if not device then return paw.notify("the track has no sampler", "warn") end
  local roots = sampler.roots()
  paw.pick({
    title = "Instruments",
    items = function() return sampler.instruments() end,
    query = query,
    format = function(i)
      return string.format("%-24s %-4s %s", i.name, i.format == "dspreset" and "DS" or "SFZ", i.folder)
    end,
    primary = function(i) return i.name end,
    empty = "no instruments in " .. table.concat(roots, ", ") .. " (the folders are paw.opt.sampler_libraries)",
    on_choose = function(i) load(device, i.path) end,
    audition_key = "sampler.instrument",
    -- Reading a library takes a moment: wait a little longer before trying one.
    audition_delay = function(_, ms) return ms * 2 end,
    audition = function(i)
      local d, err = paw.audition.try(function() return sampler.load(device, i.path) end)
      if not d then return i.name .. " · " .. tostring(err) end
      paw.audition.phrase(track_id, sampler.phrase(d), { length = 4, label = d.name })
      return { label = sampler.summary(d), keep = function() loaded(d) end }
    end,
    preview = function(i)
      local lines = { { text = i.name, style = "Title" }, i.path }
      local d = sampler.known(device)
      if d and d.path == i.path then
        if type(d.range) == "table" and d.range[1] then
          lines[#lines + 1] = "plays " .. paw.music.name(d.range[1]) .. " to " .. paw.music.name(d.range[2])
        end
        for _, a in ipairs(d.articulations or {}) do
          local ks = a.keyswitch and ("  keyswitch " .. paw.music.name(a.keyswitch)) or ""
          lines[#lines + 1] = string.format("  %-24s %-6s%s", a.name, a.m2 or "", ks)
        end
        if #(d.warnings or {}) > 0 then lines[#lines + 1] = #d.warnings .. " things in the file are not played" end
      end
      return lines
    end,
  })
end

-- A sampler track is a kind of track (`paw.track_kinds`): `:track.add
-- sampler`, `:track.new`, the window's menus that make a track, the
-- header's `S` and `K` come from here. Its clips open in the piano roll.
paw.track_kinds.define("sampler", {
  title = "Sampler track",
  letter = "S",
  desc = "an SFZ or Decent Sampler instrument, played by paw's sampler",
  -- The device first, then the instrument: a file named after the kind
  -- (`track.add sampler ~/sfz/Violins.sfz`), or words to find one by, or
  -- chosen from the list (not with `ask = false`).
  create = function(track, args)
    if not sampler.device_of(track.id) then
      if not sampler.available() then
        error("paw's sampler plugin is not installed: build extensions/sampler/native (see its README)", 0)
      end
      track:add_device(sampler.KIND, nil, { index = 1 })
    end
    local device = sampler.device_of(track.id)
    local words = args.words or {}
    local path = args.path or (#words == 1 and words[1]:gsub("^~", os.getenv("HOME") or "~"))
    if path and exists(path) then
      load(device, path)
    elseif path and file_like(path) then
      paw.notify("sampler: no such file: " .. path, "error")
    elseif args.ask ~= false then
      sampler.pick(track.id, #words > 0 and table.concat(words, " ") or nil)
    end
  end,
  describe = function(id)
    local device = sampler.device_of(id)
    return device and sampler.summary(sampler.known(device)) or nil
  end,
  is = function(id) return sampler.device_of(id) ~= nil end,
})

command("sampler.track", function(ctx)
  local args = { kind = "sampler", name = ctx.args.name or "Sampler" }
  for i, word in ipairs(ctx.args) do args[i] = word end
  paw.cmd("track.add", args)
end, { desc = "Add a sampler track, with an instrument: a file, words to find one by, or chosen from a list" })

command("sampler.load", function(ctx)
  local device, track = cursor_device()
  if not device then return end
  local text = ctx.args[1] and (tostring(ctx.args[1]):gsub("^%s+", ""):gsub("%s+$", "")) or ""
  local path = text:gsub("^~", os.getenv("HOME") or "~")
  if path ~= "" and exists(path) then return load(device, path) end
  if file_like(path) then return paw.notify("sampler: no such file: " .. path, "error") end
  sampler.pick(track, text ~= "" and text or nil)
end, { desc = "Choose the sampler's instrument: a file (`sampler.load ~/sfz/Violins.sfz`), or from a list where each is heard (`sampler.load violin`)", raw = true, complete = "files" })

command("sampler.info", function()
  local device = cursor_device()
  if not device then return end
  local d = sampler.describe(device)
  if not d then return paw.notify("sampler: not running", "warn") end
  local lines = { sampler.summary(d) }
  if d.path and d.path ~= "" then lines[#lines + 1] = d.path end
  if d.error then lines[#lines + 1] = d.error end
  if type(d.range) == "table" and d.range[1] then
    lines[#lines + 1] = "plays " .. paw.music.name(d.range[1]) .. " to " .. paw.music.name(d.range[2])
  end
  for _, a in ipairs(d.articulations or {}) do
    lines[#lines + 1] = string.format("%s (%s)%s", a.name, a.m2,
      a.keyswitch and (", keyswitch " .. paw.music.name(a.keyswitch)) or "")
  end
  for _, w in ipairs(d.warnings or {}) do lines[#lines + 1] = "not played: " .. w end
  paw.notify(table.concat(lines, "\n"))
end, { desc = "What the sampler's instrument is: range, articulations, what it does not play" })

table.insert(paw.frontend.menus.track, { label = "Sampler instrument…", command = "sampler.load" })
