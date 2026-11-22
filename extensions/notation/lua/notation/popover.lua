-- Popovers: a one-line prompt at the caret for what is not a note, as
-- Dorico's popovers are, in the shape of a Vim prompt. `<localleader>` and a
-- letter opens one (in visual mode it is for the selection, and in insert
-- mode after `<C-o>`, which goes back to entering notes after); it has its
-- own history (`<Up>`), completion with what each choice means (`<Tab>`),
-- and while it is typed the page shows what Enter would write, in the
-- accent's ink. Enter writes it as one undo step; Esc leaves no trace.
--
-- Each popover is sugar over an Ex command (`notation.dyn mp<f`), run with
-- the selection's range when there is one (`:'<,'>notation.dyn mp<f`), so
-- `.`, macros, `@:` and `:5,8notation.dyn p` do the same. `<localleader>.` opens
-- the last popover again with what was typed in it.
--
-- The preview is a trial (`paw.audition.try`): the command is run on the
-- project and taken back exactly, as a picker's choice is heard.
local api = paw.api
local view = require("notation")
local D = require("notation.doc")
local W = require("notation.write")
local cmdline = require("paw.views.cmdline")
local keymap = paw.keymap

local P = { specs = {}, order = {} }
view.popover = P

--- Define a popover: `key` (after the local leader; none for one an operator opens), `name`, `command`, `prompt`,
--- `complete(text)`, `on_key(key, text)` for keys of its own, `hint` (the
--- words shown before anything is typed).
function P.define(spec)
  P.specs[spec.name] = spec
  P.order[#P.order + 1] = spec.name
end

-- What a popover is doing: { spec, range, mode }.
local open_now

--- Whether a popover is open.
function P.active() return open_now ~= nil end

--- The open popover's spec, or nil.
function P.current() return open_now and open_now.spec end

--- Run `fn` with what it says kept from the messages: its last words and
--- whether they warn.
local function quietly(fn)
  local said, level
  local notify = paw.notify
  paw.notify = function(text, lvl)
    said, level = tostring(text), lvl
  end
  local ok, err = pcall(fn)
  paw.notify = notify
  if not ok then return tostring(err), "error" end
  return said, (level == "warn" or level == "error") and "error" or nil
end

--- A measure as text, without the token that changes with every edit.
local function content(m)
  local copy = D.copy(m)
  copy.v = nil
  return api.json_encode(copy)
end

--- What the score holds now, to tell what a preview changed.
local function snapshot()
  local clip = view:clip()
  local sc = clip and view.score_of(clip:get())
  local out = { measures = {}, marks = {}, score = sc ~= nil }
  if sc then
    for _, m in ipairs(sc.measures) do
      out.measures[m.id] = content(m)
    end
    for _, mk in ipairs(sc.marks) do
      out.marks[mk.id] = api.json_encode(mk)
    end
  end
  return out
end

--- What a preview changed, as the ghost the page draws: the measures
--- whose music or signs changed, and the marks that are new or changed.
local function changed(before)
  local clip = view:clip()
  local sc = clip and view.score_of(clip:get())
  if not sc then return nil end
  local out = { measures = {}, marks = {} }
  for _, m in ipairs(sc.measures) do
    if not before.score or before.measures[m.id] ~= content(m) then out.measures[m.id] = true end
  end
  for _, mk in ipairs(sc.marks) do
    if before.marks[mk.id] ~= api.json_encode(mk) then out.marks[mk.id] = true end
  end
  return out
end

--- Run `fn` for a popover opened over a region (an operator's): with that
--- region as the selection, as `:'<,'>` runs its command.
local function over(state, fn)
  if state.region then return keymap.with_selection(state.region, fn) end
  return fn()
end

--- The command line a popover's text makes.
local function line_of(state, text) return state.range .. state.spec.command .. " " .. text end

--- Show what the text would do: run it as a trial, kept from the history
--- and the messages, and the measures it changed drawn as a ghost.
local function preview(text)
  paw.audition.revert()
  view.ghost = nil
  local state = open_now
  if not state then return end
  if text == nil then
    -- The prompt is closing, by Enter or Esc: nothing of the preview stays.
    open_now = nil
    api.ui_redraw()
    return
  end
  if not text:match("%S") and not state.spec.empty then return end
  local before = snapshot()
  W.entering = state.mode == "i"
  local said, level = quietly(function()
    paw.audition.try(function()
      over(state, function() paw.commands.exec(line_of(state, text)) end)
    end)
  end)
  W.entering = nil
  if level == "error" then
    paw.audition.revert()
  else
    view.ghost = changed(before)
  end
  view.cache = nil
  api.ui_redraw()
  return said, level
end

--- Write the text for real: one undo step, remembered for `@:`, the
--- command line's history and `<localleader>.`.
local function commit(state, text)
  paw.audition.revert()
  view.ghost, view.cache = nil, nil
  if not text:match("%S") and not state.spec.empty then return end
  local line = line_of(state, text)
  P.last = { name = state.spec.name, text = text }
  paw.state.last_cmdline = line
  cmdline.remember("cmdline", line)
  api.undo_label(state.spec.label)
  W.entering = state.mode == "i"
  local ok, err = pcall(over, state, function() paw.commands.exec(line) end)
  W.entering = nil
  if not ok then paw.notify(tostring(err), "error") end
end

--- Where the prompt goes on the screen: over the caret's staff, where the
--- cell view drew it; nil on an engraved page, which draws its own.
local function anchor()
  local at = view.caret_cell
  if at then return { x = at.x, y = at.y } end
end

--- Open a popover by name: `opts.text` puts text in the line, `opts.region`
--- is the stretch an operator chose, which it is for.
function P.open(name, opts)
  opts = opts or {}
  local spec = P.specs[name]
  if not spec then return paw.notify("no popover " .. tostring(name), "warn") end
  if not view:clip() then return paw.notify("no clip open as notation", "warn") end
  if view:readonly() then return end
  local mode = keymap.mode
  local range = ""
  if mode == "x" and keymap.selection() then
    range = "'<,'>"
    keymap.set_mode("n")
  end
  -- Insert mode's Ctrl-o (one command of normal mode) opened it: it is for
  -- entering, and entering goes on after it.
  local entering = mode == "i" or view.once_normal
  open_now = { spec = spec, range = range, mode = entering and "i" or "n", region = opts.region }
  local state = open_now
  cmdline.open({
    prompt = spec.prompt,
    history = "notation." .. spec.name,
    label = spec.label,
    text = opts.text,
    complete = spec.complete,
    on_change = preview,
    anchor = anchor,
    mode = state.mode,
    ghost = spec.hint,
    on_key = spec.on_key and function(key, text) return spec.on_key(key, text, state) end,
  }, function(text) commit(state, text) end)
  -- One that needs no text shows what Enter would do at once.
  if spec.at_once then preview("") end
end

-- The popovers ---------------------------------------------------------------------------------

local function items(list) return W.list_of(list) end

local DYNAMIC_ITEMS = {
  { "ppp", "very very soft" },
  { "pp", "very soft" },
  { "p", "soft" },
  { "mp", "moderately soft" },
  { "mf", "moderately loud" },
  { "f", "loud" },
  { "ff", "very loud" },
  { "fff", "very very loud" },
  { "sfz", "a sudden accent" },
  { "sf", "a sudden accent" },
  { "fz", "forced" },
  { "rfz", "reinforced" },
  { "fp", "loud, then at once soft" },
  { "sfp", "accent, then at once soft" },
  { "p subito", "suddenly soft" },
  { "f subito", "suddenly loud" },
  { "<", "crescendo to the next dynamic" },
  { ">", "diminuendo to the next dynamic" },
  { "mp<f", "mp, crescendo to f over the selection" },
  { "f>p", "f, diminuendo to p over the selection" },
  { "niente<", "crescendo from nothing" },
  { ">niente", "diminuendo to nothing" },
  { "off", "take the dynamic here away" },
}

local TEMPO_ITEMS = {
  { "Allegro q=132", "lively" },
  { "Andante q=92", "walking" },
  { "Adagio q=70", "slow" },
  { "Moderato q=112", "moderate" },
  { "Presto q=180", "very fast" },
  { "Largo q=50", "broad" },
  { "Vivace q=160", "lively and fast" },
  { "q=120", "a metronome mark" },
  { "q.=60", "dotted quarters a minute" },
  { "rit.", "slowing to the end of the selection" },
  { "accel.", "quickening to the end of the selection" },
  { "a tempo", "back to the tempo before" },
  { "off", "take the tempo mark here away" },
}

local METER_ITEMS = {
  { "4/4" },
  { "3/4" },
  { "2/4" },
  { "6/8" },
  { "9/8" },
  { "12/8" },
  { "5/4" },
  { "7/8" },
  { "3+3+2/8", "three beats: 3, 3, 2 eighths" },
  { "2+2+3/8", "three beats: 2, 2, 3 eighths" },
  { "2/2" },
  { "C", "common time, 4/4" },
  { "¢", "cut time, 2/2" },
}

local KEY_ITEMS = {
  { "C", "C major" },
  { "G", "G major, 1 sharp" },
  { "D", "D major, 2 sharps" },
  { "A", "A major, 3 sharps" },
  { "E", "E major, 4 sharps" },
  { "B", "B major, 5 sharps" },
  { "F#", "F# major, 6 sharps" },
  { "F", "F major, 1 flat" },
  { "Bb", "Bb major, 2 flats" },
  { "Eb", "Eb major, 3 flats" },
  { "Ab", "Ab major, 4 flats" },
  { "Db", "Db major, 5 flats" },
  { "a", "A minor" },
  { "e", "E minor" },
  { "b", "B minor" },
  { "f#m", "F# minor" },
  { "c#m", "C# minor" },
  { "d", "D minor" },
  { "g", "G minor" },
  { "c", "C minor" },
  { "f", "F minor" },
  { "D dorian" },
  { "E phrygian" },
  { "F lydian" },
  { "G mixolydian" },
  { "off", "no key change here" },
}

local CLEF_ITEMS = {
  { "treble" },
  { "bass" },
  { "alto", "C clef on the middle line" },
  { "tenor", "C clef on the fourth line" },
  { "treble8", "an octave lower, as a guitar is written" },
  { "bass8", "an octave lower" },
  { "off", "no clef change here" },
}

local BAR_ITEMS = {}
for _, k in ipairs({ "||", "|.", "|:", ":|", ":|:", "1.", "2.", "3.", "|", "off" }) do
  BAR_ITEMS[#BAR_ITEMS + 1] = { k, W.BARLINES[k] }
end

local ORN_ITEMS = {
  { "tr", "trill" },
  { "mordent" },
  { "prall", "inverted mordent" },
  { "turn" },
  { "fermata", "a pause, held" },
  { "fermata short" },
  { "fermata long" },
  { "trem", "tremolo" },
  { "off", "take the ornaments away" },
}

local TUPLET_ITEMS = {
  { "3", "three in the time of two" },
  { "5", "five in the time of four" },
  { "6", "six in the time of four" },
  { "7", "seven in the time of four" },
  { "2", "two in the time of three (a duplet)" },
  { "5:4" },
  { "7:8" },
  { "off", "plain values again" },
}

local INTERVAL_ITEMS = {
  { "3", "a third above" },
  { "6", "a sixth above" },
  { "8", "an octave above" },
  { "5", "a fifth above" },
  { "4", "a fourth above" },
  { "-3", "a third below" },
  { "-6", "a sixth below" },
  { "-8", "an octave below" },
  { "m3", "a minor third above" },
  { "M3", "a major third above" },
  { "P5", "a perfect fifth above" },
}

local VOICE_ITEMS = { { "1", "up stems" }, { "2", "down stems" }, { "3" }, { "4" } }

P.define({
  key = "d",
  name = "dynamics",
  command = "notation.dyn",
  prompt = "dynamic ",
  label = "Write a dynamic",
  complete = items(DYNAMIC_ITEMS),
  hint = "pp p mp mf f ff  mp<f  sfz",
})
P.define({
  key = "t",
  name = "tempo",
  command = "notation.tempo",
  prompt = "tempo ",
  label = "Write a tempo mark",
  complete = items(TEMPO_ITEMS),
  hint = "Allegro q=132  rit.  a tempo",
})
P.define({
  key = "m",
  name = "meter",
  command = "notation.meter",
  prompt = "time ",
  label = "Write a time signature",
  complete = items(METER_ITEMS),
  hint = "6/8  3+3+2/8",
})
P.define({
  key = "k",
  name = "key",
  command = "notation.key",
  prompt = "key ",
  label = "Write a key signature",
  complete = items(KEY_ITEMS),
  hint = "Eb  f#m  D dorian",
})
P.define({
  key = "C",
  name = "clef",
  command = "notation.clef",
  prompt = "clef ",
  label = "Write a clef",
  complete = items(CLEF_ITEMS),
  hint = "bass  treble8  alto",
})
P.define({
  key = "b",
  name = "bars",
  command = "notation.bar",
  prompt = "bar ",
  label = "Write a barline",
  complete = items(BAR_ITEMS),
  hint = "||  |:  :|  |.  1.  2.",
})
P.define({
  key = "X",
  name = "text",
  command = "notation.text",
  prompt = "text ",
  label = "Write text",
  complete = items({
    { "dolce" },
    { "espressivo" },
    { "cantabile" },
    { "legato" },
    { "Solo" },
    { "Tutti" },
    { "sempre" },
  }),
  hint = "dolce  Solo",
})
P.define({
  key = "r",
  name = "rehearsal",
  command = "notation.rehearsal",
  prompt = "rehearsal ",
  label = "Write a rehearsal mark",
  complete = items({
    { "A" },
    { "B" },
    { "C" },
    { "Intro" },
    { "Verse" },
    { "Chorus" },
    { "Bridge" },
    { "off", "take it away" },
  }),
  hint = "A (Enter alone: the next letter)",
  empty = true,
})
P.define({
  key = "i",
  name = "intervals",
  command = "notation.interval",
  prompt = "interval ",
  label = "Add an interval",
  complete = items(INTERVAL_ITEMS),
  hint = "3  -6  8  m3  P5",
})
P.define({
  key = "3",
  name = "tuplets",
  command = "notation.tuplet",
  prompt = "tuplet ",
  label = "Write a tuplet",
  complete = items(TUPLET_ITEMS),
  hint = "3  5:4  off",
})
P.define({
  key = "v",
  name = "voice",
  command = "notation.voice",
  prompt = "voice ",
  label = "Choose a voice",
  complete = items(VOICE_ITEMS),
  hint = "1 to 4",
})
P.define({
  key = "o",
  name = "ornaments",
  command = "notation.orn",
  prompt = "ornament ",
  label = "Write an ornament",
  complete = items(ORN_ITEMS),
  hint = "tr  mordent  turn  fermata",
})
local tech = {}
for _, t in ipairs(W.TECHNIQUES) do
  tech[#tech + 1] = { t }
end
P.define({
  key = "p",
  name = "techniques",
  command = "notation.tech",
  prompt = "technique ",
  label = "Write a playing technique",
  complete = items(tech),
  hint = "pizz.  arco  con sord.",
})

-- Marks that drifted: no letter of its own, `g@` opens it (an operator, so
-- over what a motion or the selection reaches), and `:notation.apply-marks`
-- is the same without the prompt.
P.define({
  name = "apply-marks",
  command = "notation.apply-marks",
  prompt = "apply marks ",
  label = "Apply the marks to the notes",
  hint = "Enter: the notes play as the dynamics and articulations say",
  empty = true,
  at_once = true,
})

-- Lyrics and chord symbols are typed along the music: Space puts down what
-- is typed and goes on, the line open for the next.

--- Go on to the next chord of the cursor's voice; false at the end.
local function next_note()
  local ev = W.chord_from(view.beat, true)
  if not ev then return false end
  view:set(ev.notes[1].step, ev.start)
  return true
end

P.define({
  key = "l",
  name = "lyrics",
  command = "notation.lyric",
  prompt = "lyric ",
  label = "Write a lyric",
  hint = "syllables, Space next, - hyphen",
  on_key = function(key, text, state)
    local ending = (key == "-" and "-") or (key == "_" and "_") or ((key == "<Space>" or key == " ") and "") or nil
    if not ending then return nil end
    -- `verse=2` and a space: the verse, then its syllables.
    if text:match("^verse=%d+$") and ending == "" then return text .. " " end
    -- A verse said at the start stays for the next syllables.
    local verse = text:match("^(verse=%d+%s+)") or ""
    local syllable = text:sub(#verse + 1)
    if syllable == "" and ending == "" then
      next_note()
      return verse
    end
    commit(state, verse .. syllable .. ending)
    next_note()
    return verse
  end,
})

P.define({
  key = "q",
  name = "chords",
  command = "notation.chord",
  prompt = "chord ",
  label = "Write a chord symbol",
  complete = function(text) return W.chord_candidates(text) end,
  hint = "Cmaj7  G/B  N.C.",
  on_key = function(key, text, state)
    if key ~= "<Space>" and key ~= " " then return nil end
    if text:match("%S") then commit(state, text) end
    -- On to the next beat.
    local m = view:measure_at(view.beat)
    if m then
      local beat = m.meter.beat
      local nxt = m.start + (math.floor((view.beat - m.start) / beat + 1e-6) + 1) * beat
      view:set(nil, nxt)
    end
    return ""
  end,
})

-- Keys -----------------------------------------------------------------------------------------

local function opener(name)
  return function() P.open(name) end
end

for _, name in ipairs(P.order) do
  local spec = P.specs[name]
  local desc = "Popover: " .. spec.name .. " (" .. spec.hint .. ")"
  if spec.key then
    keymap.set("<localleader>" .. spec.key, opener(name), { view = "notation", mode = { "n", "x" }, desc = desc })
  end
end
local function again()
  if not P.last then return paw.notify("no popover yet", "warn") end
  P.open(P.last.name, { text = P.last.text })
end
keymap.set(
  "<localleader>.",
  again,
  { view = "notation", mode = { "n", "x" }, desc = "The last popover again, with what was typed in it" }
)

-- The ghost: the measures the preview changed, drawn in the accent.
table.insert(view.decorators, function(layout)
  local ghost = view.ghost
  for _, m in ipairs(layout.measures) do
    m.ghost = ghost and m.id and ghost.measures[m.id] or nil
  end
end)

--- Draw the open popover on an engraved page (`notation.gui`): a box at
--- `x`, its bottom at `y`, with the prompt, the text and the caret, the
--- preview's words, and the candidates under it.
function P.paint(g, x, y, width, colours)
  local st = cmdline.state()
  if not (open_now and st) then return end
  local text = st.before .. st.after
  local note = st.note or ""
  local ghost = text == "" and st.ghost or nil
  local w = math.min(width - 8, math.max(220, 8 * (#st.prompt + #text + #note + #(ghost or "")) + 40))
  local h = 24
  x = math.max(4, math.min(x - 12, width - w - 4))
  y = math.max(2, y - h)
  g:rect(x, y, w, h, { fill = colours.control, stroke = colours.select, width = 1, radius = 4 })
  local used = g:text(x + 8, y + 4, st.prompt, { color = colours.select, bold = true }) or (8 * #st.prompt)
  g:text(x + 8 + used, y + 4, text, { color = colours.text })
  if ghost then g:text(x + 8 + used + 8, y + 4, ghost, { color = colours.text_2, width = w - used - 24 }) end
  local cx = x + 8 + used + 8 * api.str_width(st.before)
  g:rect(cx, y + 4, 1, h - 8, { fill = colours.text })
  if note ~= "" then
    g:text(
      x + w - 8,
      y + 4,
      note,
      { color = st.note_level == "error" and colours.warn or colours.text_2, align = "right", width = w / 2 }
    )
  end
  local list = st.matches or {}
  for i = 1, math.min(#list, 8) do
    local c = list[i]
    local ry = y + h + (i - 1) * 20
    g:rect(x, ry, w, 20, { fill = i == st.match and colours.select or colours.control })
    g:text(x + 8, ry + 2, c.label, { color = colours.text, width = w / 2 })
    if c.desc then g:text(x + w / 2, ry + 2, c.desc, { color = colours.text_2, width = w / 2 - 8 }) end
  end
end

return P
