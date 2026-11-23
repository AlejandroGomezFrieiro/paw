-- The state that a graphical frontend polls (`paw.frontend.state`), and
-- what it fetches beside it: the pictures inside clips, the waveforms, the
-- extensions' menus and bands, and the floating window as text.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local seats = require("paw.seats")
local util = require("paw.util")
local type types = require("paw.types")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")

local paw = host.paw
local opt = options.opt

-- Values as text in their unit, and sliders on a log scale for frequencies
-- and times: see `paw.params`.
--- A parameter's value as text in its unit (see `paw.params.format`).
function M.format_value(param: types.ParamInfo, value: number): string
  return paw.params.format(param, value)
end
local format_value = M.format_value
local track_text = host.track_text
local type BandEntry = M.BandEntry
local type BandState = M.BandState
local type Bands = M.Bands
local type Cmdline = host.Cmdline
local type Completions = M.Completions
local type DeviceState = M.DeviceState
local type FloatText = M.FloatText
local type Menu = host.Menu
local type MenuLabel = M.MenuLabel
local type MixerRows = host.MixerRows
local type Modal = M.Modal
local type ParamState = M.ParamState
local type ProjectState = M.ProjectState
local type Prompt = host.Prompt
local type PromptState = M.PromptState
local type Rect = host.Rect
local type Send = M.Send
local type State = M.State
local type TakeRow = M.TakeRow
local type TrackState = M.TrackState

local function device_state(id: integer): DeviceState
  local d = api.device_get(id)
  local params: {ParamState} = {}
  -- The device's own parameters, those the user chose to show first (see
  -- `paw.fx.card_params`); the host's wet/dry mix and gain are on the header.
  local own = paw.fx.card_params(d)
  for i = 1, math.min(M.max_params, #own) do
    local p = own[i]
    local value = d.params[p.key]
    params[i] = {
      key = p.key,
      name = p.name,
      text = format_value(p, value),
      -- Sliders work on 0..1 whatever the parameter's own range is.
      value = paw.params.fraction(p, value),
      min = p.min,
      max = p.max,
      -- Where the slider rests, for a double click.
      default = paw.params.fraction(p, p.default),
    }
  end
  local meta = d.meta as {string: string}
  return {
    id = d.id,
    name = d.name,
    format = d.format,
    bypass = d.bypass,
    params = params,
    more = #own - #params,
    -- The wet share, 0 to 1, and the output gain in dB.
    wet = (d.params.fx_wet or 100) / 100,
    gain = d.params.fx_gain or 0,
    -- "open", "closed", or "" for a device with no window of its own.
    editor = d.editor or "",
    -- Why a plugin has stopped working, or "".
    stopped = d.stopped or (d.missing and "it is not installed or did not load") or "",
    -- The preset last loaded or saved, or "".
    preset = type(d.meta) == "table" and meta.preset or "",
    -- "running", "loading", "stopped", "offline" or "missing".
    status = d.status or "running",
    -- Whether it can listen to a side-chain, and the track it listens to
    -- ("" for its own input); `sidechain_menu` lists the choices.
    keyed = (d.ports and d.ports.sidechain) or d.sidechain ~= nil,
    sidechain = paw.routes.sidechain_text(d) or "",
    -- How many output pairs it has (1 for most), and how many of the
    -- further ones play somewhere; `outputs_menu` routes them.
    pairs = math.max(1, #(d.ports and d.ports.outputs or {})) as integer,
    routed = (
      function(): integer
        local n = 0
        for _ in pairs(d.outputs or {}) do
          n = n + 1
        end
        return n
      end
    )(),
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
M.menus = {clip = {}, track = {}, timeline = {}}

local function menus(): {string: {MenuLabel}}
  local out: {string: {MenuLabel}} = {}
  for kind, entries in pairs(M.menus) do
    local list: {MenuLabel} = {}
    for i, entry in ipairs(entries) do
      list[i] = {label = entry.label, only = entry.only or ""}
    end
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

local function band_entries(index: integer): {BandEntry}
  local fn = M.bands[index]
  local ok, entries = pcall(fn)
  if not ok then
    paw.notify("a band of the window's ruler failed: " .. tostring(entries), "error")
    return {}
  end
  return type(entries) == "table" and entries as {BandEntry} or {}
end

--- The bands that have entries, as rows from 0 below the marker band:
--- `{ rows, entries }`. Each entry has its `row`, its `band` and `index`
--- (for `act.band`), `beat`, `length`, `name`, `color`, `active` and `hint`.
function M.band_state(): Bands
  local out: {BandState} = {}
  local rows = 0
  for i in ipairs(M.bands) do
    local entries = band_entries(i)
    if #entries > 0 then
      for j, e in ipairs(entries) do
        out[#out + 1] = {
          row = rows,
          band = i,
          index = j,
          beat = tonumber(e.beat) or 0,
          length = tonumber(e.length) or 0,
          name = tostring(e.name or ""),
          color = e.color or "",
          active = e.command ~= nil or e.run ~= nil,
          hint = tostring(e.hint or e.name or ""),
        }
      end
      rows = rows + 1
    end
  end
  return {rows = rows, entries = out}
end

--- The candidates of a prompt, as the terminal shows them above the line.
--- These are the candidates in view around the selected one, as
--- `{ label, desc }`. `chosen` is the place of the selected candidate among
--- them (0 for none).
function M.completions(prompt: Prompt): Completions
  local all = prompt.matches
  if not all or #all == 0 then
    return nil
  end
  local rows = 10
  local first = math.max(1, math.min((prompt.match or 0) - rows + 1, #all - rows + 1))
  local list: Completions = {
    total = #all, chosen = (prompt.match or 0) > 0 and prompt.match - first + 1 or 0, items = {}
  }
  for i = first, math.min(#all, first + rows - 1) do
    local c = all[i]
    list.items[#list.items + 1] = {
      label = c.label, desc = c.desc and (c.desc:match("^[^\n]*"):gsub(":? `.*$", "")) or ""
    }
  end
  return list
end

--- A track's sends as `{ name, level }`, the level in dB.
function M.send_list(track: types.Track): {Send}
  local out: {Send} = {}
  for i, send in ipairs(track.sends or {}) do
    local ok, to = pcall(api.track_get, send.target)
    out[i] = {name = ok and (to as types.Track).name or "?", level = send.level}
  end
  return out
end

local mode_names: {string: string} = {n = "NORMAL", c = "COMMAND", i = "INSERT", o = "PENDING"}
local visual_names: {string: string} = {v = "VISUAL", V = "V-LINE", b = "V-BLOCK", clips = "CLIPS"}

--- Where the keyboard is: the mode, what is half typed, the prompt or the
--- message, the selection, and the cursors of the panels. Small, and sent
--- every time, because a key press changes it without changing the project.
local function modal(): Modal
  local keymap, ui = paw.keymap, paw.ui
  local hint, pointer = paw.mouse.hint_text()
  local _, menu_count = ((require as function(string): Menu)("paw.menu")).shown()
  local out: Modal = {
    mode = keymap.mode,
    pending = keymap.pending(),
    recording = keymap.recording() or "",
    name = keymap.mode == "x" and keymap.visual and visual_names[keymap.visual.kind]
      or mode_names[keymap.mode]
      or keymap.mode:upper(),
    focused = ui.focused,
    mixer = ui.visible("mixer"),
    float = ui.float and (ui.float.title or ui.float.name) or nil,
    -- A menu the kernel opened (a right click in a pane drawn from its
    -- scene), by how many were: the window shows it (`paw.frontend.menu("shown")`).
    menu = menu_count,
    -- What the pointer is over in a pane drawn from its scene, or what its
    -- drag will do (`paw.mouse.hint`), for the status line.
    hint = hint,
    -- The shape of the pointer there, if it has one ("resize_h", "resize_v").
    pointer = pointer,
    selection = keymap.selection(),
    -- A render in the background: { path, fraction, seconds, cancelling, stage }.
    render = api.render_status(),
    -- What `:learn` is waiting to bind a controller to, in words.
    learning = paw.learn and paw.learn.learning and paw.learn.target_name(paw.learn.learning) or nil,
  }
  -- Chosen clips are told one by one, with the clips (`selected`).
  if out.selection then
    out.selection.clips = nil
  end
  local prompt = ((require as function(string): Cmdline)("paw.views.cmdline")).state()
  if prompt then
    local shown = prompt as PromptState
    shown.matches = M.completions(prompt)
    out.prompt = shown
  elseif ui.message then
    out.message = {text = ui.message.text:match("^[^\n]*"), level = ui.message.level, time = ui.message.time}
  elseif opt.keybar and keymap.pending() == "" then
    -- With nothing to say, the keys worth knowing here, as the terminal's
    -- bottom line shows them.
    out.keys = {}
    for i, entry in ipairs(ui.keybar.entries()) do
      out.keys[i] = {key = entry[1], desc = entry[2]}
    end
    local topic = paw.help and paw.help.topic_of(ui.focused)
    if topic then
      out.keys[#out.keys + 1] = {key = ":help " .. topic, desc = "the manual"}
    end
  end
  -- What an Ex line being typed would act on: the stretch of time, the
  -- tracks, and the clips that match with how many matches each holds.
  local shown = paw.ex and paw.ex.shown()
  if shown then
    out.ex = {
      from = shown.from,
      to = shown.to,
      tracks = {},
      clips = {},
      current = shown.current and shown.current.clip and shown.current.clip.id,
    }
    for id in pairs(shown.tracks or {}) do
      out.ex.tracks[#out.ex.tracks + 1] = id
    end
    for id, n in pairs(shown.clips or {}) do
      out.ex.clips[#out.ex.clips + 1] = {id = id, count = n, notes = shown.notes[id] ~= nil}
    end
  end
  -- The row of a strip the keyboard is on in the mixer.
  if out.mixer and ui.focused == "mixer" then
    local row, id = ((require as function(string): MixerRows)("paw.mixer_rows")).current()
    if row then
      out.mixer_row = {track = id, kind = row.kind, index = row.index or 0, field = row.field or ""}
    end
  end
  -- The status line when it was set up (`paw.statusline.setup`): the
  -- pieces of each side as `{ text, style }`, for a window that draws it.
  if paw.statusline.customized() then
    out.statusline = paw.statusline.frontend()
  end
  local qf = paw.qf and paw.qf.status()
  if qf then
    local text: {string} = {}
    local worst = 0
    for _, piece in ipairs(qf) do
      text[#text + 1] = piece[1] as string
      worst = math.max(worst, piece[2] == "StatusError" and 2 or piece[2] == "StatusWarn" and 1 or 0)
    end
    out.qf = {text = table.concat(text), level = worst}
  end
  if opt.hints then
    local hints, title = keymap.hints()
    if hints then
      out.hints = {title = title, items = hints}
    end
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
    panel.row = util.clamp(panel.row, 1, math.max(1, #rows)) as integer
    local row = rows[panel.row]
    if row then
      out.device, out.param = row.device.index, 0
      for i, p in ipairs(row.device.param_info) do
        if row.param and p.key == row.param.key then
          out.param = i
        end
      end
    end
  end
  return out
end

--- The float that is open (help, a list, a picker), drawn as text `width`
--- columns wide: its title and its lines. Nil when there is none.
function M.float(width: integer, height: integer): FloatText
  if not paw.ui.float then
    return nil
  end
  local lines = api.ui_snapshot(width, height)
  local rect: Rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == paw.ui.float.name then
      rect = r
    end
  end
  if not rect then
    return nil
  end
  local out: {string} = {}
  for y = rect.y, rect.y + rect.h - 1 do
    local cells: {string} = {}
    for ch in (lines[y + 1] or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      cells[#cells + 1] = ch
    end
    out[#out + 1] = table.concat(cells, "", rect.x + 1, math.min(#cells, rect.x + rect.w))
  end
  return {title = paw.ui.float.title or paw.ui.float.name, lines = out}
end

--- The stretch of a lane's range that the drawing covers: a fader's
--- travel for volume, the whole range for anything else.
function M.lane_span(lane: types.Lane): number, number
  if lane.target == "volume" then
    return -60, 6
  end
  return lane.min, lane.max
end

--- What a lane moves, in words: `Volume`, `Pan`, `Synth · cutoff`.
function M.lane_name(lane: types.Lane): string
  if lane.target == "volume" then
    return "Volume"
  end
  if lane.target == "pan" then
    return "Pan"
  end
  local ok, got = pcall(api.device_get, lane.device)
  if not ok then
    return tostring(lane.param)
  end
  local device = got as types.Device
  for _, p in ipairs(device.param_info) do
    if p.key == lane.param then
      return device.name .. " · " .. p.name
    end
  end
  return device.name .. " · " .. tostring(lane.param)
end

--- The takes of a clip as its take lanes show them: `{ name, key }` each.
--- `key` changes exactly when the sound of the take changes. Nil for a clip
--- without takes, which has nothing in the lanes.
function M.take_rows(clip: types.Clip): {TakeRow}
  local takes = paw.takes.of(clip)
  if not takes then
    return nil
  end
  local out: {TakeRow} = {}
  local seconds = clip.kind == "audio" and paw.stretch.file_seconds(clip, clip.length) or 0
  for i, entry in ipairs(takes.list) do
    local key: string
    if clip.kind == "audio" then
      local c = paw.takes.content(clip, i)
      key = string.format(
        "%s|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%s|%s|%.17g|%.17g",
        c.file,
        c.offset,
        c.gain,
        clip.length,
        seconds,
        clip.stretch,
        clip.pitch,
        tostring(clip.stretching),
        tostring(clip.loop),
        clip.loop_start,
        clip.loop_length or 0
      )
    else
      key = string.format(
        "%s|%d|%d|%d|%.17g|%s|%.17g|%.17g",
        tostring(clip.stamp),
        takes.active,
        i,
        #(entry.notes or {}),
        clip.length,
        tostring(clip.loop),
        clip.loop_start,
        clip.loop_length or 0
      )
    end
    out[i] = {name = entry.name or ("take " .. i), key = key}
  end
  return out
end

--- What take `take` of a clip plays, for the picture in its take lane. For
--- sound, this is a waveform as `M.peaks` gives it, at `points` points. For
--- MIDI, it is the notes as `M.preview` gives them. It repeats as a looped
--- clip repeats. The waveform of the take that plays is the waveform of the
--- clip, stretched. The waveform of a different take is its file, made
--- shorter or longer in time as the clip stretches it.
function M.take_preview(id: integer, take: integer, points?: number): {number}
  local ok, got = pcall(api.clip_get, id)
  if not ok then
    return {}
  end
  local clip = got as types.Clip
  local c = paw.takes.content(clip, take)
  local flat: {number} = {}
  if clip.kind == "audio" then
    local n = util.clamp(math.floor(points or M.peak_points), 8, 4096) as integer
    local takes = paw.takes.of(clip)
    if takes and take == takes.active then
      local fetched, peaks = pcall(api.clip_peaks, id, n)
      for i, p in ipairs(fetched and peaks as {types.Peak} or {}) do
        flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = p[1], p[2], p[3]
      end
      return flat
    end
    local seconds = paw.stretch.file_seconds(clip, clip.length)
    local fetched: boolean
    local peaks: {types.Peak}
    if clip.loop and clip.loop_length then
      -- One repeat's worth, laid along the clip as it repeats.
      local period = paw.stretch.file_seconds(clip, clip.loop_length)
      local lead = clip.loop_start / clip.loop_length * period
      local per = util.clamp(math.ceil(n * period / seconds), 1, 4096) as integer
      local fetched_one, one = pcall(api.media_peaks, c.file, math.max(0, c.offset + lead), period, per)
      fetched = fetched_one
      local repeat_peaks = one as {types.Peak}
      if fetched and #repeat_peaks > 0 then
        peaks = {}
        for i = 1, n do
          local at = (i - 0.5) * seconds / n
          local phase = ((at - lead) % period) / period
          peaks[i] = repeat_peaks[math.min(#repeat_peaks, math.floor(phase * #repeat_peaks) + 1)]
        end
      end
    else
      local fetched_all, all = pcall(api.media_peaks, c.file, c.offset, seconds, n)
      fetched, peaks = fetched_all, all as {types.Peak}
    end
    local gain = 10 ^ ((c.gain or 0) / 20)
    for i, p in ipairs(fetched and peaks or {}) do
      flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = p[1] * gain, p[2] * gain, p[3] * gain
    end
    return flat
  end
  local i = 0
  for _, n in ipairs(paw.stretch.sounding(clip, c.notes, M.preview_notes)) do
    if i >= M.preview_notes then
      break
    end
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
function M.content_key(clip: types.Clip): string
  local repeats = clip.loop and string.format("|%.17g|%.17g", clip.loop_start, clip.loop_length) or ""
  -- Its warp markers change its waveform.
  for _, m in ipairs(clip.warp or {}) do
    repeats = repeats .. string.format("|%.17g:%.17g", m.source, m.target)
  end
  if clip.kind == "nest" then
    -- A block: what its subproject plays there.
    return paw.nest.content_key(clip)
  end
  if clip.kind == "audio" then
    return string.format(
      "%s|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%s%s",
      clip.file,
      clip.offset,
      clip.length,
      clip.gain,
      paw.time.seconds(clip.length, clip.start),
      clip.stretch,
      clip.pitch,
      tostring(clip.stretching),
      repeats
    )
  end
  return clip.stamp and string.format("%.0f|%.0f|%.17g%s", clip.stamp, clip.control_stamp or 0, clip.length, repeats)
    or nil
end

--- A MIDI clip's notes for the small picture inside it: one flat list
--- { start1, length1, pitch1, start2, ... }, at most `M.preview_notes` notes.
--- Fetched when the clip's `stamp` in `state` changes.
function M.preview(id: integer): {number}
  local flat: {number} = {}
  local ok, got = pcall(api.clip_notes, id)
  local notes = got as {types.Note}
  local c: types.Clip = ok and api.clip_get(id) or {length = 0}
  -- A block of a subproject: the notes that the subproject plays there.
  if not ok then
    local found, block = pcall(api.clip_get, id) as (boolean, types.Clip)
    if found and block and block.kind == "nest" then
      ok, c = true, block
      notes = paw.nest.notes(block, M.preview_notes)
    end
  end
  local length = c.length
  -- A looped clip shows its notes over and over, as they sound.
  if ok then
    notes = paw.stretch.sounding(c, notes, M.preview_notes)
  end
  local i = 0
  for _, n in ipairs(ok and notes or {}) do
    if i >= M.preview_notes then
      break
    end
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
function M.vca_words(id: integer): string
  local names: {string} = {}
  local list = paw.vca.is_vca(id) and paw.vca.members(id) or paw.vca.of(id)
  for i, other in ipairs(list) do
    names[i] = track_text(other, "name")
  end
  return table.concat(names, ", ")
end

--- The parts of the state that are kept while nothing changes them.
local record Kept
  key: string
  ids: {integer}
  modal: Modal
end

-- What the state's parts that only a turn with input, an edit or a redraw
-- can change were made for (`still_key`), by seat: the drawn tracks and
-- the modal state. While the song plays and nobody types, they are kept.
local kept: {integer: Kept} = {}

--- What those parts depend on: the project's revision, the redraws, the
--- input that came (`paw.remote.touches`), the seat and the keys typed.
--- A render in the background changes the modal state on its own.
local function still_key(): string
  if api.render_status() then
    return nil
  end
  local keymap = paw.keymap
  return table.concat(
    {M.revision, api.ui_redraws(), paw.remote and paw.remote.touches or 0, seats.current, keymap.mode, keymap.pending()}
      as {string | number},
    ":"
  )
end

--- The data that paw sends to a graphical frontend: transport, tracks,
--- clips, devices and the modal state, as plain data. `known` is a list of
--- the data that the frontend has already.
function M.state(known: integer): State
  M.polled = api.now() -- someone is looking: see `paw.fx.interactive`
  local t, e = api.transport_get(), api.engine_get()
  local key = still_key()
  local seat = seats.current
  local same = key and kept[seat] and kept[seat].key == key and kept[seat]
  -- The tracks that are drawn: those folded away into a group are left out.
  local ids = same and same.ids
  if not ids then
    ids = paw.groups.rows()
    ids[#ids + 1] = 0 -- the master track goes last
  end
  -- Both sides of every track's meter, one after the other.
  local levels: {number} = {}
  for i, id in ipairs(ids) do
    levels[2 * i - 1], levels[2 * i] = api.track_meter(id)
  end
  -- What arrives at each track's audio input, armed or not: 0 without one.
  local inputs: {number} = {}
  local device_levels = paw.audio.levels()
  for i, id in ipairs(ids) do
    inputs[i] = id ~= 0 and paw.audio.level({input = track_text(id, "input")}, device_levels) or 0
  end
  local num, den = paw.tempo.signature_at(t.position)
  local out: State = {
    revision = M.revision,
    playing = t.playing,
    recording = t.take ~= nil,
    position = t.position,
    -- Beats of a count-in still to be counted before the take starts; 0 for none.
    counting = t.counting or 0,
    time = paw.time.format(paw.time.local_beat(t.position)),
    clock = paw.time.clock(paw.time.local_beat(t.position)),
    -- The tempo and signature where the playhead is.
    tempo = math.floor(paw.tempo.at(t.position) * 100 + 0.5) / 100,
    signature = num .. "/" .. den,
    cpu = paw.audio.load(e.cpu),
    levels = levels,
    inputs = inputs,
    modal = same and same.modal or modal(),
    armed = t.recording,
    -- What went wrong while playing (see `:engine.status`).
    xruns = e.xruns,
    late_blocks = e.late_blocks,
    midi_dropped = e.midi_dropped,
    record_dropped = e.record_dropped,
    devices_stopped = e.devices_stopped,
    -- How often the window draws while the song plays (`paw.opt.window_fps`).
    window_fps = opt.window_fps,
    window_cache = opt.window_cache,
  }
  if key and not same then
    kept[seat] = {key = key, ids = ids, modal = out.modal}
  end
  if known == M.revision then
    return out
  end

  local p = api.project_get()
  local project: ProjectState = {
    name = p.name,
    modified = p.modified,
    tempo = out.tempo,
    bar = paw.time.bar(),
    length = p.length,
    signature = out.signature,
    loop_enabled = t.loop_enabled,
    loop_start = t.loop_start,
    loop_end = t.loop_end,
    metronome = t.metronome,
    backend = e.backend,
    sample_rate = e.sample_rate,
    -- Recording only between two points, and the bars counted before a take.
    punch_enabled = t.punch_enabled,
    punch_start = t.punch_start,
    punch_end = t.punch_end,
    count_in = t.count_in,
    pre_roll = t.pre_roll,
    pre_roll_seconds = t.pre_roll_seconds,
    grid = opt.grid,
    note_grid = opt.note_grid,
    threads = e.threads,
    xruns = e.xruns,
    -- The engine in a few words: backend, output device, sample rate.
    engine = paw.audio.summary(),
  }
  out.project = project
  -- Bar and beat lines from the tempo map, well past the end and the last
  -- change, and the tempo and signature changes to flag on the ruler.
  project.marks = paw.tempo.marks(0, math.huge)
  -- The tempo lane under the ruler, when it is shown: the window's map, and
  -- the tempos at the bottom and the top of the row.
  if paw.tempolane.shown() then
    local lo, hi = paw.tempolane.range()
    project.tempo_lane = {lo = lo, hi = hi, points = paw.tempolane.points()}
  end
  -- Markers and regions (`paw.markers`): { id, beat, name, length } each.
  project.markers = {}
  for i, m in ipairs(paw.markers and paw.markers.list() or {}) do
    project.markers[i] = {id = m.id, beat = m.beat, name = paw.markers.label(m), length = m.length or 0}
  end
  -- Extensions' bands under it (`M.bands`).
  project.bands = M.band_state()
  local last = math.max(p.length or 0, t.loop_end or 0)
  for _, mark in ipairs(project.marks) do
    last = math.max(last, mark.beat)
  end
  local stop = paw.time.bar_start(paw.time.bar_of(last) + 17)
  project.lines = {}
  local lines = paw.tempo.lines(0, stop)
  for i, line in ipairs(lines) do
    local next_beat = lines[i + 1] and lines[i + 1].beat
      or line.beat + (line.beat - (lines[i - 1] and lines[i - 1].beat or line.beat - 1))
    project.lines[i] = {
      beat = line.beat,
      bar = line.bar,
      index = line.index,
      next = next_beat,
      label = line.index == 0 and tostring(line.bar) or "",
      place = line.bar .. "." .. (line.index + 1),
    }
  end
  out.selected = paw.cursor.track_id() or -1
  out.cursor = paw.cursor.beat
  out.tracks, out.clips, out.devices = {}, {}, {}
  local chosen_set: {integer: boolean} = {}
  for _, id in ipairs(M.chosen_clips()) do
    chosen_set[id] = true
  end
  for i, id in ipairs(ids) do
    local track = api.track_get(id)
    -- What the track's sound goes through, in a few words.
    local chain: {string} = {}
    for j, device in ipairs(track.devices or {}) do
      chain[j] = api.device_get(device).name
    end
    local to: types.Track
    if track.output then
      local ok, got = pcall(api.track_get, track.output)
      to = ok and got as types.Track or nil
    end
    local row: TrackState = {
      id = id,
      name = track.name,
      volume = track.volume,
      pan = track.pan,
      mute = track.mute,
      solo = track.solo,
      armed = track.armed,
      master = track.master,
      lanes = {},
      input = track.input,
      monitor = track.monitor,
      -- What the track takes in, in words (`UR22mkII · 1/2`), or nil.
      input_label = not track.master and paw.audio.label(track) or nil,
      -- The colour everything of the track's is drawn in, as in the terminal.
      color = paw.draw.track_colour(track, i),
      chain = table.concat(chain, " › "),
      -- Its kind, in a few words ("Vocal track · Kitane"), or nil.
      kind = id ~= 0 and paw.track_kinds.describe(id) or nil,
      output = to and to.name or nil,
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
    out.tracks[i] = row
    for j, lane in ipairs(id ~= 0 and paw.lanes.shown(id) or {}) do
      row.lane_rows[j] = lane.id
    end
    -- Points are in the target's own units; `min` and `max` give its range,
    -- `lo` and `hi` the part of it a frontend draws the lane over, and
    -- `name` says what the lane moves.
    for j, lane in ipairs(api.lane_list(id)) do
      local lo, hi = M.lane_span(lane)
      row.lanes[j] = {
        id = lane.id,
        target = lane.target,
        device = lane.device,
        param = lane.param,
        enabled = lane.enabled,
        min = lane.min,
        max = lane.max,
        points = api.lane_points(lane.id),
        lo = lo,
        hi = hi,
        name = M.lane_name(lane),
      }
    end
    local take_lanes = row.take_rows > 0
    for _, clip in ipairs(api.clip_list(id)) do
      -- Stretched, shifted, looped, or being stretched: in a few characters.
      local mark = paw.stretch.badge(clip)
      local notches = paw.stretch.repeats(clip)
      -- Its warp markers, in beats from its start.
      local warps: {number} = {}
      for j, m in ipairs(clip.warp or {}) do
        warps[j] = m.beat - clip.start
      end
      local content = M.content_key(clip)
      local takes, take = paw.takes.count(clip)
      out.clips[#out.clips + 1] = {
        -- In take lanes: each take's name, and what changes exactly when
        -- its picture does (fetch `M.take_preview` again then).
        take_rows = take_lanes and M.take_rows(clip) or nil,
        id = clip.id,
        track = i - 1,
        start = clip.start,
        length = clip.length,
        name = (clip.offline and "offline · " or "") .. (mark and mark .. " · " or "") .. clip.name,
        midi = clip.kind == "midi",
        muted = clip.muted,
        -- How many takes it has (1 without others), and which plays.
        takes = takes,
        take = take,
        -- Chosen with the pointer (`M.chosen_clips`).
        selected = chosen_set[clip.id] or false,
        -- An audio clip's fades, in beats, and its gain in dB.
        fade_in = clip.fade_in,
        fade_out = clip.fade_out,
        gain = clip.gain,
        -- Its file is missing: silent until relinked. The name says so too.
        offline = clip.offline or nil,
        -- Changes exactly when the clip's notes or controller moves do:
        -- fetch `M.preview` (and the piano roll's clip) again then.
        stamp = clip.kind ~= "audio" and content or nil,
        -- Changes exactly when the clip's waveform does: fetch `M.peaks` again then.
        waveform = clip.kind == "audio" and content or nil,
        -- Whether it loops, and where its repeats begin, in beats from its start.
        loop = clip.loop or nil,
        notches = notches,
        warps = warps,
      }
    end
  end
  if out.selected >= 0 then
    for i, id in ipairs(api.track_get(out.selected).devices) do
      out.devices[i] = device_state(id)
    end
    out.routing = M.routing(out.selected)
  end
  if known < 0 then
    out.kinds = {}
    for i, info in ipairs(api.device_types()) do
      out.kinds[i] = info.kind
    end
  end
  return out
end

--- The waveform of an audio clip at `points` points (`M.peak_points`
--- without), as one flat list { min1, max1, rms1, min2, max2, rms2, ... }.
--- It gives how far the wave goes each way and how loud it is, which is its
--- body. It is not in `state`, which paw sends again each time the cursor
--- moves. So a frontend gets each waveform only one time for each width.
function M.peaks(clip: integer, points?: number): {number}
  local flat: {number} = {}
  local n = util.clamp(math.floor(points or M.peak_points), 8, 4096) as integer
  for i, p in ipairs(api.clip_peaks(clip, n)) do
    flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = p[1], p[2], p[3]
  end
  return flat
end

return {band_entries = band_entries}
