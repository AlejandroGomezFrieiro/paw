-- How late each articulation of an instrument sounds, measured: one note
-- per articulation is rendered offline through the part's own devices
-- (any plugin, a Lua device, paw's sampler), each after what tells the
-- instrument its articulation, and where its sound starts is found in the
-- rendering. The delays found go into the instrument's map (`delay =
-- "-80ms"`), and from there into the part's downgrade map, so that the
-- kernel plays those notes that much earlier and they sit on the grid.
--
-- The onset: the rendering is cut into 1 ms blocks from the note's start;
-- the first block whose peak reaches 20 dB under the loudest block of the
-- note's first two seconds is where its sound starts.
local api = paw.api
local art = require("articulations")
local maps = art.maps
local toml = art.toml

local M = {}

M.method = "the first 1 ms block reaching 20 dB under the note's loudest, in the first 2 s after it"

local SPACING = 8 -- beats between two articulations' notes
local LENGTH = 4 -- beats a note is held
local LEAD = 0.5 -- beats before a note its keyswitch and controllers come
local WINDOW = 2 -- seconds looked at after a note
local BELOW = 10 ^ (-20 / 20)

local function song_end()
  local finish = 0
  for _, id in ipairs(api.part_list()) do
    for _, c in ipairs(api.clip_list(id)) do
      finish = math.max(finish, c.start + c.length)
    end
  end
  return finish
end

--- The pitch an articulation is measured on: the middle of its range, the
--- comfortable range's or the map's, else middle C.
local function pitch_of(map, a)
  local r = a.range or map.comfortable or map.range
  return r and math.floor((r[1] + r[2]) / 2) or 60
end

--- The notes and controller moves that play each articulation once, in a
--- clip that starts at beat 0: `notes, controls, at` (`at[i]` the beat of
--- the i-th articulation's note).
function M.score(map)
  local notes, controls, at = {}, {}, {}
  for i, a in ipairs(map.arts) do
    local t = 1 + (i - 1) * SPACING
    at[i] = t
    for _, e in ipairs(a.events) do
      if e.type == "note" then
        notes[#notes + 1] = { pitch = e.key, start = t - LEAD, length = 0.1, velocity = e.velocity or 100 }
      elseif e.type == "hold" then
        notes[#notes + 1] = { pitch = e.key, start = t - LEAD, length = LEAD + LENGTH, velocity = e.velocity or 100 }
      elseif e.type == "cc" then
        controls[#controls + 1] = { start = t - LEAD, type = "cc", number = e.number, value = e.value / 127 }
      elseif e.type == "program" then
        controls[#controls + 1] = { start = t - LEAD, type = "program", program = e.program, bank = e.bank }
      elseif e.type == "bend" then
        controls[#controls + 1] = { start = t - LEAD, type = "bend", value = e.value }
        controls[#controls + 1] = { start = t + LENGTH, type = "bend", value = 0 }
      end
    end
    local note = { pitch = pitch_of(map, a), start = t, length = LENGTH, velocity = 100 }
    for k, v in pairs(art.attr_fields(note, a.attr)) do
      note[k] = v
    end
    notes[#notes + 1] = note
  end
  table.sort(controls, function(x, y) return x.start < y.start end)
  return notes, controls, at
end

--- Render one note of each articulation through a part and find where each
--- one's sound starts. Returns `{ { art, onset (ms, nil when silent), delay
--- (the map's value: minus the onset), now (the map's delay) } }`.
function M.measure(part)
  local map = art.map_of(part)
  if not map then error("the part has no articulation map: :art.map", 0) end
  local notes, controls, at = M.score(map)
  local start = paw.time.bar_ceil(song_end() + 1e-9) + 4
  local length = at[#at] + SPACING
  local path = api.env().data_dir .. "/articulations/measure.wav"
  api.fs_mkdir(path:match("^(.*)/"))
  local info
  paw.audition.try(function()
    -- The sound as the instrument makes it: the core plays notes early by
    -- the delays already in the map, which is not what is measured.
    local sent = art.attr_map(part)
    if sent and pcall(api.part_get, part) and api.part_get(part).attr_map then
      local plain = paw.util.merge(sent, { arts = {} })
      plain.delay = nil
      for code, e in pairs(sent.arts or {}) do
        plain.arts[code] = type(e) == "table" and { out = e.out } or e
      end
      api.part_set(part, "attr_map", plain)
    end
    local clip = paw.part(part):add_clip({ start = start, length = length, name = "measure", notes = notes })
    if #controls > 0 then clip:set_controls(controls) end
    paw.flush()
    info = paw.render(path, { start = start, ["end"] = start + length, parts = { part }, tail = 0, bits = 16 })
  end)
  paw.audition.revert()
  local origin = paw.time.to_seconds(start)
  local out = {}
  local sound = api.sound_envelope(info.path or path)
  for i, a in ipairs(map.arts) do
    local from = paw.time.to_seconds(start + at[i]) - origin
    local b = sound.blocks(from, from + WINDOW, 1)
    local loudest = 0
    for _, v in ipairs(b) do
      loudest = math.max(loudest, v)
    end
    local onset
    if loudest > 1e-4 then
      for k, v in ipairs(b) do
        if v >= loudest * BELOW then
          onset = k - 1
          break
        end
      end
    end
    out[i] = { art = a, onset = onset, delay = onset and -onset or nil, now = a.delay }
  end
  return out
end

--- A map's text with each articulation's `delay` set as `delays[id]` says
--- (milliseconds; nil leaves it), or nil and why.
function M.rewrite(text, delays)
  local lines, section = {}, nil
  local done = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local head = line:match("^%s*%[([^%]]+)%]")
    if head then section = head end
    if section == "art" and not head then
      for id, ms in pairs(delays) do
        local key = toml.key(id)
        local prefix = line:match("^(%s*" .. key:gsub("%p", "%%%0") .. "%s*=%s*{)")
        if prefix and line:find("}", #prefix + 1, true) then
          local value = 'delay = "' .. maps.delay_text(ms) .. '"'
          if line:find('delay%s*=%s*"[^"]*"') then
            line = line:gsub('delay%s*=%s*"[^"]*"', value, 1)
          else
            line = line:gsub("%s*}(%s*#?.*)$", ", " .. value .. " }%1", 1)
          end
          done[id] = true
        end
      end
    end
    lines[#lines + 1] = line
  end
  for id in pairs(delays) do
    if not done[id] then return nil, "articulation `" .. id .. "` is not one line of its own in the map's [art]" end
  end
  return (table.concat(lines, "\n"):gsub("\n*$", "\n"))
end

--- Write measured delays into the map's file and bind it again, so that the
--- part's downgrade map has them: one undo step for the part.
function M.apply(part, results)
  local map = art.map_of(part)
  local delays = {}
  for _, r in ipairs(results) do
    if r.delay then delays[r.art.id] = r.delay end
  end
  local text = maps.read(map.file)
  local new, why = M.rewrite(text, delays)
  if not new then error(why, 0) end
  maps.write(map.file, new)
  maps.forget()
  art.bind(part, map.file)
  return map.file
end

--- What a measurement found, as lines for a page.
function M.lines(map, results)
  local lines = { { text = "Articulation delays · " .. map.name, style = "Title" }, "  measured: " .. M.method, "" }
  for _, r in ipairs(results) do
    lines[#lines + 1] = string.format(
      "  %-22s %-5s %s   delay %s%s",
      r.art.name,
      r.art.code,
      r.onset and ("sounds " .. r.onset .. " ms after its note") or "no sound",
      r.delay and maps.delay_text(r.delay) or "—",
      r.now and ("  (now " .. maps.delay_text(r.now) .. ")") or ""
    )
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  :art.measure! writes them into " .. tostring(map.file)
  return lines
end

local plan -- the last measurement: { part, results }

paw.command("art.measure", function()
  local part = paw.ui.views:get("pianoroll"):clip() and paw.ui.views:get("pianoroll"):clip():get().part
    or (paw.cursor.part() and paw.cursor.part().id)
  if not part then error("no part here", 0) end
  local results = M.measure(part)
  plan = { part = part, results = results }
  paw.ui.page("Articulation delays", M.lines(art.map_of(part), results))
end, {
  desc = "Measure how late each articulation of the part's instrument sounds (one note each, rendered offline), and show the delays to write",
})

paw.command("art.measure!", function()
  local part = paw.ui.views:get("pianoroll"):clip() and paw.ui.views:get("pianoroll"):clip():get().part
    or (paw.cursor.part() and paw.cursor.part().id)
  if not part then error("no part here", 0) end
  local results = plan and plan.part == part and plan.results or M.measure(part)
  plan = nil
  local file = M.apply(part, results)
  paw.notify("delays written into " .. file)
end, {
  label = "Articulation delays",
  desc = "Write the delays :art.measure found (or measure now) into the instrument's map, and send them",
})

return M
