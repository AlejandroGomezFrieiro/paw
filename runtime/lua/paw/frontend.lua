-- What a graphical frontend needs to draw the project, in one call.
--
-- A frontend polls `paw.frontend.state(known)` many times a second. The
-- answer always holds what moves on its own (transport position, meters). The
-- project itself is only included when it has changed since revision `known`,
-- so an idle project costs almost nothing to watch. Waveforms are a separate
-- call, `paw.frontend.peaks(clip)`, made only when a clip's `waveform` changes.
local api = paw.api
local M = { revision = 0, max_params = 16, peak_points = 128, preview_notes = 2000 }

for _, event in ipairs({ "changed", "transport.changed", "cursor.changed", "project.loaded", "engine.started", "option.changed", "lanes.changed" }) do
  paw.on(event, function() M.revision = M.revision + 1 end)
end

-- Values as text in their unit, and sliders on a log scale for frequencies
-- and times: see `paw.params`.
--- A parameter's value as text in its unit (see `paw.params.format`).
local function format_value(param, value) return paw.params.format(param, value) end
M.format_value = format_value

local function device_state(id)
  local d = api.device_get(id)
  local params = {}
  -- The device's own parameters, those the user chose to show first (see
  -- `paw.fx.card_params`); the host's wet/dry mix and gain are on the header.
  local own = paw.fx.card_params(d)
  for i = 1, math.min(M.max_params, #own) do
    local p = own[i]
    local value = d.params[p.key]
    params[i] = {
      key = p.key, name = p.name, text = format_value(p, value),
      -- Sliders work on 0..1 whatever the parameter's own range is.
      value = paw.params.fraction(p, value),
      min = p.min, max = p.max,
      -- Where the slider rests, for a double click.
      default = paw.params.fraction(p, p.default),
    }
  end
  return {
    id = d.id, name = d.name, format = d.format, bypass = d.bypass, params = params,
    more = #own - #params,
    -- The wet share, 0 to 1, and the output gain in dB.
    wet = (d.params.fx_wet or 100) / 100, gain = d.params.fx_gain or 0,
    -- "open", "closed", or "" for a device with no window of its own.
    editor = d.editor or "",
    -- Why a plugin has stopped working, or "".
    stopped = d.stopped or (d.missing and "it is not installed or did not load") or "",
    -- The preset last loaded or saved, or "".
    preset = type(d.meta) == "table" and d.meta.preset or "",
    -- "running", "loading", "stopped", "offline" or "missing".
    status = d.status or "running",
    -- Whether it can listen to a side-chain, and the track it listens to
    -- ("" for its own input); `sidechain_menu` lists the choices.
    keyed = (d.ports and d.ports.sidechain) or d.sidechain ~= nil,
    sidechain = paw.routes.sidechain_text(d) or "",
    -- How many output pairs it has (1 for most), and how many of the
    -- further ones play somewhere; `outputs_menu` routes them.
    pairs = math.max(1, #(d.ports and d.ports.outputs or {})),
    routed = (function()
      local n = 0
      for _ in pairs(d.outputs or {}) do n = n + 1 end
      return n
    end)(),
  }
end

--- What extensions add to the frontend's right-click menus: on a clip, on a
--- track's header, on an empty stretch of the timeline.
---
---   table.insert(paw.frontend.menus.clip, { label = "Open as notation", command = "notation.open", only = "midi" })
---   table.insert(paw.frontend.menus.timeline, { label = "New drum track", run = function(track, beat) ... end })
---
--- `command` is a command line and `run` a function given the clip or track
--- and the beat that was clicked; either runs with the cursor put there
--- first. `only` keeps a clip's entry to "midi" or "audio" clips.
M.menus = { clip = {}, track = {}, timeline = {} }

local function menus()
  local out = {}
  for kind, entries in pairs(M.menus) do
    local list = {}
    for i, entry in ipairs(entries) do list[i] = { label = entry.label, only = entry.only or "" } end
    out[kind] = list
  end
  return out
end

--- Bands of their own under the frontend's ruler, from extensions, under
--- the one for markers: each a function that returns the band's entries,
--- `{ beat, length, name, color, command }` each (`length` 0 for a flag,
--- `color` `#rrggbb` or nil for the window's own, `command` a command line,
--- or `run` a function, for a click on it, and `hint`, what the status line
--- says over it).
---
---   table.insert(paw.frontend.bands, function()
---     return { { beat = 0, length = 16, name = "Intro", command = "section.goto 1" } }
---   end)
---
--- A band with no entries takes no room. They are asked again whenever the
--- project, the cursor or the transport changes; after a change of its own
--- (a measurement that has ended) an extension calls `paw.frontend.refresh()`.
M.bands = {}

--- Make the frontend get the state of the project again, when nothing in the
--- project changed. This is for data that an extension adds to the state.
function M.refresh()
  M.revision = M.revision + 1
  api.ui_redraw()
end

local function band_entries(index)
  local fn = M.bands[index]
  local ok, entries = pcall(fn)
  if not ok then
    paw.notify("a band of the window's ruler failed: " .. tostring(entries), "error")
    return {}
  end
  return type(entries) == "table" and entries or {}
end

--- The bands that have entries, as rows from 0 below the marker band:
--- `{ rows, entries }`. Each entry has its `row`, its `band` and `index`
--- (for `act.band`), `beat`, `length`, `name`, `color`, `active` and `hint`.
function M.band_state()
  local out, rows = {}, 0
  for i in ipairs(M.bands) do
    local entries = band_entries(i)
    if #entries > 0 then
      for j, e in ipairs(entries) do
        out[#out + 1] = {
          row = rows, band = i, index = j, beat = tonumber(e.beat) or 0, length = tonumber(e.length) or 0,
          name = tostring(e.name or ""), color = e.color or "", active = (e.command or e.run) and true or false,
          hint = tostring(e.hint or e.name or ""),
        }
      end
      rows = rows + 1
    end
  end
  return { rows = rows, entries = out }
end

--- The candidates of a prompt, as the terminal shows them above the line.
--- These are the candidates in view around the selected one, as
--- `{ label, desc }`. `chosen` is the place of the selected candidate among
--- them (0 for none).
function M.completions(prompt)
  local all = prompt.matches
  if not all or #all == 0 then return nil end
  local rows = 10
  local first = math.max(1, math.min((prompt.match or 0) - rows + 1, #all - rows + 1))
  local list = { total = #all, chosen = (prompt.match or 0) > 0 and prompt.match - first + 1 or 0, items = {} }
  for i = first, math.min(#all, first + rows - 1) do
    local c = all[i]
    list.items[#list.items + 1] = { label = c.label, desc = c.desc and (c.desc:match("^[^\n]*"):gsub(":? `.*$", "")) or "" }
  end
  return list
end

--- A track's sends as `{ name, level }`, the level in dB.
function M.send_list(track)
  local out = {}
  for i, send in ipairs(track.sends or {}) do
    local ok, to = pcall(api.track_get, send.target)
    out[i] = { name = ok and to.name or "?", level = send.level }
  end
  return out
end

local mode_names = { n = "NORMAL", c = "COMMAND", i = "INSERT", o = "PENDING" }
local visual_names = { v = "VISUAL", V = "V-LINE", b = "V-BLOCK", clips = "CLIPS" }

--- Where the keyboard is: the mode, what is half typed, the prompt or the
--- message, the selection, and the cursors of the panels. Small, and sent
--- every time, because a key press changes it without changing the project.
local function modal()
  local keymap, ui = paw.keymap, paw.ui
  local out = {
    mode = keymap.mode, pending = keymap.pending(), recording = keymap.recording() or "",
    name = keymap.mode == "x" and keymap.visual and visual_names[keymap.visual.kind]
      or mode_names[keymap.mode] or keymap.mode:upper(),
    focused = ui.focused, mixer = ui.visible("mixer"),
    float = ui.float and (ui.float.title or ui.float.name) or nil,
    -- A menu the kernel opened (a right click in a pane drawn from its
    -- scene), by how many were: the window shows it (`paw.frontend.menu("shown")`).
    menu = select(2, require("paw.menu").shown()),
    -- What the pointer is over in a pane drawn from its scene, or what its
    -- drag will do (`paw.mouse.hint`), for the status line.
    hint = paw.mouse.hint_text(),
    -- The shape of the pointer there, if it has one ("resize_h", "resize_v").
    pointer = select(2, paw.mouse.hint_text()),
    selection = keymap.selection(),
    -- A render in the background: { path, fraction, seconds, cancelling, stage }.
    render = paw.api.render_status(),
    -- What `:learn` is waiting to bind a controller to, in words.
    learning = paw.learn and paw.learn.learning and paw.learn.target_name(paw.learn.learning) or nil,
  }
  -- Chosen clips are told one by one, with the clips (`selected`).
  if out.selection then out.selection.clips = nil end
  local prompt = require("paw.views.cmdline").state()
  if prompt then
    out.prompt = prompt
    out.prompt.matches = M.completions(prompt)
  elseif ui.message then
    out.message = { text = ui.message.text:match("^[^\n]*"), level = ui.message.level, time = ui.message.time }
  elseif paw.opt.keybar and keymap.pending() == "" then
    -- With nothing to say, the keys worth knowing here, as the terminal's
    -- bottom line shows them.
    out.keys = {}
    for i, entry in ipairs(ui.keybar.entries()) do out.keys[i] = { key = entry[1], desc = entry[2] } end
    local topic = paw.help and paw.help.topic_of(ui.focused)
    if topic then out.keys[#out.keys + 1] = { key = ":help " .. topic, desc = "the manual" } end
  end
  -- What an Ex line being typed would act on: the stretch of time, the
  -- tracks, and the clips that match with how many matches each holds.
  local shown = paw.ex and paw.ex.shown()
  if shown then
    out.ex = { from = shown.from, to = shown.to, tracks = {}, clips = {}, current = shown.current and shown.current.clip and shown.current.clip.id }
    for id in pairs(shown.tracks or {}) do out.ex.tracks[#out.ex.tracks + 1] = id end
    for id, n in pairs(shown.clips or {}) do out.ex.clips[#out.ex.clips + 1] = { id = id, count = n, notes = shown.notes[id] ~= nil } end
  end
  -- The row of a strip the keyboard is on in the mixer.
  if out.mixer and ui.focused == "mixer" then
    local row, id = require("paw.mixer_rows").current()
    if row then out.mixer_row = { track = id, kind = row.kind, index = row.index or 0, field = row.field or "" } end
  end
  -- The status line when it was set up (`paw.statusline.setup`): the
  -- pieces of each side as `{ text, style }`, for a window that draws it.
  if paw.statusline.customized() then out.statusline = paw.statusline.frontend() end
  local qf = paw.qf and paw.qf.status()
  if qf then
    local text, worst = {}, 0
    for _, piece in ipairs(qf) do
      text[#text + 1] = piece[1]
      worst = math.max(worst, piece[2] == "StatusError" and 2 or piece[2] == "StatusWarn" and 1 or 0)
    end
    out.qf = { text = table.concat(text), level = worst }
  end
  if paw.opt.hints then
    local hints, title = keymap.hints()
    if hints then out.hints = { title = title, items = hints } end
  end
  local under = paw.cursor.clip()
  out.clip = ui.focused == "arrange" and under and under.id or nil
  -- The tabs and windows, as panes of the main area.
  out.panes = paw.panes.state()
  -- Views in windows of their own.
  out.windows = paw.canvas.windows()
  -- Views that can be opened in one, for the views menu.
  out.views = paw.canvas.openable()
  out.menus = menus()
  if ui.focused == "devices" then
    -- The row the keyboard is on, as a device of the track and one of its
    -- parameters (0 for the device's own line).
    local panel = ui.views.devices
    local rows = panel:rows()
    panel.row = paw.util.clamp(panel.row, 1, math.max(1, #rows))
    local row = rows[panel.row]
    if row then
      out.device, out.param = row.device.index, 0
      for i, p in ipairs(row.device.param_info) do
        if row.param and p.key == row.param.key then out.param = i end
      end
    end
  end
  return out
end

--- The float that is open (help, a list, a picker), drawn as text `width`
--- columns wide: its title and its lines. Nil when there is none.
function M.float(width, height)
  if not paw.ui.float then return nil end
  local lines = api.ui_snapshot(width, height)
  local rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == paw.ui.float.name then rect = r end
  end
  if not rect then return nil end
  local out = {}
  for y = rect.y, rect.y + rect.h - 1 do
    local cells = {}
    for ch in (lines[y + 1] or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do cells[#cells + 1] = ch end
    out[#out + 1] = table.concat(cells, "", rect.x + 1, math.min(#cells, rect.x + rect.w))
  end
  return { title = paw.ui.float.title or paw.ui.float.name, lines = out }
end

--- The stretch of a lane's range that is worth drawing it over: a fader's
--- travel for volume, the whole range for anything else.
function M.lane_span(lane)
  if lane.target == "volume" then return -60, 6 end
  return lane.min, lane.max
end

--- What a lane moves, in words: `Volume`, `Pan`, `Synth · cutoff`.
function M.lane_name(lane)
  if lane.target == "volume" then return "Volume" end
  if lane.target == "pan" then return "Pan" end
  local ok, device = pcall(api.device_get, lane.device)
  if not ok then return tostring(lane.param) end
  for _, p in ipairs(device.param_info) do
    if p.key == lane.param then return device.name .. " · " .. p.name end
  end
  return device.name .. " · " .. tostring(lane.param)
end

--- The takes of a clip as its take lanes show them: `{ name, key }` each.
--- `key` changes exactly when the sound of the take changes. Nil for a clip
--- without takes, which has nothing in the lanes.
function M.take_rows(clip)
  local takes = paw.takes.of(clip)
  if not takes then return nil end
  local out = {}
  local seconds = clip.kind == "audio" and paw.stretch.file_seconds(clip, clip.length) or 0
  for i, entry in ipairs(takes.list) do
    local key
    if clip.kind == "audio" then
      local c = paw.takes.content(clip, i)
      key = string.format("%s|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%s|%s|%.17g|%.17g", c.file, c.offset, c.gain, clip.length,
        seconds, clip.stretch, clip.pitch, tostring(clip.stretching), tostring(clip.loop), clip.loop_start, clip.loop_length or 0)
    else
      key = string.format("%s|%d|%d|%d|%.17g|%s|%.17g|%.17g", tostring(clip.stamp), takes.active, i, #(entry.notes or {}),
        clip.length, tostring(clip.loop), clip.loop_start, clip.loop_length or 0)
    end
    out[i] = { name = entry.name or ("take " .. i), key = key }
  end
  return out
end

--- What take `take` of a clip plays, for the picture in its take lane. For
--- sound, this is a waveform as `M.peaks` gives it, at `points` points. For
--- MIDI, it is the notes as `M.preview` gives them. It repeats as a looped
--- clip repeats. The waveform of the take that plays is the waveform of the
--- clip, stretched. The waveform of a different take is its file, made
--- shorter or longer in time as the clip stretches it.
function M.take_preview(id, take, points)
  local ok, clip = pcall(api.clip_get, id)
  if not ok then return {} end
  local c = paw.takes.content(clip, take)
  local flat = {}
  if clip.kind == "audio" then
    points = paw.util.clamp(math.floor(points or M.peak_points), 8, 4096)
    local takes = paw.takes.of(clip)
    if takes and take == takes.active then
      local got, peaks = pcall(api.clip_peaks, id, points)
      for i, p in ipairs(got and peaks or {}) do
        flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = p[1], p[2], p[3]
      end
      return flat
    end
    local seconds = paw.stretch.file_seconds(clip, clip.length)
    local got, peaks
    if clip.loop and clip.loop_length then
      -- One repeat's worth, laid along the clip as it repeats.
      local period = paw.stretch.file_seconds(clip, clip.loop_length)
      local lead = clip.loop_start / clip.loop_length * period
      local per = paw.util.clamp(math.ceil(points * period / seconds), 1, 4096)
      local one
      got, one = pcall(api.media_peaks, c.file, math.max(0, c.offset + lead), period, per)
      if got and #one > 0 then
        peaks = {}
        for i = 1, points do
          local at = (i - 0.5) * seconds / points
          local phase = ((at - lead) % period) / period
          peaks[i] = one[math.min(#one, math.floor(phase * #one) + 1)]
        end
      end
    else
      got, peaks = pcall(api.media_peaks, c.file, c.offset, seconds, points)
    end
    local gain = 10 ^ ((c.gain or 0) / 20)
    for i, p in ipairs(got and peaks or {}) do
      flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = p[1] * gain, p[2] * gain, p[3] * gain
    end
    return flat
  end
  local i = 0
  for _, n in ipairs(paw.stretch.sounding(clip, c.notes, M.preview_notes)) do
    if i >= M.preview_notes then break end
    if n.start >= 0 and n.start < clip.length then
      i = i + 1
      flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = n.start, n.length, n.pitch
    end
  end
  return flat
end

--- What changes exactly when what a clip shows inside does: its notes and
--- controller moves (fetch `M.preview` again then), or its waveform (fetch
--- `M.peaks` again then). Nil for a MIDI clip with no notes yet.
function M.content_key(clip)
  local repeats = clip.loop and string.format("|%.17g|%.17g", clip.loop_start, clip.loop_length) or ""
  -- Its warp markers change its waveform.
  for _, m in ipairs(clip.warp or {}) do repeats = repeats .. string.format("|%.17g:%.17g", m.source, m.target) end
  if clip.kind == "audio" then
    return string.format("%s|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%s%s", clip.file, clip.offset, clip.length, clip.gain,
      paw.time.seconds(clip.length, clip.start), clip.stretch, clip.pitch, tostring(clip.stretching), repeats)
  end
  return clip.stamp and string.format("%.0f|%.0f|%.17g%s", clip.stamp, clip.control_stamp or 0, clip.length, repeats) or nil
end

--- A MIDI clip's notes for the small picture inside it: one flat list
--- { start1, length1, pitch1, start2, ... }, at most `M.preview_notes` notes.
--- Fetched when the clip's `stamp` in `state` changes.
function M.preview(id)
  local flat = {}
  local ok, notes = pcall(api.clip_notes, id)
  local c = ok and api.clip_get(id) or { length = 0 }
  local length = c.length
  -- A looped clip shows its notes over and over, as they sound.
  if ok then notes = paw.stretch.sounding(c, notes, M.preview_notes) end
  local i = 0
  for _, n in ipairs(ok and notes or {}) do
    if i >= M.preview_notes then break end
    -- Notes hidden by a trim of the clip's edges are not drawn.
    if n.start >= 0 and n.start < length then
      i = i + 1
      flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = n.start, n.length, n.pitch
    end
  end
  return flat
end

--- What a track is in VCA terms, for a strip: a VCA's members by name, a
--- member's VCAs by name, joined by commas.
function M.vca_words(id)
  local names = {}
  local list = paw.vca.is_vca(id) and paw.vca.members(id) or paw.vca.of(id)
  for i, other in ipairs(list) do names[i] = api.track_get(other, "name") end
  return table.concat(names, ", ")
end

-- What the state's parts that only a turn with input, an edit or a redraw
-- can change were made for (`still_key`), by seat: the drawn tracks and
-- the modal state. While the song plays and nobody types, they are kept.
local kept = {}

--- What those parts depend on: the project's revision, the redraws, the
--- input that came (`paw.remote.touches`), the seat and the keys typed.
--- A render in the background changes the modal state on its own.
local function still_key()
  if paw.api.render_status() then return nil end
  local keymap = paw.keymap
  return table.concat({ M.revision, api.ui_redraws(), paw.remote and paw.remote.touches or 0, paw.seats.current,
    keymap.mode, keymap.pending() }, ":")
end

--- The data that paw sends to a graphical frontend: transport, tracks,
--- clips, devices and the modal state, as plain data. `known` is a list of
--- the data that the frontend has already.
function M.state(known)
  M.polled = api.now() -- someone is looking: see `paw.fx.interactive`
  local t, e = api.transport_get(), api.engine_get()
  local key = still_key()
  local seat = paw.seats.current
  local same = key and kept[seat] and kept[seat].key == key and kept[seat]
  -- The tracks that are drawn: those folded away into a group are left out.
  local ids = same and same.ids
  if not ids then
    ids = paw.groups.rows()
    ids[#ids + 1] = 0 -- the master track goes last
  end
  -- Both sides of every track's meter, one after the other.
  local levels = {}
  for i, id in ipairs(ids) do
    levels[2 * i - 1], levels[2 * i] = api.track_meter(id)
  end
  -- What arrives at each track's audio input, armed or not: 0 without one.
  local inputs, device_levels = {}, paw.audio.levels()
  for i, id in ipairs(ids) do
    inputs[i] = id ~= 0 and paw.audio.level({ input = api.track_get(id, "input") }, device_levels) or 0
  end
  local num, den = paw.tempo.signature_at(t.position)
  local out = {
    revision = M.revision, playing = t.playing, recording = t.take ~= nil, position = t.position,
    -- Beats of a count-in still to be counted before the take starts; 0 for none.
    counting = t.counting or 0,
    time = paw.time.format(t.position), clock = paw.time.clock(t.position),
    -- The tempo and signature where the playhead is.
    tempo = math.floor(paw.tempo.at(t.position) * 100 + 0.5) / 100, signature = num .. "/" .. den,
    cpu = paw.audio.load(e.cpu), levels = levels, inputs = inputs, modal = same and same.modal or modal(), armed = t.recording,
    -- What went wrong while playing (see `:engine.status`).
    xruns = e.xruns, late_blocks = e.late_blocks, midi_dropped = e.midi_dropped,
    record_dropped = e.record_dropped, devices_stopped = e.devices_stopped,
    -- How often the window draws while the song plays (`paw.opt.window_fps`).
    window_fps = paw.opt.window_fps,
    window_cache = paw.opt.window_cache,
  }
  if key and not same then kept[seat] = { key = key, ids = ids, modal = out.modal } end
  if known == M.revision then return out end

  local p = api.project_get()
  out.project = {
    name = p.name, modified = p.modified, tempo = out.tempo, bar = paw.time.bar(), length = p.length,
    signature = out.signature, loop_enabled = t.loop_enabled, loop_start = t.loop_start,
    loop_end = t.loop_end, metronome = t.metronome, backend = e.backend, sample_rate = e.sample_rate,
    -- Recording only between two points, and the bars counted before a take.
    punch_enabled = t.punch_enabled, punch_start = t.punch_start, punch_end = t.punch_end,
    count_in = t.count_in, pre_roll = t.pre_roll, pre_roll_seconds = t.pre_roll_seconds,
    grid = paw.opt.grid, note_grid = paw.opt.note_grid, threads = e.threads, xruns = e.xruns,
    -- The engine in a few words: backend, output device, sample rate.
    engine = paw.audio.summary(),
  }
  -- Bar and beat lines from the tempo map, well past the end and the last
  -- change, and the tempo and signature changes to flag on the ruler.
  out.project.marks = paw.tempo.marks(0, math.huge)
  -- The tempo lane under the ruler, when it is shown: the whole map, and the
  -- tempos at the bottom and the top of the row.
  if paw.tempolane.shown() then
    local lo, hi = paw.tempolane.range()
    out.project.tempo_lane = { lo = lo, hi = hi, points = paw.tempo.points() }
  end
  -- Markers and regions (`paw.markers`): { id, beat, name, length } each.
  out.project.markers = {}
  for i, m in ipairs(paw.markers and paw.markers.list() or {}) do
    out.project.markers[i] = { id = m.id, beat = m.beat, name = paw.markers.label(m), length = m.length or 0 }
  end
  -- Extensions' bands under it (`M.bands`).
  out.project.bands = M.band_state()
  local last = math.max(p.length or 0, t.loop_end or 0)
  for _, mark in ipairs(out.project.marks) do last = math.max(last, mark.beat) end
  local stop = paw.time.bar_start(paw.time.bar_of(last) + 17)
  out.project.lines = {}
  local lines = paw.tempo.lines(0, stop)
  for i, line in ipairs(lines) do
    local next_beat = lines[i + 1] and lines[i + 1].beat or line.beat + (line.beat - (lines[i - 1] and lines[i - 1].beat or line.beat - 1))
    out.project.lines[i] = {
      beat = line.beat, bar = line.bar, index = line.index, next = next_beat,
      label = line.index == 0 and tostring(line.bar) or "", place = line.bar .. "." .. (line.index + 1),
    }
  end
  out.selected = paw.cursor.track_id() or -1
  out.cursor = paw.cursor.beat
  out.tracks, out.clips, out.devices = {}, {}, {}
  local chosen_set = {}
  for _, id in ipairs(M.chosen_clips()) do chosen_set[id] = true end
  for i, id in ipairs(ids) do
    local track = api.track_get(id)
    -- What the track's sound goes through, in a few words.
    local chain = {}
    for j, device in ipairs(track.devices or {}) do chain[j] = api.device_get(device).name end
    local to = track.output and select(2, pcall(api.track_get, track.output))
    out.tracks[i] = {
      id = id, name = track.name, volume = track.volume, pan = track.pan, mute = track.mute,
      solo = track.solo, armed = track.armed, master = track.master, lanes = {},
      input = track.input, monitor = track.monitor,
      -- What the track takes in, in words (`UR22mkII · 1/2`), or nil.
      input_label = not track.master and paw.audio.label(track) or nil,
      -- The colour everything of the track's is drawn in, as in the terminal.
      color = paw.draw.track_colour(track, i), chain = table.concat(chain, " › "),
      -- Its kind, in a few words ("Vocal track · Kitane"), or nil.
      kind = id ~= 0 and paw.track_kinds.describe(id) or nil,
      output = type(to) == "table" and to.name or nil,
      -- Its sends, for the mixer's strip: `{ name, level }` in dB each.
      sends = M.send_list(track),
      -- Groups: how many groups the track is inside, whether it is one,
      -- whether it is folded, and how many tracks it holds.
      depth = id ~= 0 and paw.groups.depth(id) or 0,
      group = id ~= 0 and paw.groups.is_group(id) or false,
      folded = id ~= 0 and paw.groups.folded(id) or false,
      members = id ~= 0 and #paw.groups.members(id) or 0,
      -- VCAs: whether it is one, and the names of the tracks under it, or
      -- of the VCAs a track is under, in a few words.
      vca = id ~= 0 and paw.vca.is_vca(id) or false,
      vcas = id ~= 0 and M.vca_words(id) or "",
      -- How tall it is drawn, as a share of the zoom's height.
      height = track.height or 1,
      -- "read", "touch", "latch", "write" or "off".
      automation = track.automation or "read",
      -- The lanes shown as rows of their own under the track, by id.
      lane_rows = {},
      -- How many take lanes it shows under its clips, above those rows.
      take_rows = id ~= 0 and paw.takes.lane_count(id) or 0,
    }
    for j, lane in ipairs(id ~= 0 and paw.lanes.shown(id) or {}) do out.tracks[i].lane_rows[j] = lane.id end
    -- Points are in the target's own units; `min` and `max` give its range,
    -- `lo` and `hi` the part of it a frontend draws the lane over, and
    -- `name` says what the lane moves.
    for j, lane in ipairs(api.lane_list(id)) do
      local lo, hi = M.lane_span(lane)
      out.tracks[i].lanes[j] = {
        id = lane.id, target = lane.target, device = lane.device, param = lane.param,
        enabled = lane.enabled, min = lane.min, max = lane.max, points = api.lane_points(lane.id),
        lo = lo, hi = hi, name = M.lane_name(lane),
      }
    end
    local take_lanes = out.tracks[i].take_rows > 0
    for _, clip in ipairs(api.clip_list(id)) do
      -- Stretched, shifted, looped, or being stretched: in a few characters.
      local mark = paw.stretch.badge(clip)
      local notches = paw.stretch.repeats(clip)
      -- Its warp markers, in beats from its start.
      local warps = {}
      for j, m in ipairs(clip.warp or {}) do warps[j] = m.beat - clip.start end
      local content = M.content_key(clip)
      out.clips[#out.clips + 1] = {
        -- In take lanes: each take's name, and what changes exactly when
        -- its picture does (fetch `M.take_preview` again then).
        take_rows = take_lanes and M.take_rows(clip) or nil,
        id = clip.id, track = i - 1, start = clip.start, length = clip.length,
        name = (clip.offline and "offline · " or "") .. (mark and mark .. " · " or "") .. clip.name,
        midi = clip.kind == "midi", muted = clip.muted,
        -- How many takes it has (1 without others), and which plays.
        takes = select(1, paw.takes.count(clip)), take = select(2, paw.takes.count(clip)),
        -- Chosen with the pointer (`M.chosen_clips`).
        selected = chosen_set[clip.id] or false,
        -- An audio clip's fades, in beats, and its gain in dB.
        fade_in = clip.fade_in, fade_out = clip.fade_out, gain = clip.gain,
        -- Its file is missing: silent until relinked. The name says so too.
        offline = clip.offline or nil,
        -- Changes exactly when the clip's notes or controller moves do:
        -- fetch `M.preview` (and the piano roll's clip) again then.
        stamp = clip.kind ~= "audio" and content or nil,
        -- Changes exactly when the clip's waveform does: fetch `M.peaks` again then.
        waveform = clip.kind == "audio" and content or nil,
        -- Whether it loops, and where its repeats begin, in beats from its start.
        loop = clip.loop or nil, notches = notches, warps = warps,
      }
    end
  end
  if out.selected >= 0 then
    for i, id in ipairs(api.track_get(out.selected).devices) do out.devices[i] = device_state(id) end
    out.routing = M.routing(out.selected)
  end
  if known < 0 then
    out.kinds = {}
    for i, info in ipairs(api.device_types()) do out.kinds[i] = info.kind end
  end
  return out
end

--- Save the project under a new name: choose the directory from a list,
--- then type the file's name. `after` runs once it is saved.
function M.save_as(after)
  paw.pick.file({
    title = "Save the project in",
    directory = true,
    on_choose = function(dir)
      local p = api.project_get()
      -- A project is a folder: its name is the folder's.
      local name = p.path and (p.path:gsub("/project%.toml$", ""):gsub("%.json$", ""):match("([^/]+)$"))
        or (p.name ~= "" and p.name or "song")
      paw.ui.input({ prompt = "Folder name: ", text = name }, function(typed)
        if typed == "" then return end
        local saved, note = paw.project.write(dir .. "/" .. typed)
        paw.notify(note and (note .. ": " .. saved) or ("saved " .. saved))
        if after then after() end
      end)
    end,
  })
end

paw.option.define("native_dialogs", true) -- the window opens the desktop's file dialogs, not the kernel's list
-- Frames a second the window draws while the song plays (the playhead, the
-- meters): "auto" is 30 on a graphics card and 15 on the processor. Keys,
-- the pointer and edits are drawn at once all the same.
paw.option.define("window_fps", "auto", { type = { "number", "string" }, min = 1, max = 60, values = { "auto" } })
-- The window keeps what does not move in a pane as textures, and paints a
-- part again only when it changes: true, false, or "auto" (on).
paw.option.define("window_cache", "auto", { type = { "boolean", "string" }, values = { "auto", true, false } })

--- What the graphical window said of the OpenGL that draws it when it
--- started: `{ renderer, version, software, cause }`, or nil before a
--- window started. `cause` tells why a window draws on the processor:
--- "asked", "libgl", "no-card" or "driver".
M.window_renderer = nil

--- What to do about a window that draws on the processor, by cause, the
--- likely cause first. `:checkhealth window` gives all of them.
M.software_advice = {
  asked = "PAW_GUI_RENDERER=software or --renderer software asks for the processor: unset the variable and leave out the option",
  libgl = "LIBGL_ALWAYS_SOFTWARE is set: unset it",
  driver = "the OpenGL driver of the graphics card is missing (on NixOS, set hardware.graphics.enable = true; elsewhere install Mesa's drivers), "
    .. "or the X server gives no DRI3 (over SSH, VNC or Xvfb): start the window on the computer's own screen",
  ["no-card"] = "no graphics card was found (/dev/dri has no render node): on this computer the window can only draw on the processor; "
    .. "a lower paw.opt.window_fps costs less",
}

--- The window tells which OpenGL renderer draws it (see
--- `paw.frontend.window_renderer`). One that draws on the processor is
--- told once, in a line that says what to do.
function M.window_renderer_set(info)
  M.window_renderer = info
  if type(info) == "table" and info.software then
    local advice = M.software_advice[info.cause] or M.software_advice.driver
    paw.notify("The window draws on the processor (" .. tostring(info.renderer):match("^%S+") .. "), which costs CPU while a song plays: "
      .. advice .. ". See :checkhealth window.", "warn")
  end
end

--- The data that the window needs to open the file dialog of the desktop.
--- `native` tells if it must use that dialog (the option). When it is off,
--- the dialogs are those of the kernel. `dir` is the folder to start in. It
--- is the folder of the last selected file, or of the project, or home, as
--- in the list picker. `name` is the file name of the project, for
--- "Save as". `render` is the file endings that a render can write.
function M.dialog_info()
  local p = api.project_get()
  local dir = paw.state.pick_dir or (p.path and p.path:match("^(.*)/[^/]+$")) or os.getenv("HOME") or "/"
  local name = p.path and p.path:match("([^/]+)$") or ((p.name ~= "" and p.name or "song") .. ".json")
  -- What a render can write: wav and flac, and the lossy formats ffmpeg can make.
  local render = { "wav", "flac" }
  for ext, available in pairs(M.render_dialog().formats) do
    if available then render[#render + 1] = ext end
  end
  table.sort(render)
  return { native = paw.opt.native_dialogs and true or false, dir = dir, name = name, render = render }
end

--- Tells if paw would lose data if it closes now: { modified, name, path }.
function M.closing()
  local p = api.project_get()
  return { modified = paw.project.unsaved(), name = p.name, path = p.path }
end

--- The start values of the render dialog. These are the file that a render
--- would write, and the ranges that paw can render (`{ name, label }`: the
--- song, the loop, the selection, each region). They are also the sample
--- rate of the engine, and the lossy formats that ffmpeg can make here
--- (`formats`: `{ mp3 = true, ogg = false, ... }`).
function M.render_dialog()
  local t = api.transport_get()
  local ranges = { { name = "song", label = "The whole song" } }
  if t.loop_end > t.loop_start then
    ranges[#ranges + 1] = { name = "loop", label = string.format("The loop (%s – %s)", paw.time.format(t.loop_start), paw.time.format(t.loop_end)) }
  end
  local sel = paw.keymap.selection()
  if sel and sel.c0 and sel.c1 and sel.c1 > sel.c0 then ranges[#ranges + 1] = { name = "selection", label = "The selection" } end
  for _, r in ipairs(paw.markers.regions()) do
    ranges[#ranges + 1] = { name = "region:" .. r.id, label = "Region “" .. paw.markers.label(r) .. "”" }
  end
  -- A project with no file yet renders to where a file was last chosen, or home.
  local path = require("paw.render").default_path()
  if not path:find("/", 1, true) then path = (paw.state.pick_dir or os.getenv("HOME") or ".") .. "/" .. path end
  local formats = {}
  for _, f in ipairs(api.render_formats(paw.opt.ffmpeg)) do
    if f.lossy then formats[f.extensions[1]] = f.available end
  end
  return {
    path = path, ranges = ranges, sample_rate = api.engine_get().sample_rate, formats = formats,
    tags = require("paw.render").tags(),
  }
end

--- The menu of the input of a track: the choices of `paw.audio.choices`
--- under their headings, `audio`, `midi` and `channel`. It also gives the
--- MIDI output of the track: `midi_out`, `midi_out_channel` and
--- `midi_out_form`. Each is a list of `{ label, checked }`.
--- `act.choose_input` takes one by heading and place.
function M.input_menu(track)
  local out = {
    audio = {}, midi = {}, channel = {}, midi_out = {}, midi_out_channel = {}, midi_out_form = {},
    monitor = api.track_get(track, "monitor"),
  }
  for _, choice in ipairs(paw.audio.choices(track)) do
    local list = out[choice.group]
    list[#list + 1] = { label = choice.label, checked = choice.checked }
  end
  return out
end

--- The recent projects the File menu lists: `{ label, path }` each.
function M.recent_menu()
  return paw.recent.menu()
end

local function layout_file() return M.layout_path or api.env().state_dir .. "/window.json" end

--- How the window was left (its size, the zoom, the heights of rows and of
--- the piano roll, if the mixer shows): a table, empty when nothing
--- was kept. It belongs to the machine, so it is kept here, where a window
--- attached to this kernel finds it too. (`M.layout_path` names another
--- file, for tests.)
function M.layout_get()
  local handle = io.open(layout_file(), "rb")
  if not handle then return {} end
  local text = handle:read("*a")
  handle:close()
  local ok, data = pcall(api.json_decode, text)
  return ok and type(data) == "table" and data or {}
end

--- Keep the window's layout (see `layout_get`).
function M.layout_set(layout)
  local file = layout_file()
  pcall(paw.api.fs_mkdir, (file:match("^(.*)/[^/]*$") or "."))
  local handle = io.open(file .. ".tmp", "wb")
  if not handle then return end
  handle:write(api.json_encode(layout, true))
  handle:close()
  os.rename(file .. ".tmp", file)
end

--- The menu where the audio devices are chosen: `info` (lines to show),
--- `output`, `input`, `block`, `rate` and `backend`, each a list of
--- `{ label, checked }`.
--- `act.choose_engine` takes one by heading and place.
function M.engine_menu()
  local out = { info = {}, output = {}, input = {}, block = {}, rate = {}, backend = {} }
  local ok, choices = pcall(paw.audio.engine_choices)
  if not ok then
    out.info[1] = { label = tostring(choices):match("[^\n]*"), checked = false }
    return out
  end
  for _, choice in ipairs(choices) do
    local list = out[choice.group]
    list[#list + 1] = { label = choice.label, checked = choice.checked }
  end
  return out
end

--- The waveform of an audio clip at `points` points (`M.peak_points`
--- without), as one flat list { min1, max1, rms1, min2, max2, rms2, ... }.
--- It gives how far the wave goes each way and how loud it is, which is its
--- body. It is not in `state`, which paw sends again each time the cursor
--- moves. So a frontend gets each waveform only one time for each width.
function M.peaks(clip, points)
  local flat = {}
  points = paw.util.clamp(math.floor(points or M.peak_points), 8, 4096)
  for i, p in ipairs(api.clip_peaks(clip, points)) do
    flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = p[1], p[2], p[3]
  end
  return flat
end

-- What a pointer does ---------------------------------------------------------
--
-- A frontend sends gestures here (`paw.frontend.act.move_clip(id, 8, track)`)
-- instead of spelling out what they mean, so that every frontend means the
-- same by a drag or a double click, and the suite can test it. Beats snap to
-- the grid here. Notes and points are named by their place, from 1.

local A = {}
M.act = A
M.openers = {}

local function snap(beat) return math.max(0, paw.cursor.snap(beat)) end

local function note_snap(beat)
  local grid = paw.opt.note_grid
  return math.max(0, math.floor(beat / grid + 0.5) * grid)
end

--- Give the arrange view the keyboard, unless a window is open over it.
local function to_arrange()
  if paw.keymap.mode == "x" then paw.keymap.set_mode("n") end
  if not paw.ui.float and paw.ui.focused ~= "arrange" then paw.ui.focus("arrange") end
end

-- Clips chosen with the pointer -----------------------------------------------
--
-- A click chooses a clip, Ctrl and a click adds or takes one away, Shift and
-- a click takes in the clips between it and the last one chosen, a box drawn
-- with the right button takes in what it touches. Gestures on a chosen clip
-- act on all of them. So do the keys: two or more chosen clips (or any chosen
-- with a modifier or a box) are visual mode's selection, of the kind "clips",
-- which every operator acts on (`d`, `x`, `y`, `>`, `gc`...) and Esc lets go
-- of; one clip chosen with a plain click is the clip under the cursor, which
-- `x` already deletes, and is let go of when the cursor leaves it.

local picked = { set = {}, anchor = nil }
local recently_chosen  -- the clips chosen before the last plain click: { set, at }
-- A gesture is choosing: the cursor and mode it moves keep the choice.
local pointing = false
-- Each window and terminal chooses clips of its own.
paw.seats.keep("frontend.picked", function() return picked end, function(p) picked = p end,
  function() return { set = {}, anchor = nil } end)
paw.seats.keep("frontend.recently_chosen", function() return recently_chosen end,
  function(r) recently_chosen = r end, function() return nil end)

--- The ids of the chosen clips, in order.
--- @type function(): {integer}
function M.chosen_clips()
  local keymap = paw.keymap
  -- Another kind of selection is open: that is what the keys act on.
  if keymap.mode == "x" and not (keymap.visual and keymap.visual.region) then return {} end
  local out = {}
  for id in pairs(picked.set) do
    if pcall(api.clip_get, id) then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

--- Where each drawn track is, by id: its row from 1.
local function row_index()
  local rows = {}
  for i, id in ipairs(paw.groups.rows()) do rows[id] = i end
  return rows
end

--- The chosen clips as a region for the operators: the rows and the stretch
--- they span, and `clips`, the set of them.
local function clip_region()
  local rows, set = row_index(), {}
  local r0, r1, c0, c1 = math.huge, -math.huge, math.huge, -math.huge
  for _, id in ipairs(M.chosen_clips()) do
    local c = api.clip_get(id)
    local row = rows[c.track]
    if row then
      set[id] = true
      r0, r1 = math.min(r0, row), math.max(r1, row)
      c0, c1 = math.min(c0, c.start), math.max(c1, c.start + c.length)
    end
  end
  if not next(set) then return nil end
  return { kind = "clips", clips = set, r0 = r0, r1 = r1, c0 = c0, c1 = c1 }
end

local function changed()
  M.revision = M.revision + 1
  api.ui_redraw()
end

--- Choose a set of clips (`{ [id] = true }`); with `visual` they become
--- visual mode's selection.
local function choose_clips(set, anchor, visual)
  picked = { set = set, anchor = anchor or picked.anchor }
  local keymap = paw.keymap
  pointing = true
  if visual and next(set) and clip_region() then
    if not paw.ui.float and paw.ui.focused ~= "arrange" then paw.ui.focus("arrange") end
    local region = clip_region()
    keymap.visual = { kind = "clips", row = region.r0, col = region.c0, view = paw.ui.focused, region = clip_region }
    if keymap.mode ~= "x" then keymap.set_mode("x") end
  elseif keymap.mode == "x" then
    keymap.set_mode("n")
  end
  pointing = false
  changed()
end

paw.on("mode.changed", function(e)
  if not pointing and e.old == "x" and next(picked.set) then
    picked.set = {}
    changed()
  end
end)
paw.on("cursor.changed", function()
  if pointing or paw.keymap.mode == "x" or not next(picked.set) then return end
  local under = paw.cursor.clip()
  if not (under and picked.set[under.id]) then
    picked.set = {}
    changed()
  end
end)

--- Let go of the chosen clips.
function A.clear_clip_selection()
  if next(picked.set) then choose_clips({}, nil, false) end
end

--- Put the cursor on a track at a beat: a click on a lane or a header. A
--- click on a lane (one with a beat) lets go of the chosen clips.
function A.select(track, beat)
  pointing = true
  to_arrange()
  if track ~= 0 then paw.cursor.set_track(track) end
  if beat then paw.cursor.set_beat(snap(beat)) end
  pointing = false
  if beat and next(picked.set) then
    picked.set = {}
    changed()
  end
end

--- Put the cursor in a clip where it was clicked, on the grid but inside
--- the clip, so that the keys act on it.
local function cursor_into(id, beat)
  local c = api.clip_get(id)
  pointing = true
  to_arrange()
  paw.cursor.set_track(c.track)
  beat = snap(beat or c.start)
  if beat < c.start or beat >= c.start + c.length then beat = c.start end
  paw.cursor.set_beat(beat)
  pointing = false
end

--- The clips on drawn rows `row0` to `row1` reaching into beats `from` to `to`.
local function clips_in(row0, row1, from, to)
  local rows, out = paw.groups.rows(), {}
  for row = math.max(1, math.min(row0, row1)), math.min(#rows, math.max(row0, row1)) do
    for _, c in ipairs(api.clip_list(rows[row])) do
      if c.start < to - 1e-9 and c.start + c.length > from + 1e-9 then out[#out + 1] = c.id end
    end
  end
  return out
end

--- A click on a clip: the cursor goes there, and `mode` says what happens
--- to the chosen clips: "only" (or nil) the clip alone, "toggle" (Ctrl) in
--- or out, "add" (Shift) the clips from the last one chosen to this one: on
--- one track those that start between them, across tracks those in the
--- rectangle the two span.
function A.select_clip(id, beat, mode)
  cursor_into(id, beat)
  mode = mode or "only"
  if mode == "only" then
    -- What was chosen before, for a double click that follows.
    recently_chosen = { set = {}, at = api.now() }
    for _, other in ipairs(M.chosen_clips()) do recently_chosen.set[other] = true end
    return choose_clips({ [id] = true }, id, false)
  end
  local set = {}
  for _, other in ipairs(M.chosen_clips()) do set[other] = true end
  if mode == "toggle" then
    set[id] = not set[id] or nil
    return choose_clips(set, set[id] and id or picked.anchor, true)
  end
  local anchor = picked.anchor and set[picked.anchor] and pcall(api.clip_get, picked.anchor) and api.clip_get(picked.anchor)
  local c = api.clip_get(id)
  if not anchor then
    set[id] = true
    return choose_clips(set, id, true)
  end
  local rows = row_index()
  local from, to = math.min(anchor.start, c.start), math.max(anchor.start, c.start)
  if anchor.track == c.track then
    for _, other in ipairs(api.clip_list(c.track)) do
      if other.start >= from - 1e-9 and other.start <= to + 1e-9 then set[other.id] = true end
    end
  else
    to = math.max(anchor.start + anchor.length, c.start + c.length)
    for _, other in ipairs(clips_in(rows[anchor.track] or 1, rows[c.track] or 1, from, to)) do set[other] = true end
  end
  set[id] = true
  choose_clips(set, anchor.id, true)
end

--- A box drawn with the right button over the timeline, from row `row0`
--- at `beat0` to `row1` at `beat1` (rows of drawn tracks, from 1): the
--- clips it touches are chosen. `mode` as for `select_clip`: "add" keeps
--- those chosen already, "toggle" turns the ones it touches over.
function A.select_clips_box(row0, beat0, row1, beat1, mode)
  local set = {}
  if mode == "add" or mode == "toggle" then
    for _, id in ipairs(M.chosen_clips()) do set[id] = true end
  end
  local touched = clips_in(row0, row1, math.min(beat0, beat1), math.max(beat0, beat1))
  for _, id in ipairs(touched) do
    if mode == "toggle" and set[id] then set[id] = nil else set[id] = true end
  end
  choose_clips(set, touched[1] or picked.anchor, true)
  local count = 0
  for _ in pairs(set) do count = count + 1 end
  return count
end

--- Choose a set of clips (`{ [id] = true }`), as visual mode's selection:
--- what `:select` does.
function M.choose_clips(set) choose_clips(set, nil, true) end

--- Every clip on the timeline, chosen.
function A.select_all_clips()
  local set = {}
  for _, track in ipairs(paw.groups.rows()) do
    for _, c in ipairs(api.clip_list(track)) do set[c.id] = true end
  end
  choose_clips(set, nil, true)
end

--- Drop a clip somewhere else: at `start`, on `track` if given. With `copy`
--- the clip stays and a copy is dropped.
function A.move_clip(id, start, track, copy)
  local clip = paw.clip(id)
  start = snap(start)
  track = track and track ~= 0 and track or clip:get().track
  if copy then
    local made = paw.restore_clip(paw.util.merge(clip:snapshot(), { start = start }), track)
    return made.id
  end
  api.clip_set(id, "start", start)
  if track ~= api.clip_get(id).track then api.clip_set(id, "track", track) end
  return id
end

--- The clips a gesture on clip `id` acts on: all the chosen ones if it is
--- one of them, else that clip alone, which is then the chosen one.
local function grabbed_clips(id)
  local ids = M.chosen_clips()
  for _, other in ipairs(ids) do
    if other == id then return ids end
  end
  choose_clips({ [id] = true }, id, false)
  return { id }
end

--- Drag clips: the one at `id` and, if it is chosen, the others chosen with
--- it, by `dbeat` beats and `drows` rows of drawn tracks, keeping their
--- places to one another. Snapping is relative: the clips move by whole
--- grid steps, so the grabbed clip keeps its distance from the grid line
--- before it, which is none if it started on one. `free` (Shift) moves them
--- by exactly `dbeat`. With `copy` (Ctrl) they stay and copies are dropped,
--- which are then the chosen clips. Nothing goes before the start or off
--- the tracks. One undo step, as one call. Returns the ids of what moved.
function A.drag_clips(id, dbeat, drows, copy, free)
  local ids = grabbed_clips(id)
  local by = free and dbeat or paw.util.round(dbeat, paw.opt.grid)
  drows = math.floor((drows or 0) + 0.5)
  local rows, list = row_index(), paw.groups.rows()
  local clips = {}
  for i, cid in ipairs(ids) do
    local c = api.clip_get(cid)
    clips[i] = c
    by = math.max(by, -c.start)
    local row = rows[c.track]
    if row then drows = paw.util.clamp(drows, 1 - row, #list - row) end
  end
  if math.abs(by) < 1e-9 and drows == 0 and not copy then return ids end
  local out = {}
  for i, c in ipairs(clips) do
    local row = rows[c.track]
    local track = row and list[row + drows] or c.track
    if copy then
      local made = paw.restore_clip(paw.util.merge(paw.clip(c.id):snapshot(), { start = c.start + by }), track)
      out[i] = made.id
    else
      api.clip_set(c.id, "start", c.start + by)
      if track ~= c.track then api.clip_set(c.id, "track", track) end
      out[i] = c.id
    end
  end
  if copy then
    local set = {}
    for _, cid in ipairs(out) do set[cid] = true end
    choose_clips(set, out[1], #out > 1)
  end
  return out
end

--- Move what plays inside a MIDI clip by `by` beats: its notes and its
--- controller moves. What goes before the clip's start keeps a place below
--- 0, where it is not played or drawn, and comes back when the start is
--- dragged out over it again.
local function shift_content(id, by)
  local notes = api.clip_notes(id)
  for _, n in ipairs(notes) do n.start = n.start + by end
  api.clip_set_notes(id, notes)
  local c = api.clip_get(id)
  if c.control_count > 0 then
    local controls = api.clip_controls(id)
    for _, move in ipairs(controls) do move.start = move.start + by end
    api.clip_set_controls(id, controls)
  end
  -- The takes that are not playing stay lined up with the one that is.
  paw.takes.shift(id, by)
end

--- Beats in an audio clip's offset into its file.
--- How far before an audio clip's start its file begins, in beats of the
--- tempo map there (a negative number).
local function file_start(c)
  return paw.time.to_beat(math.max(0, paw.time.to_seconds(c.start) - paw.stretch.lead(c))) - c.start
end

--- Drag an edge of a clip, and the same edge of the clips chosen with it:
--- `edge` is "start" or "end", `dbeat` how far it went. The grabbed clip's
--- edge lands on the grid unless `free` (Shift); the others change by as
--- much, each within what it can do. The start is trimmed without moving
--- what plays: an audio clip starts further into its file, a MIDI clip
--- hides the notes before its new start, which come back when it is
--- dragged out again. A clip is never shorter than a grid step (a 64th of
--- a beat when free). With `slip` (Alt) the edge stays and what plays
--- inside the clip moves instead. With Alt and Shift on the right edge,
--- the sound is stretched instead (`A.stretch_clips`). One undo step.
--- Returns the ids.
function A.trim_clips(id, edge, dbeat, free, slip)
  if slip and free and edge == "end" then return A.stretch_clips(id, dbeat) end
  local ids = grabbed_clips(id)
  local held = api.clip_get(id)
  local least = free and 1 / 64 or paw.opt.grid
  if slip then
    for _, cid in ipairs(ids) do
      local c = api.clip_get(cid)
      if c.loop then
        -- A looped clip's repeats turn round under it.
        paw.stretch.move_content(cid, -dbeat)
      elseif c.kind == "audio" then
        -- Later in the clip is earlier in the file, which has no time before 0.
        api.clip_set(cid, "offset", math.max(0, c.offset - paw.stretch.file_seconds(c, dbeat)))
      else
        shift_content(cid, dbeat)
      end
    end
    return ids
  end
  local at = edge == "start" and held.start or held.start + held.length
  local by = (free and math.max(0, at + dbeat) or snap(at + dbeat)) - at
  if math.abs(by) < 1e-9 then return ids end
  for _, cid in ipairs(ids) do
    local c = api.clip_get(cid)
    if edge == "start" then
      local d = math.min(by, c.length - least)
      d = math.max(d, -c.start)
      -- A looped clip turns its loop round instead of running out of file.
      if c.kind == "audio" and not c.loop then d = math.max(d, file_start(c)) end
      if math.abs(d) > 1e-9 then
        api.clip_set(cid, "start", c.start + d)
        api.clip_set(cid, "length", c.length - d)
        if c.loop then
          paw.stretch.move_content(cid, d)
        elseif c.kind == "audio" then
          api.clip_set(cid, "offset", math.max(0, c.offset + paw.stretch.file_seconds(c, d)))
        else
          shift_content(cid, -d)
        end
        if c.kind == "audio" then
          api.clip_set(cid, "fade_in", math.min(c.fade_in, c.length - d))
          api.clip_set(cid, "fade_out", math.min(c.fade_out, c.length - d))
        end
      end
    else
      local length = math.max(least, c.length + by)
      api.clip_set(cid, "length", length)
      if c.kind == "audio" then
        api.clip_set(cid, "fade_in", math.min(c.fade_in, length))
        api.clip_set(cid, "fade_out", math.min(c.fade_out, length))
      end
    end
  end
  return ids
end

--- The right edge of an audio clip dragged with Alt and Shift: what it
--- plays is stretched to end where the edge lands on the grid, without
--- changing its pitch, and that of the audio clips chosen with it by as
--- many beats (`paw.stretch.to`). The stretched sound is made once the
--- edge is let go. One undo step. Returns the ids.
function A.stretch_clips(id, dbeat)
  local ids = grabbed_clips(id)
  local held = api.clip_get(id)
  local at = held.start + held.length
  local by = snap(at + dbeat) - at
  if math.abs(by) < 1e-9 then return ids end
  for _, cid in ipairs(ids) do
    local c = api.clip_get(cid)
    if c.kind == "audio" then
      local ok, err = pcall(paw.stretch.to, cid, math.max(paw.opt.grid, c.length + by))
      if not ok then paw.notify(tostring(err):gsub("^[^:]*:%d+: ", ""), "warn") end
    end
  end
  return ids
end

--- The clip menu's "Stretch to the selection", "Stretch to the loop" and
--- "Reset stretch" (`what` "selection", "loop" or "reset"), on audio clip
--- `id`: it is stretched to start and end where the time selection or the
--- loop does, or plays its file at its own speed again.
function A.stretch_clip(id, what)
  local from, to
  if what == "selection" then
    local sel = paw.keymap.selection()
    -- Clips chosen with the pointer make a selection too: not one of time.
    if not (sel and not sel.clips and sel.c0 and sel.c1 and sel.c1 > sel.c0) then
      return paw.notify("select a stretch of time to stretch the clip to", "warn")
    end
    from, to = sel.c0, sel.c1
  elseif what == "loop" then
    local t = api.transport_get()
    if not (t.loop_end > t.loop_start) then return paw.notify("there is no loop to stretch the clip to", "warn") end
    from, to = t.loop_start, t.loop_end
  end
  local ok, err = pcall(function()
    if from then paw.stretch.fit(id, from, to) else paw.stretch.reset(id) end
  end)
  if not ok then paw.notify(tostring(err):gsub("^[^:]*:%d+: ", ""), "warn") end
end

--- Warp markers in the window (`paw.stretch.warp_add`): a double click on
--- an audio clip's top band puts one at `beat`; a marker's handle dragged
--- moves marker `index` to `beat` (on the grid unless `free`), stretching
--- the sound on either side of it; its menu takes it off. Each one undo
--- step; a refusal is said, not raised.
local function warp_run(f, ...)
  local ok, err = pcall(f, ...)
  if not ok then paw.notify((tostring(err):gsub("^[^:]*:%d+: ", ""):gsub("^runtime error: ", "")), "warn") end
end

function A.warp_add(id, beat)
  warp_run(paw.stretch.warp_add, id, math.max(0, beat))
end

function A.warp_move(id, index, beat, free)
  warp_run(paw.stretch.warp_move, id, index, free and math.max(0, beat) or snap(beat))
end

function A.warp_remove(id, index)
  warp_run(paw.stretch.warp_remove, id, index)
end

--- The handle at a top corner of an audio clip: its fade in (`which` "in")
--- or out ("out") is set to `beats`, and so is that of the audio clips
--- chosen with it, each no longer than the clip. One undo step.
function A.set_fade(id, which, beats)
  local field = which == "out" and "fade_out" or "fade_in"
  for _, cid in ipairs(grabbed_clips(id)) do
    local c = api.clip_get(cid)
    if c.kind == "audio" then api.clip_set(cid, field, paw.util.clamp(beats, 0, c.length)) end
  end
end

--- A drag on the top line of an audio clip: its gain, in dB, is set to
--- `db`, and that of the audio clips chosen with it changes by as much,
--- each between -60 and +24 dB. The waveform is drawn as loud as it plays.
function A.set_clip_gain(id, db)
  local by = db - api.clip_get(id).gain
  for _, cid in ipairs(grabbed_clips(id)) do
    local c = api.clip_get(cid)
    if c.kind == "audio" then api.clip_set(cid, "gain", paw.util.clamp(c.gain + by, -60, 24)) end
  end
end

--- Drag a clip's right edge to a new length, never shorter than a grid step.
function A.resize_clip(id, length)
  api.clip_set(id, "length", math.max(paw.opt.grid, paw.cursor.snap(length)))
end

--- A tempo (`kind` "tempo") or signature change flagged on the ruler at
--- `beat`: "move" it to beat `to` (on the grid; a signature to the bar
--- line nearest), "edit" its value through a prompt, or "remove" it.
function A.tempo_mark(action, kind, beat, to)
  local map = api.tempo_points()
  local list = kind == "tempo" and map.tempos or map.signatures
  local index
  for i, p in ipairs(list) do
    if math.abs(p.beat - beat) < 1e-6 then index = i end
  end
  if not index or index == 1 then return end
  local point = list[index]
  if action == "remove" then
    if kind == "tempo" then api.tempo_remove(point.beat) else api.signature_remove(point.beat) end
  elseif action == "move" then
    table.remove(list, index)
    local was = point.beat
    if kind == "tempo" then
      point.beat = math.max(paw.opt.grid, paw.cursor.snap(to))
    else
      -- To the nearest bar line, so that the bars before it stay whole.
      local n = paw.time.bar_of(to)
      local a, b = paw.time.bar_start(n), paw.time.bar_start(n + 1)
      point.beat = math.max(paw.time.bar_start(2), (to - a < b - to) and a or b)
    end
    list[#list + 1] = point
    if math.abs(point.beat - was) > 1e-9 then api.tempo_set_points(map.tempos, map.signatures) end
  elseif action == "edit" then
    local where = "bar " .. paw.time.bar_of(point.beat)
    if kind == "tempo" then
      paw.ui.input({ prompt = "tempo at " .. where .. ": ", text = string.format("%g", point.bpm) }, function(text)
        local bpm = tonumber(text)
        if bpm then api.tempo_set(point.beat, bpm) end
      end)
    else
      paw.ui.input({ prompt = "signature at " .. where .. ": ", text = point.num .. "/" .. point.den }, function(text)
        local n, d = tostring(text):match("^%s*(%d+)%s*/%s*(%d+)%s*$")
        if n then api.signature_set(point.beat, tonumber(n), tonumber(d)) end
      end)
    end
  end
end

-- The tempo lane under the ruler. A frontend names a height in it as a
-- fraction, 0 at the bottom, as for the automation lanes.

--- Show the tempo lane, or hide it.
function A.tempo_lane(on)
  if on == nil then return paw.tempolane.toggle() end
  paw.tempolane.show(on)
  return on
end

--- A click on the lane: a tempo change at the beat, on the grid.
function A.tempo_point_add(beat, fraction)
  paw.tempolane.add(snap(beat), paw.tempolane.bpm(fraction))
end

--- A change dragged to a beat and a height. The first change, the start's,
--- only changes its tempo.
function A.tempo_point_move(beat, to, fraction)
  paw.tempolane.move(beat, snap(to), paw.tempolane.bpm(fraction))
end

function A.tempo_point_remove(beat)
  paw.tempolane.remove(beat)
end

--- Make the change at `beat` ramp to the next, or hold again.
function A.tempo_point_ramp(beat)
  return paw.tempolane.ramp(beat)
end

--- Draw over the lane with a pencil: `points` are `{ beat, fraction }`.
function A.tempo_draw(points)
  local out = {}
  for i, p in ipairs(points) do out[i] = { snap(p[1]), paw.tempolane.bpm(p[2]) } end
  paw.tempolane.draw(out)
end

--- A double click on an empty lane: a clip of one bar in the bar clicked.
function A.add_clip(track, beat)
  local start = paw.time.bar_floor(math.max(0, beat))
  local id = api.clip_add(track, { start = start, length = paw.time.bar(start) })
  A.select(track, api.clip_get(id).start)
  return id
end

--- Open a clip's notes; an audio clip has none to open. An extension that
--- has an editor of its own for some clips adds a function to
--- `paw.frontend.openers`, which is asked first: it gets the clip and
--- returns true if it has opened it.
function A.open_clip(id)
  local clip = paw.clip(id)
  -- Opening one of several chosen clips edits them all. A double click's
  -- first click had chosen it alone a moment before.
  local before = recently_chosen and api.now() - recently_chosen.at < 1500 and recently_chosen.set
  if not (before and before[id]) then
    before = {}
    for _, other in ipairs(M.chosen_clips()) do before[other] = true end
  end
  local together = {}
  if before[id] then
    for other in pairs(before) do
      local ok, c = pcall(api.clip_get, other)
      if ok and c.kind == "midi" then together[#together + 1] = other end
    end
    table.sort(together)
  end
  A.select_clip(id, clip.start)
  for _, opener in ipairs(M.openers) do
    if opener(clip) then return end
  end
  if clip.kind ~= "midi" then return end
  -- Opened by the pointer, the roll shows the clips whole where it can.
  paw.ui.views.pianoroll.fit_next = true
  if #together > 1 then return paw.roll_clips.open(together, id) end
  paw.ui.views.pianoroll:edit(clip)
end

--- The record button. With nothing being recorded: arm the selected track
--- if no track is armed, then record from the playhead. Otherwise: end the
--- take and stop.
function A.record()
  local t = api.transport_get()
  if t.recording or t.take then
    paw.transport.recording = false
    if t.playing then paw.transport.stop() end
    return
  end
  local armed = false
  for _, id in ipairs(api.track_list()) do armed = armed or api.track_get(id, "armed") end
  if not armed then
    local track = paw.cursor.track()
    if not track then
      return paw.notify("nothing to record on: select a track, or arm one with its R button", "warn")
    end
    track.armed = true
    paw.notify("recording on " .. track.name .. ": it was armed for you (its R button)")
  end
  paw.transport.record()
end

function A.close_roll()
  paw.ui.hide("pianoroll")
  to_arrange()
end

--- Run a command on a clip or a track that was not under the cursor: what
--- a context menu does. The cursor goes there first, as a click would put it.
function A.clip_command(id, beat, line)
  A.menu_target(id, beat)
  paw.commands.exec(line)
end

--- The cursor goes to the clip a menu was opened on; the chosen clips stay
--- chosen if it is one of them, else it is chosen alone.
function A.menu_target(id, beat)
  local among = false
  for _, other in ipairs(M.chosen_clips()) do among = among or other == id end
  if among then return cursor_into(id, beat) end
  A.select_clip(id, beat)
end

function A.track_command(id, line)
  A.select(id)
  paw.commands.exec(line)
end

--- Set a device offline, or back online.
function A.toggle_offline(id)
  paw.loading.toggle(paw.device(id))
end

--- Start a plugin again that has stopped working.
function A.restart_device(id)
  local ok, err = pcall(api.device_restart, id)
  if not ok then paw.notify(tostring(err):match("^[^\n]*"), "error") end
end

--- An entry an extension added to a menu (`paw.frontend.menus`), by its
--- place in the list: `target` is the clip or the track that was clicked.
--- The timeline's entries are also offered by the buttons that make a
--- track, which have no place to give: no track, or a beat below 0, leaves
--- the cursor where it is.
function A.menu(kind, index, target, beat)
  local entry = (M.menus[kind] or {})[index]
  if not entry then return end
  if beat and beat < 0 then beat = nil end
  if kind == "clip" then
    A.menu_target(target, beat)
  elseif target and target > 0 then
    A.select(target, beat)
  else
    to_arrange()
  end
  if entry.run then
    entry.run(target, beat)
  elseif entry.command then
    paw.commands.exec(entry.command)
  end
end

--- A click on an entry of an extension's band under the ruler
--- (`paw.frontend.bands`), by the band's place in the list and the entry's
--- in what it returns: its command runs, in the arrange view.
function A.band(band, index)
  if not M.bands[band] then return end
  local entry = band_entries(band)[index]
  if not entry then return end
  to_arrange()
  if entry.run then
    entry.run(entry)
  elseif entry.command then
    paw.commands.exec(entry.command)
  end
end

--- Drag along the ruler: loop that stretch. Too short a drag is a click,
--- which only moves the playhead.
function A.set_loop(from, to)
  from, to = snap(math.min(from, to)), snap(math.max(from, to))
  if to - from < paw.opt.grid then return api.transport_seek(from) end
  paw.transport.loop_start, paw.transport.loop_end = from, to
  paw.transport.loop_enabled = true
end

--- The pointer on the floating window, drawn as the lines of `M.float`:
--- `kind` is "down" for a click, "scroll_up" or "scroll_down" for the
--- wheel; `line` and `col` count from 1. It goes where a click in the
--- terminal goes: in a picker a click on a row selects it, and a click on
--- the selected row (the second of a double click) chooses it.
function A.float_pointer(kind, line, col)
  local float = paw.ui.float
  if not float then return end
  for _, r in ipairs(paw.ui.rects) do
    if r.name == float.name then
      return paw.ui.mouse({ kind = kind, button = "left", x = r.x + math.max(0, (col or 1) - 1), y = r.y + math.max(0, line - 1) })
    end
  end
end

local splitting = false

--- Split every chosen clip that the edit cursor is inside, there: what
--- `clip.split` (`S`, and the clip menu's "Split at the edit cursor") does
--- while clips are chosen. Both halves are chosen afterwards. Returns false
--- when no clip is chosen, for `clip.split` to split the clip under the
--- cursor instead.
function A.split_clips()
  local ids = M.chosen_clips()
  if splitting or #ids == 0 then return false end
  local beat, track, visual = paw.cursor.beat, paw.cursor.track_id(), paw.keymap.mode == "x"
  local set = {}
  splitting, pointing = true, true
  local ok, err = pcall(function()
    for _, id in ipairs(ids) do
      set[id] = true
      local c = api.clip_get(id)
      if beat > c.start + 1e-9 and beat < c.start + c.length - 1e-9 then
        paw.cursor.set_track(c.track)
        paw.commands.exec("clip.split")
        local right = paw.track(c.track):clip_at(beat)
        if right then set[right.id] = true end
      end
    end
  end)
  if track then paw.cursor.set_track(track) end
  splitting, pointing = false, false
  if not ok then error(err, 0) end
  choose_clips(set, ids[1], visual or #ids > 1)
  return true
end

--- Glue the chosen clips on each track into one clip, the gaps between
--- them included: what the clip menu's "Glue" and `J` on chosen clips do.
--- MIDI clips are joined; audio clips are glued into a new file
--- (`paw.media.glue`). A track whose chosen clips are of both kinds is left
--- as it is.
function A.glue_clips()
  local region = clip_region()
  if not region then return paw.notify("no clips chosen to glue", "warn") end
  local glued = false
  for _, track in ipairs(paw.edit.arrange.tracks(region)) do
    local audio, midi = {}, 0
    for _, c in ipairs(api.clip_list(track)) do
      if region.clips[c.id] then
        if c.kind == "audio" then audio[#audio + 1] = c.id else midi = midi + 1 end
      end
    end
    local ok, done = true, false
    if #audio >= 2 and midi == 0 then
      ok, done = pcall(paw.media.glue, audio)
      done = ok and done and done.glued and done.glued > 1
    elseif midi >= 2 and #audio == 0 then
      ok, done = pcall(paw.edit.arrange.join, track, region.c0, region.c1, region.clips)
    elseif #audio > 0 and midi > 0 then
      paw.notify("audio and MIDI clips cannot be glued together", "warn")
    end
    if not ok then return paw.notify(tostring(done):match("^[^\n]*"), "warn") end
    glued = glued or done
  end
  if not glued then paw.notify("glue takes two or more chosen clips of one kind on a track", "warn") end
  local left = {}
  for _, id in ipairs(M.chosen_clips()) do left[id] = true end
  choose_clips(left, nil, false)
end

--- The clip menu's "Split at the edit cursor" and "Glue", opened on clip
--- `id`: on the chosen clips if it is one of them, else on it alone. The
--- edit cursor stays where it is.
function A.menu_split(id)
  grabbed_clips(id)
  if not A.split_clips() then paw.commands.exec("clip.split") end
end

function A.menu_glue(id)
  grabbed_clips(id)
  A.glue_clips()
end

--- Drag an edge of the loop, "start" or "end", to a beat on the grid; it
--- stays at least a grid step long.
function A.set_loop_edge(edge, beat)
  local t = paw.transport
  beat = snap(beat)
  if edge == "start" then
    t.loop_start = math.min(beat, t.loop_end - paw.opt.grid)
  else
    t.loop_end = math.max(beat, t.loop_start + paw.opt.grid)
  end
end

--- Drag an edge of the punch range, "start" or "end", to a beat on the
--- grid (anywhere with `free`); it stays at least a grid step long.
function A.set_punch_edge(edge, beat, free)
  local t = paw.transport
  beat = free and math.max(0, beat) or snap(beat)
  local least = free and 1 / 64 or paw.opt.grid
  if edge == "start" then
    t.punch_start = math.min(beat, t.punch_end - least)
  else
    t.punch_end = math.max(beat, t.punch_start + least)
  end
end

--- Punch in and out between two beats, on the grid, and turn punching on.
function A.set_punch(from, to)
  from, to = snap(math.min(from, to)), snap(math.max(from, to))
  if to - from < paw.opt.grid then return end
  paw.transport.punch_start, paw.transport.punch_end = from, to
  paw.transport.punch_enabled = true
end

--- Show a track's take lanes under its clips, or hide them. Returns
--- whether they show now.
function A.take_lanes(track)
  return paw.takes.toggle_lanes(track)
end

--- A drag across take lane `take` of a track, from beat `from` to `to`:
--- that take plays over the stretch (see `paw.takes.comp`). The ends land
--- on the grid unless `free` (Shift). A stretch shorter than a grid step is
--- a click, which chooses the take for the piece under the pointer. One
--- undo step. Returns how many pieces play the take now.
function A.comp(track, take, from, to, free)
  local a, b = math.min(from, to), math.max(from, to)
  if not free then a, b = snap(a), snap(b) end
  a = math.max(0, a)
  if b - a < (free and 1 / 64 or paw.opt.grid) - 1e-9 then
    return A.take_click(track, take, math.min(from, to)) and 1 or 0
  end
  local n = paw.takes.comp(track, take, a, b)
  if n > 0 then paw.cursor.set_track(track) end
  return n
end

--- A click on take lane `take` of a track: the piece under the pointer
--- plays that take. Returns its clip, or nil when there is none there.
function A.take_click(track, take, beat)
  local c = paw.takes.choose_at(track, take, beat)
  if c then
    pointing = true
    to_arrange()
    paw.cursor.set_track(track)
    pointing = false
  end
  return c and c.id or nil
end

--- A click on the ruler: the edit cursor goes to the beat, on the grid,
--- and the playhead with it.
function A.ruler_click(beat)
  beat = snap(beat)
  pointing = true
  paw.cursor.set_beat(beat)
  pointing = false
  api.transport_seek(beat)
end

--- Drag across empty lanes: select that stretch of time on those tracks,
--- as visual mode does, for the keys and the menu to act on. Rows are
--- places in the track list, from 1.
function A.select_range(row0, beat0, row1, beat1)
  local tracks = paw.groups.rows()
  if #tracks == 0 then return end
  to_arrange()
  local clamp = paw.util.clamp
  paw.cursor.set_track(tracks[clamp(row0, 1, #tracks)])
  paw.cursor.set_beat(snap(math.min(beat0, beat1)))
  paw.keymap.visual_start("v")
  paw.cursor.set_track(tracks[clamp(row1, 1, #tracks)])
  paw.cursor.set_beat(snap(math.max(beat0, beat1)))
end

--- Type keys as if at the keyboard: what a menu entry for an operator does
--- to a selection.
--- The window got the focus of the desktop (true), or lost it.
function A.focus(on)
  paw.ui.has_focus = on
  paw.emit("ui.focus", { focused = on })
end

function A.keys(keys)
  -- Keys typed in the main window are not for a view in a window of its
  -- own, which sends its own (`paw.canvas.key`): they go to the window
  -- that had the keyboard before.
  if paw.canvas.open_views[paw.ui.focused] and not paw.ui.float and not paw.ui.grabber then
    paw.canvas.back(paw.ui.focused)
  end
  paw.keymap.feed(keys)
end

function A.set_volume(track, db) api.track_set(track, "volume", paw.util.fader_db(api.track_get(track, "volume"), db)) end

--- A fader, a pan or a parameter is under the pointer (`on`), or let go:
--- in touch mode it writes automation for as long as it is held. `device`
--- and `param` name a parameter; 0 and "" for a fader or a pan.
function A.hold(track, target, device, param, on)
  if target ~= "param" then device, param = nil, nil end
  api.automation_hold(track, target, device, param, on)
end

--- Where a file was chosen is where the next choice starts.
local function remember_dir(path)
  paw.state.pick_dir = path:match("^(.*)/[^/]*$") or paw.state.pick_dir
end

--- Leave the project: `what` is "quit", "new" (an empty project),
--- "open" (another, chosen from a list) or "open:<path>" (that one, already
--- chosen: from the recent list, by the desktop's dialog, or dropped on the
--- window). `how` is "save" to save its
--- changes first (asking where, for a project with no file yet),
--- "discard" to throw them away, or "go" when there are none.
function A.leave(how, what)
  local function go()
    if what == "quit" then
      if how == "discard" then paw.autosave.discard = true end
      api.quit(0)
    elseif what == "new" then
      paw.project.new()
    elseif what:match("^open:") then
      remember_dir(what:sub(6))
      paw.recent.open(what:sub(6))
    else
      paw.commands.exec("open")
    end
  end
  if how ~= "save" then return go() end
  if api.project_get("path") then
    paw.project.write()
    return go()
  end
  M.save_as(go)
end

--- A file chosen in the desktop's dialog, for what `kind` says: "import"
--- (a sound file on a new track, a MIDI file's tracks at the cursor) or
--- "saveas" (the project's new file).
function A.chosen(kind, path)
  remember_dir(path)
  if kind == "saveas" then
    local saved, note = paw.project.write(path)
    paw.notify(note and (note .. ": " .. saved) or ("saved " .. saved))
  else
    paw.commands.run("import", { path })
  end
end

--- Files dropped on the window: sound files, MIDI files and projects. A
--- project (the first of them, when there are several) is not opened here,
--- for the window asks about unsaved changes first: its path is returned as
--- `open`. A MIDI file's tracks come in below the cursor's at `beat`, or
--- the edit cursor. Sound files go on the track at `row` (a place in the list of
--- drawn tracks, from 1) at `beat`, snapped, one after another; with no
--- track there (below the last, or where the window cannot tell) each gets
--- a track of its own, at `beat` or the edit cursor. Anything else is said
--- to be refused. Returns `{ open, clips, refused }`.
function A.drop(paths, row, beat)
  local out = { clips = {}, refused = 0 }
  local sounds, midis = {}, {}
  for _, path in ipairs(paths) do
    if paw.is_audio_file(path) then
      sounds[#sounds + 1] = path
    elseif paw.midifile.is_midi_file(path) then
      midis[#midis + 1] = path
    elseif path:lower():match("%.json$") or paw.project.is_folder(path) then
      out.open = out.open or path
    else
      out.refused = out.refused + 1
      paw.notify("cannot take " .. (path:match("([^/]+)$") or path) .. ": it is not a sound file, a MIDI file or a project", "warn")
    end
  end
  if out.open then return out end
  local rows = paw.groups.rows()
  local track = row and rows[row]
  local start = beat and snap(beat)
  for _, path in ipairs(midis) do
    local ok, done = pcall(paw.midifile.import, path, { start = start })
    if ok then
      for _, clip in ipairs(done.clips) do out.clips[#out.clips + 1] = clip.id end
      paw.notify(string.format("dropped %s: %d notes on %d tracks", path:match("([^/]+)$") or path, done.notes, #done.tracks))
    else
      out.refused = out.refused + 1
      paw.notify("could not import " .. path .. ": " .. tostring(done), "error")
    end
  end
  for _, path in ipairs(sounds) do
    local ok, clip = pcall(paw.import_audio, path, { track = track, start = start })
    if ok then
      out.clips[#out.clips + 1] = clip.id
      if track then start = clip.start + clip.length end
      paw.notify(string.format("dropped %s: %.1f beats on track “%s”", path:match("([^/]+)$") or path, clip.length, clip:track().name))
    else
      out.refused = out.refused + 1
      paw.notify("could not import " .. path .. ": " .. tostring(clip), "error")
    end
  end
  return out
end

--- The lanes of a lane's track are no longer shown as rows.
function A.hide_lane_rows(lane)
  paw.lanes.open(api.lane_get(lane).track, false)
end

--- Show a track's lanes as rows of their own under it, or hide them. A
--- track that has none yet gets one for its fader, to draw on.
function A.lane_rows(track)
  if not paw.lanes.is_open(track) and #api.lane_list(track) == 0 then A.lane(track, "volume") end
  return paw.lanes.toggle(track)
end

--- Render as the window's dialog says: `o.path`, `o.range` (a name from
--- `render_dialog`), `o.format` ("wav", "flac", "mp3", "ogg" or "opus"), `o.quality` (for those
--- three: "low" to "best"), `o.bits`, `o.tail`
--- seconds, `o.normalize` dB or nil, `o.dither`, `o.mono`, and `o.stems`
--- for a file per track in a directory named after the path. `o.tags`
--- (`title`, `artist`, ... as `paw.render.tags` has them, an empty one
--- taking it out) becomes the project's tags, which the files carry. It
--- runs in the background: the state's `modal.render` says how far it is.
function A.render(o)
  if o.tags then require("paw.render").tags(o.tags) end
  local opts = {
    tail = tonumber(o.tail), bits = tonumber(o.bits), dither = o.dither and true or nil,
    normalize = tonumber(o.normalize), channels = o.mono and 1 or nil, background = true,
  }
  local format = ({ flac = "flac", mp3 = "mp3", ogg = "ogg", opus = "opus" })[o.format] or "wav"
  if format == "flac" and opts.bits == 32 then opts.bits = 24 end
  if format ~= "wav" and format ~= "flac" then opts.bits, opts.dither, opts.quality = nil, nil, o.quality end
  local range = o.range or "song"
  local region = range:match("^region:(%d+)$")
  if region then
    local r = paw.markers.find({ id = tonumber(region) })
    if not r then error("that region is gone", 0) end
    opts.start, opts["end"] = r.beat, r.beat + r.length
  elseif range ~= "song" then
    opts.range = range
  end
  local path = paw.util.expand_path(tostring(o.path or ""))
  if path == "" then error("render: name a file to write", 0) end
  local stem = path:gsub("%.[Ww][Aa][Vv]$", ""):gsub("%.[Ff][Ll][Aa][Cc]$", ""):gsub("%.[Mm][Pp]3$", "")
    :gsub("%.[Oo][Gg][Gg]$", ""):gsub("%.[Oo][Pp][Uu][Ss]$", "")
  if o.stems then
    opts.format = format
    local files = paw.render_stems(stem .. " stems", opts)
    return paw.notify(string.format("rendering %d stem%s into %s", #files, #files == 1 and "" or "s", stem .. " stems"))
  end
  paw.render(stem .. "." .. format, opts)
  paw.notify("rendering " .. (stem:match("([^/]+)$") or stem) .. "." .. format .. " · Esc cancels")
end

-- Where a track's sound goes.

--- Where a track's sound goes, for a frontend to show and change:
---   output   the name of the track it plays into ("Master" without one)
---   targets  the tracks it could play into or send to, `{ id, name }` each;
---            the master is first, with id 0
---   sends    `{ target, name, level, pre }` each, levels in dB
--- A track cannot play into itself or into a track that plays into it.
function M.routing(track)
  local t = api.track_get(track)
  local targets = { { id = 0, name = "Master" } }
  -- Not a track whose sound reaches this one, by any route.
  local reaching = paw.routes.reaching(track)
  for _, id in ipairs(api.track_list()) do
    if id ~= track and not reaching[id] then targets[#targets + 1] = { id = id, name = api.track_get(id, "name") } end
  end
  local sends = {}
  for i, send in ipairs(t.sends or {}) do
    local ok, to = pcall(api.track_get, send.target)
    sends[i] = { target = send.target, name = ok and to.name or "?", level = send.level, pre = send.pre or false }
  end
  local ok, to = pcall(api.track_get, t.output or 0)
  return { output = t.output and ok and to.name or "Master", output_id = t.output or 0, targets = targets, sends = sends, master = t.master or false }
end

--- Play a track into another (`target` 0 or nil for the master).
function A.set_output(track, target)
  api.track_set(track, "output", target and target ~= 0 and target or nil)
end

--- Send a track's sound to another as well, at `level` dB (`paw.opt.send_level` without).
function A.add_send(track, target, level)
  local sends = api.track_get(track).sends
  for _, send in ipairs(sends) do
    if send.target == target then return end
  end
  sends[#sends + 1] = { target = target, level = level or paw.opt.send_level }
  api.track_set(track, "sends", sends)
end

--- Change the send at `index` (from 1): `level` in dB, `pre` whether it is
--- taken ahead of the fader; nil leaves either as it is.
function A.set_send(track, index, level, pre)
  local sends = api.track_get(track).sends
  if not sends[index] then return end
  if level ~= nil then sends[index].level = paw.util.fader_db(sends[index].level, level) end
  if pre ~= nil then sends[index].pre = pre and true or nil end
  api.track_set(track, "sends", sends)
end

function A.remove_send(track, index)
  local sends = api.track_get(track).sends
  if not sends[index] then return end
  table.remove(sends, index)
  api.track_set(track, "sends", sends)
end

--- The menu of the side-chain of a device: "None" first, then the tracks
--- that it can listen to. The last item tells if it takes the sound before
--- their fader. Each is `{ label, checked }`.
--- `act.choose_sidechain` takes one by place.
function M.sidechain_menu(device)
  local d = api.device_get(device)
  local out = { { label = "None: its own input", checked = d.sidechain == nil } }
  for _, source in ipairs(paw.routes.sidechain_sources(device)) do
    out[#out + 1] = { label = source.name, checked = source.id == d.sidechain }
  end
  out[#out + 1] = { label = "Before the fader", checked = d.sidechain_pre or false }
  return out
end

--- The menu of the other output pairs of a device. For each pair, it gives
--- `{ label, choices }`. The label names the pair and where it plays. The
--- choices (`{ label, checked }`) are "Nowhere" and the tracks that it can
--- play into. `act.route_pair` takes one. `act.spread_outputs` makes a
--- track for each pair that plays nowhere.
function M.outputs_menu(device)
  local out = {}
  local d = api.device_get(device)
  local reaching = paw.routes.reaching(d.track)
  for _, o in ipairs(paw.routes.outputs(device)) do
    if o.pair > 1 then
      local choices = { { label = "Nowhere: not heard", checked = o.target == nil } }
      for _, id in ipairs(api.track_list()) do
        if id ~= d.track and not reaching[id] then
          choices[#choices + 1] = { label = api.track_get(id, "name"), checked = id == o.target }
        end
      end
      out[#out + 1] = { label = string.format("%d %s → %s", o.pair, o.name, o.target_name or "not heard"), choices = choices }
    end
  end
  return out
end

--- Route a device's output pair `pair` (from 2) to the `index`th choice of
--- its menu (`M.outputs_menu`): 1 for nowhere, then the tracks it lists.
function A.route_pair(device, pair, index)
  if index == 1 then return paw.routes.set_output(device, pair, nil) end
  local d = api.device_get(device)
  local reaching = paw.routes.reaching(d.track)
  local n = 1
  for _, id in ipairs(api.track_list()) do
    if id ~= d.track and not reaching[id] then
      n = n + 1
      if n == index then return paw.routes.set_output(device, pair, id) end
    end
  end
end

function A.spread_outputs(device) paw.routes.spread(device) end

--- Choose from a device's side-chain menu (`M.sidechain_menu`), by place
--- from 1: none, a track, or the last entry, which turns taking it before
--- the fader on or off.
function A.choose_sidechain(device, index)
  local d = api.device_get(device)
  local sources = paw.routes.sidechain_sources(device)
  if index == 1 then
    paw.routes.set_sidechain(device, nil)
  elseif sources[index - 1] then
    paw.routes.set_sidechain(device, sources[index - 1].id, d.sidechain_pre)
  elseif index == #sources + 2 and d.sidechain then
    api.device_set(device, "sidechain_pre", not d.sidechain_pre)
  end
end

function A.set_pan(track, pan) api.track_set(track, "pan", paw.util.clamp(pan, -1, 1)) end

function A.toggle(track, flag) api.track_set(track, flag, not api.track_get(track, flag)) end

local function nth(list, group, index)
  local n = 0
  for _, choice in ipairs(list) do
    if choice.group == group then
      n = n + 1
      if n == index then return choice end
    end
  end
end

--- Choose a track's input from its menu (`M.input_menu`): the `index`th
--- entry, from 1, under the heading `group`.
function A.choose_input(track, group, index)
  local choice = nth(paw.audio.choices(track), group, index)
  if not choice then return end
  paw.audio.choose(track, choice)
  A.select(track)
end

--- Choose an audio device or a block size from `M.engine_menu`.
function A.choose_engine(group, index)
  local choice = nth(paw.audio.engine_choices(), group, index)
  if choice then paw.audio.choose_engine(choice) end
end

--- A click on a device of a track's chain, as a mixer strip lists them: the
--- track becomes the cursor's and the device panel gets the keyboard, on
--- the `index`th device, from 1.
function A.pick_device(track, index)
  A.select(track)
  local panel = paw.ui.views.devices
  for row, entry in ipairs(panel:rows()) do
    if not entry.param and entry.device.index == index then panel.row = row end
  end
  paw.ui.focus("devices")
end

function A.rename_track(track, name)
  name = name:match("^%s*(.-)%s*$")
  if name ~= "" then api.track_set(track, "name", name) end
end

--- Give a track one of the theme's colours by name, any `#rrggbb`, or "none".
function A.color_track(track, colour)
  A.track_command(track, "track.color " .. colour)
end

--- Drag a track's header to another place among the drawn rows, from 1.
--- It goes into the group of the track drawn above it where it lands (or
--- into that track, if it is an open group), and out of its own group if it
--- lands outside it. A group takes its tracks along.
function A.move_track(track, index)
  local groups = paw.groups
  -- The row is among the tracks that are drawn; the list may hold more.
  local rows = groups.rows()
  local target = rows[paw.util.clamp(index, 1, #rows)]
  for place, id in ipairs(api.track_list()) do
    if id == target then api.track_move(track, place) end
  end
  local above
  rows = groups.rows()
  for i, id in ipairs(rows) do
    if id == track then above = rows[i - 1] end
  end
  local want
  if above then
    want = groups.is_group(above) and not groups.folded(above) and above or groups.of(above)
  end
  if want ~= groups.of(track) then
    if want then
      -- A group cannot go inside itself; then it stays in its own group.
      pcall(groups.add, track, want)
    else
      while groups.of(track) do groups.remove(track, true) end
    end
  end
  if groups.is_group(track) then groups.gather(track) end
  local group = groups.of(track)
  if group then groups.gather(group) end
end

--- Drag a track's bottom edge: its height, as a share of the zoom's height
--- that every track has (`1` for that height, which is then not kept).
function A.set_track_height(track, share)
  api.track_set(track, "height", share)
end

--- A press on one of a track's M, S or R buttons swept down across others:
--- each it crosses is set as the first was (`flag` is "mute", "solo" or
--- "armed").
function A.set_flag(track, flag, on)
  if flag ~= "mute" and flag ~= "solo" and flag ~= "armed" then
    error("not a flag of a track: " .. tostring(flag), 2)
  end
  api.track_set(track, flag, on and true or false)
end

--- The same, for the drawn tracks from row `row0` to `row1` (from 1, either
--- way round): where a sweep has gone so far.
function A.sweep_flag(row0, row1, flag, on)
  local rows = paw.groups.rows()
  for row = math.max(1, math.min(row0, row1)), math.min(#rows, math.max(row0, row1)) do
    A.set_flag(rows[row], flag, on)
  end
end

--- Fold a group away or open it: a click on its triangle.
function A.fold(track)
  paw.groups.fold(track)
end

-- Notes, in the clips the piano roll has open. A gesture names a note by
-- its clip and its place there; where the roll edits several clips (see
-- `paw.roll_clips`), the chosen notes may be in any of them and a gesture
-- on one acts on all of them, each note staying in its own clip. Beats a
-- gesture gives are the roll's: from the start of the clip it names.

-- The notes chosen with the pointer: places in each clip, by clip id. They
-- are kept as long as the clip's notes are what the pointer's own edits
-- left; an edit made any other way (a key, an undo) forgets them, since
-- places move. Each window and terminal chooses notes of its own.
local chosen = {}
paw.seats.keep("frontend.chosen", function() return chosen end, function(c) chosen = c end,
  function() return {} end)

local function stamp_of(clip)
  local ok, data = pcall(api.clip_get, clip)
  return ok and data.stamp or nil
end

--- Choose notes of `clip` by their places (`{ [place] = true }`), as the
--- pointer would: what `:select` does.
function M.choose_notes(clip, places)
  chosen[clip] = next(places) and { places = places, stamp = stamp_of(clip) } or nil
  api.ui_redraw()
end

--- The places of the selected notes of `clip`, in order. None if the notes
--- of the clip changed after the selection.
function M.chosen_notes(clip)
  local entry = chosen[clip]
  if not entry or entry.stamp ~= stamp_of(clip) then return {} end
  local out = {}
  for place in pairs(entry.places) do out[#out + 1] = place end
  table.sort(out)
  return out
end

--- The clips a gesture on `clip` reaches, with how far each starts after
--- it (`offset`): every clip the roll edits when it is one of them, else
--- that clip alone.
local function parts_for(clip)
  local rc = paw.roll_clips
  if rc.editable(clip) then
    local parts = rc.parts()
    -- Offsets count from the clip named, which is the active one when the
    -- gesture gives beats.
    local base = rc.offset(clip)
    for _, part in ipairs(parts) do part.offset = part.offset - base end
    return parts
  end
  local c = api.clip_get(clip)
  return { { id = clip, clip = paw.clip(clip), offset = 0, start = c.start, length = c.length } }
end

--- The chosen notes of the clips a gesture on `clip` reaches: clip id ->
--- places, and how many there are.
local function chosen_map(clip)
  local map, count = {}, 0
  for _, part in ipairs(parts_for(clip)) do
    local places = M.chosen_notes(part.id)
    if #places > 0 then map[part.id], count = places, count + #places end
  end
  return map, count
end

--- Every chosen note of the clips the roll edits, as `{ clip, place }`.
--- @type function(): {{integer}}
function M.chosen_refs()
  local out = {}
  local active = paw.roll_clips.active()
  if not active then return out end
  for _, part in ipairs(parts_for(active)) do
    for _, place in ipairs(M.chosen_notes(part.id)) do out[#out + 1] = { part.id, place } end
  end
  return out
end

--- The chosen notes of `clip` (and of the clips edited with it) in words,
--- for a toolbar: `3 notes · 5.1.00 – 5.3.00`, or "" with none chosen.
function M.chosen_text(clip)
  local map, count = chosen_map(clip)
  if count == 0 then return "" end
  local first, last, clips = math.huge, -math.huge, 0
  for id, places in pairs(map) do
    local c = api.clip_get(id)
    local notes = api.clip_notes(id)
    clips = clips + 1
    for _, place in ipairs(places) do
      local n = notes[place]
      if n then first, last = math.min(first, c.start + n.start), math.max(last, c.start + n.start + n.length) end
    end
  end
  if first == math.huge then return "" end
  return string.format("%d note%s%s · %s – %s", count, count == 1 and "" or "s",
    clips > 1 and " in " .. clips .. " clips" or "", paw.time.format(first), paw.time.format(last))
end

--- Choose notes: `map` is clip id -> places, and replaces every choice.
local function choose_all(map)
  chosen = {}
  for clip, places in pairs(map) do
    local set = {}
    for _, place in ipairs(places) do set[place] = true end
    if next(set) then chosen[clip] = { places = set, stamp = stamp_of(clip) } end
  end
  api.ui_redraw()
end

local function choose(clip, places)
  choose_all({ [clip] = places })
end

--- Where notes are now, given what they are: `wanted` is a list of
--- `{ start, pitch }`.
local function places_of(clip, wanted)
  local notes = paw.clip(clip):notes()
  local out, used = {}, {}
  for _, want in ipairs(wanted) do
    for place, n in ipairs(notes) do
      if not used[place] and n.pitch == want.pitch and math.abs(n.start - want.start) < 1e-6 then
        out[#out + 1], used[place] = place, true
        break
      end
    end
  end
  return out
end

-- A gesture's beat on the grid, unless it is `free` (Shift held) or snap
-- is off in the piano roll (`paw.opt.note_snap`): then to the nearest of
-- 960 ticks a beat, as MIDI files count them.
local function snap_note(beat, free)
  if free or not paw.opt.note_snap then return math.max(0, math.floor(beat * 960 + 0.5) / 960) end
  return note_snap(beat)
end

--- A press and drag on the empty grid: a note from `start` for `length`,
--- which is then the one chosen note. `free` leaves it off the grid. A
--- click gives no length (nil, or 0 or less): the note is the piano roll's
--- note length (`set_note_length`); a drawn length becomes that length. A
--- click on a note shown behind the roll's own (another track's) makes its
--- clip the one the roll edits instead. With several clips edited the note
--- goes into the one at `start`, the active one first.
function A.add_note(clip, pitch, start, length, free)
  local rc = paw.roll_clips
  if (not length or length <= 0) and clip == rc.active() then
    local behind = rc.context_at(pitch, start)
    if behind then return rc.activate(behind.clip) end
  end
  local part = parts_for(clip)[1]
  if rc.editable(clip) then
    part = rc.target(start + rc.offset(clip))
    start = start + rc.offset(clip) - part.offset
  end
  local c = part.clip
  free = free or not paw.opt.note_snap
  start = snap_note(start, free)
  if start >= c.length or c:note_at(pitch, start) then return end
  local roll = paw.ui.views.pianoroll
  if not length or length <= 0 then
    length = roll:step_length()
  else
    length = math.max(free and 1 / 64 or paw.opt.note_grid, snap_note(length, free))
    roll:set_step(length)
  end
  local index = c:add_note(roll.new_note(c, { pitch = pitch, start = start, length = math.min(length, c.length - start), velocity = paw.opt.velocity }))
  c:track():play_note(pitch, paw.opt.velocity, 150)
  choose(part.id, { index })
  return index
end

--- Ctrl and a click on a note shown behind the roll's own: its clip is
--- edited too, or no longer. `beat` is the roll's.
function A.context_click(clip, beat, pitch)
  local behind = paw.roll_clips.context_at(math.floor(pitch + 0.5), beat + paw.roll_clips.offset(clip))
  if behind then paw.roll_clips.toggle(behind.clip) end
end

--- The clips list of the roll's side panel: make one active, edit it too
--- (or no longer), show a track's notes behind the roll's or not.
function A.roll_activate(_, id) paw.roll_clips.activate(math.floor(id)) end
function A.roll_toggle_clip(_, id) paw.roll_clips.toggle(math.floor(id)) end
function A.roll_show_track(_, id)
  id = math.floor(id)
  for _, t in ipairs(paw.roll_clips.tracks()) do
    if t.id == id then return paw.roll_clips.show_track(id, not t.on) end
  end
end

--- Choose notes with a click: `mode` is "only" (the note alone), "add" or
--- "toggle" (Shift or Ctrl held).
function A.select_note(clip, index, mode)
  if mode == "only" or mode == nil then return choose(clip, { index }) end
  local map = chosen_map(clip)
  local set = {}
  for _, place in ipairs(map[clip] or {}) do set[place] = true end
  if mode == "toggle" and set[index] then set[index] = nil else set[index] = true end
  local out = {}
  for place in pairs(set) do out[#out + 1] = place end
  map[clip] = out
  choose_all(map)
end

--- Choose the notes a box touches: from `beat0, pitch0` to `beat1, pitch1`,
--- in any order, in every clip the roll edits. `mode` as for `select_note`.
function A.select_notes_box(clip, beat0, pitch0, beat1, pitch1, mode)
  if beat0 > beat1 then beat0, beat1 = beat1, beat0 end
  if pitch0 > pitch1 then pitch0, pitch1 = pitch1, pitch0 end
  local map = (mode == "add" or mode == "toggle") and chosen_map(clip) or {}
  local count = 0
  for _, part in ipairs(parts_for(clip)) do
    local set = {}
    for _, place in ipairs(map[part.id] or {}) do set[place] = true end
    for place, n in ipairs(part.clip:notes()) do
      local start = n.start + part.offset
      if n.start >= 0 and n.pitch >= pitch0 and n.pitch <= pitch1 and start < beat1 and start + n.length > beat0 then
        if mode == "toggle" and set[place] then set[place] = nil else set[place] = true end
      end
    end
    local out = {}
    for place in pairs(set) do out[#out + 1] = place end
    map[part.id], count = out, count + #out
  end
  choose_all(map)
  return count
end

function A.select_all_notes(clip)
  local map = {}
  for _, part in ipairs(parts_for(clip)) do
    local out = {}
    for place, n in ipairs(part.clip:notes()) do
      -- Not those hidden by a trim of the clip's edges.
      if n.start >= 0 and n.start < part.length then out[#out + 1] = place end
    end
    map[part.id] = out
  end
  choose_all(map)
end

function A.clear_note_selection()
  if next(chosen) then choose_all({}) end
end

--- The notes a gesture on the note at `index` acts on: all the chosen ones
--- if it is one of them, else that note alone, which is then the chosen
--- one. Clip id -> places.
local function grabbed(clip, index)
  local map = chosen_map(clip)
  for _, place in ipairs(map[clip] or {}) do
    if place == index then return map end
  end
  choose(clip, { index })
  return { [clip] = { index } }
end

--- The parts a map of chosen notes is in, each with its notes and places.
local function grabbed_parts(clip, map)
  local out = {}
  for _, part in ipairs(parts_for(clip)) do
    if map[part.id] then
      part.notes, part.places = part.clip:notes(), map[part.id]
      out[#out + 1] = part
    end
  end
  return out
end

--- Drag notes: the one at `index` and, if it is chosen, the others chosen
--- with it, by `dbeat` and `dpitch`. The grabbed note lands on the grid
--- unless `free`; the rest keep their distance from it. With `copy` the
--- notes stay and copies are dropped. Each note stays in its own clip.
function A.drag_notes(clip, index, dbeat, dpitch, copy, free)
  local held = paw.clip(clip):notes()[index]
  if not held then return end
  local parts = grabbed_parts(clip, grabbed(clip, index))
  local by = snap_note(held.start + dbeat, free) - held.start
  dpitch = math.floor((dpitch or 0) + 0.5)
  -- Nothing leaves its clip or the keyboard.
  for _, part in ipairs(parts) do
    for _, place in ipairs(part.places) do
      local n = part.notes[place]
      by = math.max(by, -n.start)
      by = math.min(by, part.length - n.start - math.min(n.length, paw.opt.note_grid))
      dpitch = paw.util.clamp(dpitch, -n.pitch, 127 - n.pitch)
    end
  end
  if math.abs(by) < 1e-9 and dpitch == 0 and not copy then return end
  local after = {}
  for _, part in ipairs(parts) do
    local wanted, set, add = {}, {}, {}
    for _, place in ipairs(part.places) do
      local n = part.notes[place]
      local moved = { start = n.start + by, pitch = n.pitch + dpitch }
      wanted[#wanted + 1] = moved
      if copy then
        add[#add + 1] = paw.util.merge(n, moved)
      else
        set[#set + 1] = { index = place, start = moved.start, pitch = moved.pitch }
      end
    end
    part.clip:edit_notes({ set = set, add = add })
    after[part.id] = wanted
  end
  if dpitch ~= 0 then paw.clip(clip):track():play_note(held.pitch + dpitch, held.velocity, 120) end
  local map = {}
  for id, wanted in pairs(after) do map[id] = places_of(id, wanted) end
  choose_all(map)
end

--- Drag an end of the note at `index`, and the same end of the notes chosen
--- with it: `dstart` moves their starts (the ends stay), `dlength` their ends.
function A.stretch_notes(clip, index, dstart, dlength, free)
  local held = paw.clip(clip):notes()[index]
  if not held then return end
  local parts = grabbed_parts(clip, grabbed(clip, index))
  local least = (free or not paw.opt.note_snap) and 1 / 64 or paw.opt.note_grid
  -- The grabbed note's end lands on the grid; the others change by as much.
  if dstart and dstart ~= 0 then
    dstart = snap_note(held.start + dstart, free) - held.start
  else
    dstart = 0
  end
  if dlength and dlength ~= 0 then
    dlength = snap_note(held.start + held.length + dlength, free) - (held.start + held.length)
  else
    dlength = 0
  end
  local map = {}
  for _, part in ipairs(parts) do
    local wanted, set = {}, {}
    for _, place in ipairs(part.places) do
      local n = part.notes[place]
      local stop = n.start + n.length
      local start = paw.util.clamp(n.start + dstart, 0, stop - least)
      local length = math.max(least, math.min(stop + dlength, part.length) - start)
      wanted[#wanted + 1] = { start = start, pitch = n.pitch }
      set[#set + 1] = { index = place, start = start, length = length }
    end
    part.clip:edit_notes({ set = set })
    map[part.id] = places_of(part.id, wanted)
  end
  choose_all(map)
  return dlength ~= 0 or dstart ~= 0
end

--- Take a note away, and with it the others if it is one of the chosen.
function A.remove_note(clip, index)
  for _, part in ipairs(grabbed_parts(clip, grabbed(clip, index))) do
    part.clip:edit_notes({ remove = part.places })
  end
  choose_all({})
end

--- Take the chosen notes away: what Delete does in the piano roll.
function A.remove_chosen_notes(clip)
  local map, count = chosen_map(clip)
  if count == 0 then return false end
  for _, part in ipairs(grabbed_parts(clip, map)) do
    part.clip:edit_notes({ remove = part.places })
  end
  choose_all({})
  return true
end

-- One note at a time, as scripts and older frontends ask for it.
function A.move_note(clip, index, start, pitch)
  pitch = paw.util.clamp(pitch, 0, 127)
  local c = paw.clip(clip)
  local before = c:notes()[index]
  local at = c:set_note(index, { start = note_snap(start), pitch = pitch })
  if before and before.pitch ~= pitch then c:track():play_note(pitch, before.velocity, 120) end
  return at
end

function A.resize_note(clip, index, length)
  paw.clip(clip):set_note(index, { length = math.max(paw.opt.note_grid, note_snap(length)) })
end

--- How hard a note is played; with the note among the chosen, all of them.
function A.set_velocity(clip, index, velocity)
  velocity = paw.util.clamp(math.floor(velocity + 0.5), 1, 127)
  local map = chosen_map(clip)
  local among = false
  for _, place in ipairs(map[clip] or {}) do among = among or place == index end
  if not among then return paw.clip(clip):set_note(index, { velocity = velocity }) end
  for _, part in ipairs(grabbed_parts(clip, map)) do
    local set = {}
    for i, place in ipairs(part.places) do set[i] = { index = place, velocity = velocity } end
    part.clip:edit_notes({ set = set })
  end
  choose_all(map)
end

--- Hear a pitch on the track of the clip that is open: a click on the keyboard.
function A.audition(clip, pitch)
  paw.clip(clip):track():play_note(paw.util.clamp(pitch, 0, 127), paw.opt.velocity, 250)
end

--- A drag with Alt held: take away every note the pointer crossed. `points`
--- are `{ beat, pitch }` as the pointer went; between two of them the path
--- is a straight line, so a quick stroke misses nothing it passed over.
function A.erase_notes(clip, points)
  local function crosses(n, b0, p0, b1, p1)
    -- Walk the segment in steps finer than a note's height and a 64th.
    local steps = math.max(1, math.ceil(math.max(math.abs(p1 - p0) * 4, math.abs(b1 - b0) * 64)))
    for s = 0, steps do
      local t = s / steps
      local beat, pitch = b0 + (b1 - b0) * t, p0 + (p1 - p0) * t
      if not n.hidden and math.floor(pitch + 0.5) == n.pitch and beat >= n.start and beat < n.start + n.length then return true end
    end
    return false
  end
  local count = 0
  for _, part in ipairs(parts_for(clip)) do
    local hit = {}
    for place, n in ipairs(part.clip:notes()) do
      -- Notes hidden by a trim of the clip's start are not there to cross.
      local seen = paw.util.merge(n, { start = n.start + part.offset, hidden = n.start < 0 })
      for i = 1, #points do
        local a, b = points[i], points[math.min(i + 1, #points)]
        if crosses(seen, a[1], a[2], b[1], b[2]) then
          hit[#hit + 1] = place
          break
        end
      end
    end
    if #hit > 0 then part.clip:edit_notes({ remove = hit }) end
    count = count + #hit
  end
  if count > 0 then choose_all({}) end
  return count
end

--- A drag with the right button down the keyboard: choose every note from
--- `low` to `high` (either way round). `mode` as for `select_note`.
function A.select_pitches(clip, low, high, mode)
  local from, to = 0, paw.clip(clip).length
  for _, part in ipairs(parts_for(clip)) do
    from, to = math.min(from, part.offset), math.max(to, part.offset + part.length)
  end
  return A.select_notes_box(clip, from - 1, low, to + 1, high, mode)
end

--- Draw over the velocity strip: `points` are `{ beat, fraction }` as the
--- pointer went (fraction 0 at the bottom, 1 at the top). Each note starting
--- within the stretch drawn over, or within `reach` beats of a click, takes
--- the height drawn above its start; with notes chosen, only those.
function A.draw_velocities(clip, points, reach)
  if #points == 0 then return 0 end
  table.sort(points, function(a, b) return a[1] < b[1] end)
  reach = reach or 0
  local from, to = points[1][1] - reach, points[#points][1] + reach
  local function height(beat)
    if beat <= points[1][1] then return points[1][2] end
    for i = 2, #points do
      local a, b = points[i - 1], points[i]
      if beat <= b[1] then
        return b[1] > a[1] and a[2] + (b[2] - a[2]) * (beat - a[1]) / (b[1] - a[1]) or b[2]
      end
    end
    return points[#points][2]
  end
  local map, chosen_count = chosen_map(clip)
  local count = 0
  for _, part in ipairs(parts_for(clip)) do
    local only = {}
    for _, place in ipairs(map[part.id] or {}) do only[place] = true end
    local set = {}
    for place, n in ipairs(part.clip:notes()) do
      local start = n.start + part.offset
      if (chosen_count == 0 or only[place]) and n.start >= 0 and start >= from - 1e-9 and start <= to + 1e-9 then
        set[#set + 1] = { index = place, velocity = paw.util.clamp(math.floor(height(start) * 127 + 0.5), 1, 127) }
      end
    end
    if #set > 0 then part.clip:edit_notes({ set = set }) end
    count = count + #set
  end
  if count > 0 and chosen_count > 0 then choose_all(map) end
  return count
end

--- The length a click on the grid gives a note, and that insert mode and
--- step input enter: the piano roll's note length. 0 or nil for one grid step.
function A.set_note_length(length)
  paw.ui.views.pianoroll:set_step(length and length > 0 and length or nil)
end

--- The snap button: whether the pointer's notes land on the grid.
function A.toggle_note_snap()
  paw.opt.note_snap = not paw.opt.note_snap
end

--- Quantize: the chosen notes of `clip` (and of the clips edited with it),
--- or all of them with none chosen, start on the nearest step of the piano
--- roll's grid, keeping their lengths (a note that would leave its clip
--- stops at its end). `strength` from 0 to 1 moves them that part of the
--- way (1 without).
function A.quantize_notes(clip, strength)
  strength = paw.util.clamp(strength or 1, 0, 1)
  local map, chosen_count = chosen_map(clip)
  local kept = chosen_count > 0
  local count, after = 0, {}
  for _, part in ipairs(parts_for(clip)) do
    local notes = part.clip:notes()
    local places = map[part.id] or {}
    if not kept then
      for place in ipairs(notes) do places[place] = place end
    end
    local set, wanted = {}, {}
    for _, place in ipairs(places) do
      local n = notes[place]
      local start = math.max(0, math.min(n.start + (note_snap(n.start) - n.start) * strength, part.length - paw.opt.note_grid))
      set[#set + 1] = { index = place, start = start, length = math.min(n.length, part.length - start) }
      wanted[#wanted + 1] = { start = start, pitch = n.pitch }
    end
    if #set > 0 then
      part.clip:edit_notes({ set = set })
      after[part.id] = wanted
    end
    count = count + #set
  end
  if count == 0 then return 0 end
  if kept then
    local out = {}
    for id, wanted in pairs(after) do out[id] = places_of(id, wanted) end
    choose_all(out)
  end
  return count
end

-- Step input: with it on, the piano roll open and the transport stopped,
-- each note a MIDI keyboard plays is entered at the roll's cursor with the
-- roll's note length. Notes held together make a chord; the cursor steps
-- on when the last of them is let go.
local stepping = { on = false, held = {}, entered = false }

--- True if step input (notes from a MIDI keyboard) is on.
function M.step_input() return stepping.on end

function A.toggle_step_input()
  stepping.on, stepping.held, stepping.entered = not stepping.on, {}, false
  paw.notify(stepping.on and "step input: play notes on a MIDI keyboard to enter them at the cursor" or "step input off")
  api.ui_redraw()
end

paw.on("midi.in", function(event)
  if not stepping.on or not paw.ui.visible("pianoroll") or api.transport_get().playing then return end
  local roll = paw.ui.views.pianoroll
  local clip = roll:clip()
  if not clip or not event.pitch then return end
  if event.type == "note_on" and (event.velocity or 0) > 0 then
    local length = roll:step_length()
    if roll.beat + length > clip.length + 1e-9 then
      clip.length = paw.time.bar_ceil(clip.start + roll.beat + length - 1e-9) - clip.start
    end
    clip:edit_notes({
      remove = roll:starting_here(clip, event.pitch),
      add = { { pitch = event.pitch, start = roll.beat, length = length, velocity = event.velocity } },
    })
    roll.pitch = event.pitch
    stepping.held[event.pitch], stepping.entered = true, true
    api.ui_redraw()
  elseif event.type == "note_off" or event.type == "note_on" then
    stepping.held[event.pitch] = nil
    if stepping.entered and next(stepping.held) == nil then
      stepping.entered = false
      roll:step(1)
    end
  end
end)

--- A click on the piano roll's ruler: the playhead to that beat of the clip.
function A.roll_seek(clip, beat)
  api.transport_seek(math.max(0, paw.clip(clip).start + math.max(0, beat)))
end

-- Automation. A lane is drawn over a stretch of its range (`lane_span`),
-- and a frontend names a height in it as a fraction, 0 at the bottom.

local function lane_value(lane, fraction)
  local lo, hi = M.lane_span(api.lane_get(lane))
  return lo + paw.util.clamp(fraction, 0, 1) * (hi - lo)
end

--- The lane of a track for "volume", "pan", or a parameter (by key) of one
--- of its devices: the one there is, or a new one.
function A.lane(track, target, device, param)
  for _, lane in ipairs(api.lane_list(track)) do
    if lane.target == target and (target ~= "param" or (lane.device == device and lane.param == param)) then
      return lane.id
    end
  end
  return api.lane_add(track, { target = target, device = device, param = param })
end

function A.add_point(lane, beat, fraction)
  api.lane_add_point(lane, snap(beat), lane_value(lane, fraction))
end

function A.move_point(lane, index, beat, fraction)
  local points = api.lane_points(lane)
  table.remove(points, index)
  points[#points + 1] = { snap(beat), lane_value(lane, fraction) }
  api.lane_set_points(lane, points)
end

--- Draw over a lane with a pencil: `points` are `{ beat, fraction }` as
--- they were drawn. They replace what the lane held over the stretch drawn
--- across, at most one to a quarter of a grid step.
function A.draw_lane(lane, points)
  if #points == 0 then return end
  table.sort(points, function(a, b) return a[1] < b[1] end)
  local step = paw.opt.grid / 4
  local from, to = math.max(0, points[1][1]), math.max(0, points[#points][1])
  local out = {}
  for _, p in ipairs(api.lane_points(lane)) do
    if p[1] < from - 1e-9 or p[1] > to + 1e-9 then out[#out + 1] = p end
  end
  local last
  for i, p in ipairs(points) do
    local beat = math.max(0, p[1])
    if not last or beat - last >= step - 1e-9 or i == #points then
      out[#out + 1] = { beat, lane_value(lane, p[2]) }
      last = beat
    end
  end
  api.lane_set_points(lane, out)
end

function A.toggle_lane(lane)
  api.lane_set(lane, "enabled", not api.lane_get(lane).enabled)
end

function A.clear_lane(lane)
  api.lane_set_points(lane, {})
end

-- Controller moves in a MIDI clip: the pitch wheel, pressure, or a control
-- change by number. Heights are fractions, 0 at the bottom; the wheel rests
-- in the middle.

local function control_value(kind, fraction)
  fraction = paw.util.clamp(fraction, 0, 1)
  return kind == "bend" and fraction * 2 - 1 or fraction
end

--- Draw controller moves with a pencil: `points` are `{ beat, fraction }`
--- in the clip. They replace the moves of that kind over the stretch drawn
--- across, one to a note-grid step.
function A.draw_controls(clip, kind, number, points)
  if #points == 0 then return end
  table.sort(points, function(a, b) return a[1] < b[1] end)
  local c = paw.clip(clip)
  local grid = paw.opt.note_grid
  local from, to = note_snap(points[1][1]), note_snap(points[#points][1])
  local same = function(control)
    return control.type == kind and control.key == nil and (kind ~= "cc" or control.number == number)
  end
  local out = {}
  for _, control in ipairs(c:controls()) do
    if not (same(control) and control.start >= from - 1e-9 and control.start <= to + 1e-9) then out[#out + 1] = control end
  end
  -- Each step takes the height drawn nearest to it.
  local steps, nearest = {}, {}
  for _, p in ipairs(points) do
    local at = note_snap(p[1])
    local off = math.abs(p[1] - at)
    if not nearest[at] or off < nearest[at] then steps[at], nearest[at] = p[2], off end
  end
  for beat = from, to + 1e-9, grid do
    local fraction = steps[note_snap(beat)]
    if fraction and beat < c.length then
      out[#out + 1] = { start = note_snap(beat), type = kind, number = kind == "cc" and number or nil, value = control_value(kind, fraction) }
    end
  end
  c:set_controls(out)
end

--- Remove the moves of one kind from a clip.
function A.clear_controls(clip, kind, number)
  local c = paw.clip(clip)
  local out = {}
  for _, control in ipairs(c:controls()) do
    if not (control.type == kind and control.key == nil and (kind ~= "cc" or control.number == number)) then out[#out + 1] = control end
  end
  c:set_controls(out)
end

-- Moves of the strip chosen, moved and taken away, drawn as a line, and
-- the event list: `paw.controls` says what each does.
-- A window names a mode by number: 0 alone, 1 add, 2 toggle.
local modes = { [0] = "only", [1] = "add", [2] = "toggle" }
function A.select_control(clip, place, mode) paw.controls.select(clip, place, modes[mode] or mode) end
function A.select_controls(clip, kind, number, beat0, low, beat1, high, mode)
  return paw.controls.select_box(clip, kind, number, beat0, low, beat1, high, modes[mode] or mode)
end
function A.select_all_controls(clip, kind, number)
  return paw.controls.select_box(clip, kind, number, -1, 0, paw.clip(clip).length + 1, 1)
end
function A.clear_control_selection(clip) paw.controls.clear(clip) end
function A.move_controls(clip, dbeat, dfraction, free)
  return paw.controls.move(clip, dbeat, dfraction, free == true or free == 1)
end
function A.remove_chosen_controls(clip) return paw.controls.remove(clip) end
function A.line_controls(clip, kind, number, beat0, f0, beat1, f1, free)
  return paw.controls.line(clip, kind, number, beat0, f0, beat1, f1, free == true or free == 1)
end

--- The event list of the clip in the piano roll, in a window of its own.
function A.open_event_list(clip)
  paw.canvas.open_view("eventlist", { title = "Events · " .. paw.clip(clip).name, width = 520, height = 440 })
end

function A.remove_point(lane, index)
  local points = api.lane_points(lane)
  table.remove(points, index)
  api.lane_set_points(lane, points)
end

-- Devices.

local function param_of(device, key)
  for _, p in ipairs(api.device_get(device).param_info) do
    if p.key == key then return p end
  end
  error("the device has no parameter `" .. tostring(key) .. "`", 3)
end

--- Set a parameter from a slider's position, 0 to 1 across its range.
function A.set_param(device, key, fraction)
  local p = param_of(device, key)
  api.device_set_param(device, key, paw.params.from_fraction(p, fraction))
end

--- Back to where the device starts out: a double click on a slider.
function A.reset_param(device, key)
  api.device_set_param(device, key, param_of(device, key).default)
end

function A.toggle_bypass(device)
  api.device_set(device, "bypass", not api.device_get(device).bypass)
end

function A.add_device(kind, query)
  return paw.fx.add(assert(paw.cursor.track(), "no track selected"), kind, { query = query }).id
end

--- Move a device one place earlier (-1) or later (1) in its track's chain.
function A.move_device(device, by)
  local d = api.device_get(device)
  api.device_move(device, d.track, paw.util.clamp(d.index + by, 1, #api.track_get(d.track).devices))
end

return M
