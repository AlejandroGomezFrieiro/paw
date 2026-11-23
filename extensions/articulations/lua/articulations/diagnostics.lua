-- What is wrong with the notes of a track that has a map, as diagnostics
-- (`paw.diagnostic`, namespace "articulations"), each with its fixes:
-- notes the instrument cannot play (outside its range, or the range of
-- their articulation), notes on keyswitch rows, articulations the map does
-- not have (played by M2-123's fallback), and chords of two articulations
-- that keyswitches cannot tell apart.
local api = paw.api
local music = paw.music
local art = require("articulations")
local m2 = art.m2

local M = { namespace = "articulations" }

local function inside(range, pitch) return pitch >= range[1] and pitch <= range[2] end

local function range_text(r) return music.name(r[1]) .. "–" .. music.name(r[2]) end

--- Whether a map tells its instrument by keyswitch notes.
local function keyswitched(map)
  for _, a in ipairs(map.arts) do
    for _, e in ipairs(a.events) do
      if e.type == "note" or e.type == "hold" then return true end
    end
  end
  return false
end

--- The diagnostics of one clip.
function M.of_clip(clip_id)
  local c = api.clip_get(clip_id)
  local map = art.map_of(c.track)
  if not map or c.kind ~= "midi" then return {} end
  local keys = require("articulations.roll").keyswitch_keys(map)
  local out = {}
  local notes = api.clip_notes(clip_id)
  local by_start = {}
  for place, n in ipairs(notes) do
    local attr = art.attr_of(n)
    local a, exact = art.resolve(map, attr)
    if not attr then
      a, exact = art.default_of(c.track, map), true
    end
    local ks = keys[n.pitch]
    if ks or (map.keyswitches and inside(map.keyswitches, n.pitch)) then
      out[#out + 1] = {
        notes = { place },
        severity = "warning",
        rule = "keyswitch-row",
        message = music.name(n.pitch)
          .. " is a keyswitch row"
          .. (ks and (" (" .. ks.name .. ")") or "")
          .. ": it switches the instrument, it does not sound",
        fixes = {
          {
            title = "Make the keyswitches of the clip the articulation of the notes after them",
            apply = function() require("articulations.commands").from_keyswitches(clip_id) end,
          },
        },
      }
    else
      local range = a and a.range or map.range
      if range and not inside(range, n.pitch) then
        local fixes = {}
        for _, step in ipairs({ 12, -12, 24, -24 }) do
          if inside(range, n.pitch + step) and #fixes == 0 then
            fixes[1] = {
              title = "Move it an octave "
                .. (step > 0 and "up" or "down")
                .. (math.abs(step) == 24 and " twice" or ""),
              edits = { { note = place, pitch = n.pitch + step } },
            }
          end
        end
        out[#out + 1] = {
          notes = { place },
          severity = "warning",
          rule = "out-of-range",
          fixes = fixes,
          message = string.format(
            "%s is outside what %s plays%s (%s)",
            music.name(n.pitch),
            map.name,
            a and a.range and (" as " .. a.name) or "",
            range_text(range)
          ),
        }
      end
    end
    if attr and not exact then
      local fixes = {}
      if a then
        fixes[#fixes + 1] = {
          title = "Make it " .. a.name .. " (" .. a.code .. ")",
          apply = function() art.set({ { clip = clip_id, place = place } }, { attr = a.attr }) end,
        }
      end
      fixes[#fixes + 1] = {
        title = "Take the articulation away",
        apply = function() art.set({ { clip = clip_id, place = place } }, false) end,
      }
      out[#out + 1] = {
        notes = { place },
        severity = "info",
        rule = "unknown-articulation",
        fixes = fixes,
        message = m2.describe(attr)
          .. " is not in "
          .. map.name
          .. (a and (": it plays as " .. a.name .. " (" .. a.code .. ")") or ": it plays as the instrument decides"),
      }
    end
    if not ks then
      local key = string.format("%.6f", n.start)
      by_start[key] = by_start[key] or {}
      table.insert(by_start[key], { place = place, art = a })
    end
  end
  if keyswitched(map) then
    for _, chord in pairs(by_start) do
      local first = chord[1].art
      for i = 2, #chord do
        if chord[i].art ~= first then
          local places = {}
          for k, x in ipairs(chord) do
            places[k] = x.place
          end
          out[#out + 1] = {
            notes = places,
            severity = "warning",
            rule = "mixed-chord",
            message = "a chord of two articulations: keyswitches cannot play both at once, the last switched wins",
          }
          break
        end
      end
    end
  end
  return out
end

local pending = false

--- Check every MIDI clip of the tracks that have a map, soon (once for many edits).
function M.schedule()
  if pending then return end
  pending = true
  paw.defer(function()
    pending = false
    M.check()
  end, 150)
end

local published = {} -- the clips something was said about, to take it back

--- Check every MIDI clip of the tracks that have a map, now.
function M.check()
  local now = {}
  for _, track in ipairs(api.track_list()) do
    local info = art.info(track)
    if info and info.map then
      for _, c in ipairs(api.clip_list(track)) do
        if c.kind == "midi" then
          local ok, list = pcall(M.of_clip, c.id)
          if ok and #list > 0 then
            now[c.id] = true
            paw.diagnostic.set(M.namespace, c.id, list)
          end
        end
      end
    end
  end
  for id in pairs(published) do
    if not now[id] then paw.diagnostic.set(M.namespace, id, {}) end
  end
  published = now
end

-- Check again after each change of the notes or the maps. Undo and redo
-- need no handler of their own: the changes that they put back come as
-- these events too, with `restored = true`.
for _, pattern in ipairs({ "clip.*", "track.*", "project.loaded", "articulations.bound" }) do
  paw.on(pattern, function() M.schedule() end)
end

paw.command("art.check", function()
  M.check()
  paw.diagnostic.setqflist({ namespace = M.namespace })
end, { desc = "Check the notes of the tracks that have an articulation map, into the quickfix list" })

return M
