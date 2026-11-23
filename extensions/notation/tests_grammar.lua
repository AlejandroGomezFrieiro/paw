-- Tests of the grammar for music: text objects over the score, operators
-- that change what is written, motions by what is written, the entry
-- modes, and Ex over a score clip. Loaded by tests/suite.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation")
end

local keys = T.keys

--- A track with an empty clip open as notation; `typed` entered from bar 1.
local function song(typed, length)
  fresh()
  local view = load()
  local track = paw.add_track({ name = "Lead" })
  track:add_device("synth")
  local clip = track:add_clip({ start = 0, length = length or 8, name = "tune", notes = {} })
  paw.flush()
  paw.keymap.set_mode("n")
  view:edit(clip)
  view.value, view.dot, view.voice, view.triplets, view.tuplet = 1, false, 1, false, nil
  if typed then
    view:set(35, 0)
    keys("i" .. typed .. "<Esc>")
  end
  return view, clip, track
end

--- The written text of a staff and voice: "q C4 q D4 | R".
local function written(view, staff, voice) return require("notation.model").text(view:layout(), staff, voice) end

-- Steps of the staff, as the cursor counts them.
local C4, D4, E4, G4 = 35, 36, 37, 39

-- Text objects -----------------------------------------------------------------------------------

test("grammar: ic is the chord, in a note of it, an the note and what its ties join", function()
  local view = song("CEgde")
  eq(written(view), "q <C4 E4 G4> q D4 q E4 qr | R", "a chord, then D and E")
  view:set(C4, 0)
  keys("dic")
  eq(written(view), "qr q D4 q E4 qr | R", "dic: the chord is a rest")
  keys("u")
  view:set(E4, 0)
  keys("din")
  eq(written(view), "q <C4 G4> q D4 q E4 qr | R", "din: only the E leaves the chord")
  view:set(D4, 1)
  keys("d2ic")
  eq(written(view), "q <C4 G4> qr hr | R", "d2ic: two chords")
end)

test("grammar: an takes the tie chain", function()
  local view = song("cc~d")
  eq(written(view), "q C4 q~ C4 q C4 q D4 | R", "a C held on by a tie")
  view:set(C4, 1)
  keys("dan")
  eq(written(view), "q C4 qr qr q D4 | R", "the C and the C its tie joins")
end)

test("grammar: ib empties the bar, ab takes it out and p puts it back", function()
  local view = song("cdefgabc")
  eq(written(view), "q C4 q D4 q E4 q F4 | q G4 q A4 q B4 q C5", "two bars")
  view:set(C4, 0)
  keys("dib")
  eq(written(view), "R | q G4 q A4 q B4 q C5", "dib: a bar's rest")
  keys("u")
  keys("dab")
  eq(written(view), "q G4 q A4 q B4 q C5 | R", "dab: the bar is gone, the next closes up")
  keys("p")
  eq(written(view), "q G4 q A4 q B4 q C5 | q C4 q D4 q E4 q F4", "p: the bar again, after the cursor's")
  keys("u")
  view:set(G4, 0)
  keys("yabP")
  eq(written(view), "q G4 q A4 q B4 q C5 | q G4 q A4 q B4 q C5", "yab P: a copy before it")
end)

test("grammar: counts take more bars, beats and chords", function()
  local view = song("cdefgabc", 12)
  view:set(C4, 0)
  keys("d2ab")
  eq(written(view), "R | R | R", "d2ab: both bars out")
  keys("u")
  view:set(D4, 1)
  keys("d2i.")
  eq(written(view), "q C4 qr qr q F4 | q G4 q A4 q B4 q C5 | R", "d2i.: two beats")
end)

test("grammar: ip is the phrase between rests, ap with the rests after it", function()
  local view = song("cdrefrg")
  eq(written(view), "q C4 q D4 qr q E4 | q F4 qr q G4 qr", "three phrases")
  view:set(E4, 3)
  keys("dip")
  eq(written(view), "q C4 q D4 hr | hr q G4 qr", "dip: E and F, over the barline")
  keys("u")
  view:set(C4, 0)
  keys("dap")
  eq(written(view), "hr qr q E4 | q F4 qr q G4 qr", "dap: C, D and the rest after")
end)

test("grammar: il is the slur's notes, al the slur too, and g( slurs over a motion", function()
  local view = song("cdef")
  view:set(C4, 0)
  keys("g(3w")
  local evs = view:layout().measures[1].staves[1]
  eq(evs[1].slur_to == evs[3], true, "g(3w: a slur from C over E")
  view:set(D4, 1)
  keys("yil")
  eq(#paw.keymap.getreg().notes, 3, "yil: the three notes under it")
  keys("dal")
  eq(written(view), "hr qr q F4 | R", "dal: the notes and the slur")
end)

test("grammar: iv is one voice of the bar, is the staff", function()
  local view = song("cdef")
  view.voice = 2
  view:set(30, 0)
  keys("i7g<Esc>")
  eq(written(view, 1, 2), "w G3 | ", "a second voice")
  view:set(C4, 0)
  keys("div")
  eq(written(view), "R | R", "div: voice 1 is gone")
  eq(written(view, 1, 2), "w G3 | ", "voice 2 stays")
  keys("u")
  keys("dis")
  eq(written(view, 1, 0), "R | R", "dis: every voice of the staff")
end)

test("grammar: it is the tuplet's notes, at the tuplet", function()
  local view = song("4tcde")
  eq(written(view), "3{e C4 e D4 e E4} qr hr | R", "a triplet")
  view:set(D4, 1 / 3)
  keys("dit")
  eq(written(view), "R | R", "dit: its notes are rests, a silent tuplet a plain rest")
  keys("u")
  view:set(D4, 1 / 3)
  keys("yat")
  view:set(C4, 2)
  keys("P")
  eq(written(view), "3{e C4 e D4 e E4} qr 3{e C4 e D4 e E4} qr | R", "yat P: the tuplet copied, still a tuplet")
end)

-- Operators ---------------------------------------------------------------------------------------

test("grammar: gU and gu move by steps of the key, a count is the steps", function()
  local view = song("cdef")
  view:set(C4, 0)
  keys("gUib")
  eq(written(view), "q D4 q E4 q F4 q G4 | R", "gUib: a step up")
  keys("3guib")
  eq(written(view), "q A3 q B3 q C4 q D4 | R", "3guib: three steps down")
  keys("u")
  eq(written(view), "q D4 q E4 q F4 q G4 | R", "undo: one step back")
end)

test("grammar: g+ and g- move by semitones, spelled by the key, g~ respells", function()
  local view = song("cdef")
  view:set(C4, 0)
  keys("g+ic")
  eq(written(view), "q C#4 q D4 q E4 q F4 | R", "g+ic: C sharp")
  keys("g~ic")
  eq(written(view), "q Db4 q Dn4 q E4 q F4 | R", "g~: D flat")
  view:set(E4, 2)
  keys("2g-ic")
  eq(written(view), "q Db4 q Dn4 q D4 q F4 | R", "2g-: a whole tone down")
end)

test("grammar: g? is a retrograde, with a count an inversion", function()
  local view = song("6c4d3e3f")
  eq(written(view), "h C4 e D4 s E4 s F4 qr | R", "a rhythm")
  view:set(C4, 0)
  keys("g?ib")
  eq(written(view), "qr s F4 s E4 e D4 h C4 | R", "backwards, rhythm and all")
  keys("u")
  keys("2g?ib")
  eq(written(view), "h C4 e B3 s A3 s G3 qr | R", "inverted about C")
end)

test("grammar: gq spells in the key and writes the values as the metre has them", function()
  local view = song("c~ef")
  eq(written(view), "h C4 q E4 q F4 | R", "a C held on by a tie is one note: a half, as the metre writes it")
  view:set(E4, 2)
  keys("g+ic")
  keys("g~ic")
  eq(written(view), "h C4 q E#4 q F4 | R", "an F written as E sharp")
  keys("gqib")
  eq(written(view), "h C4 q F4 q F4 | R", "gq: one half note, and F as C major spells it")
end)

test("grammar: > and < move what is written, with its ids", function()
  local view, clip = song("cd")
  view:set(C4, 0)
  local id = clip:notes()[1].id
  keys(">ic")
  eq(written(view), "qr q C4 hr | R", ">ic: a quarter later, over what was there")
  eq(clip:notes()[1].id, id, "the same MIDI note, moved")
  keys("<lt>ic")
  eq(written(view), "q C4 qr hr | R", "<ic: back")
end)

test("grammar: ! filters through a named filter or a shell command", function()
  local view = song("6c4d3e3f")
  view:set(C4, 0)
  keys("!ib<C-u>reverse<CR>")
  eq(written(view), "qr s F4 s E4 e D4 h C4 | R", "!ib reverse: the line backwards")
  keys("u")
  keys("!ib<C-u>transpose 12<CR>")
  eq(written(view), "h C5 e D5 s E5 s F5 qr | R", "!ib transpose 12")
  keys("u")
  keys("!ib<C-u>tac<CR>")
  eq(written(view), "qr s F4 s E4 e D4 h C4 | R", "!ib tac: the same through the shell")
  keys("u")
  keys("!ib<C-u>sed s/D4/G4/<CR>")
  eq(written(view), "h C4 e G4 s E4 s F4 qr | R", "sed changes a note")
end)

test("grammar: ! in a build without processes says so, and its named filters still work", function()
  local view = song("6c4d3e3f")
  view:set(C4, 0)
  -- A build of the web, as the pod has it: no processes.
  local real = paw.api.build
  paw.api.build = function() return { vm = "lua52", features = {} } end
  T.after(function() paw.api.build = real end)
  keys("!ib<C-u>tac<CR>")
  eq(written(view), "h C4 e D4 s E4 s F4 qr | R", "nothing changes")
  eq(
    paw.ui.messages[#paw.ui.messages].text:find("! with a shell command needs processes", 1, true) ~= nil,
    true,
    "and the message names ! and processes"
  )
  keys("!ib<C-u>reverse<CR>")
  eq(written(view), "qr s F4 s E4 e D4 h C4 | R", "a named filter still works")
end)

test("grammar: . repeats an operator with its object, and each is one undo step", function()
  local view = song("cdef")
  view:set(C4, 0)
  keys("gUic")
  keys("w.")
  eq(written(view), "q D4 q E4 q E4 q F4 | R", "gUic then w.")
  keys("u")
  eq(written(view), "q D4 q D4 q E4 q F4 | R", "u takes back the repeat alone")
  view:set(E4, 2)
  keys("dic")
  keys("w.")
  eq(written(view), "q D4 q D4 hr | R", "dic then w.")
end)

-- Motions ------------------------------------------------------------------------------------------

test("grammar: f, F, t, T and ; go by letter, and an operator takes the note f finds", function()
  local view = song("cdefcdef")
  view:set(C4, 0)
  keys("fe")
  eq(view.beat, 2, "fe: the E")
  keys(";")
  eq(view.beat, 6, "; the next E")
  keys("Fc")
  eq(view.beat, 4, "Fc: the C before")
  keys("te")
  eq(view.beat, 5, "te: the D before the E")
  view:set(C4, 0)
  keys("dfe")
  eq(written(view), "hr qr q F4 | q C4 q D4 q E4 q F4", "dfe: the E too, as Vim's df")
end)

test("grammar: ) and ( go by phrase, ]v by voice, Ctrl-j by staff", function()
  local view = song("cdrefrg")
  view:set(C4, 0)
  keys(")")
  eq(view.beat, 3, "): the E after the rest")
  keys(")")
  eq(view.beat, 6, "and the G")
  keys("(")
  eq(view.beat, 3, "(: back")
  view.voice = 2
  view:set(30, 0)
  keys("i7g<Esc>")
  view:set(C4, 0)
  view.voice = 1
  keys("]v")
  eq(view.voice, 2, "]v: voice 2")
  eq(view.step, 32, "on its G")
  paw.cmd("notation.clef", { "grand" })
  view:set(C4, 0)
  keys("<C-j>")
  eq(view:cursor_staff(), 2, "Ctrl-j: the staff below")
  keys("<C-k>")
  eq(view:cursor_staff(), 1, "Ctrl-k: back up")
end)

-- Entry modes -----------------------------------------------------------------------------------------

test("grammar: I pushes later music along, Insert toggles it", function()
  local view = song("cdef")
  view:set(D4, 1)
  keys("Ig<Esc>")
  eq(written(view), "q C4 q G4 q D4 q E4 | q F4 qr hr", "I g: G in, D E F moved along")
  view:set(C4, 0)
  keys("I<Insert>a<Esc>")
  eq(written(view), "q A3 q G4 q D4 q E4 | q F4 qr hr", "Insert: written over again")
end)

test("grammar: r re-pitches a note, R re-pitches in turn, rhythm kept", function()
  local view = song("6c4d3e3f")
  view:set(D4, 2)
  keys("ra")
  eq(written(view), "h C4 e A3 s E4 s F4 qr | R", "ra: the D an A, nearest it")
  view:set(C4, 0)
  keys("Rgabc<Esc>")
  eq(written(view), "h G3 e A3 s B3 s C4 qr | R", "R: four new pitches on the old rhythm")
  view:set(C4, 0)
  keys("RcE<Esc>")
  eq(written(view), "h <C4 E4> e A3 s B3 s C4 qr | R", "an upper case letter adds to the chord")
end)

test("grammar: in insert mode Ctrl-o runs one command, Ctrl-r pastes a register", function()
  local view = song("cd")
  view:set(C4, 0)
  keys("yib")
  view:set(C4, 2)
  keys("i<C-o>")
  eq(paw.keymap.mode, "n", "Ctrl-o: normal mode")
  keys("w")
  eq(paw.keymap.mode, "i", "back to entering after one command")
  view:set(C4, 4)
  keys('<C-r>"')
  eq(written(view), "q C4 q D4 hr | q C4 q D4 hr", 'Ctrl-r ": the bar pasted')
  eq(view.beat, 8, "the cursor after it")
  keys("<Esc>")
end)

test("grammar: / and // enter grace notes, Ctrl-t a tuplet", function()
  local view = song()
  view:set(C4, 0)
  keys("i/dc<Esc>")
  eq(written(view), "q [D4]C4 qr hr | R", "/d: a grace note before the C")
  eq(view:layout().doc.measures[1].voices[1].events[1].grace, "acciaccatura", "an acciaccatura")
  view:set(C4, 1)
  keys("i//ed<Esc>")
  eq(view:layout().doc.measures[1].voices[1].events[3].grace, "appoggiatura", "//: an appoggiatura")
  view:set(C4, 2)
  keys("i3<C-t><C-u>5<CR>cdefg<Esc>")
  eq(written(view):find("5{s C4 s D4 s E4 s F4 s G4}", 1, true) ~= nil, true, "Ctrl-t 5: a quintuplet")
end)

test("grammar: Tab takes the suggestion shown as ghost notes", function()
  local view, clip = song("c")
  paw.complete.show(
    { { notes = { { pitch = 62, start = 1, length = 1 }, { pitch = 64, start = 2, length = 1 } } } },
    { clip = clip.id }
  )
  view:set(C4, 1)
  keys("1<Tab>")
  eq(written(view), "q C4 q D4 hr | R", "1 Tab: the next note")
  eq(view.beat, 2, "the cursor after it")
  keys("i<Tab><Esc>")
  eq(written(view), "q C4 q D4 q E4 qr | R", "Tab in insert mode: the rest of it")
end)

-- Ex -------------------------------------------------------------------------------------------------

test("grammar: Ex :s and :g change the notes, and notation shows them", function()
  local view = song("cdecdecd")
  keys(":%s/c4/db4/g<CR>")
  eq(
    written(view),
    "q C#4 q D4 q E4 q C4 | q D4 q E4 q C#4 q D4",
    ":%s/c4/db4/g: a MIDI edit, spelled by the key (the bar's sharp holds)"
  )
  keys("u")
  keys(":%s/c4/c#4/<CR>")
  eq(written(view), "q C#4 q D4 q E4 q Cn4 | q D4 q E4 q C#4 q D4", "without g, the first of each bar")
  keys("u")
  keys(":g/e4/d<CR>")
  eq(written(view), "q C4 q D4 qr q C4 | q D4 qr q C4 q D4", ":g/e4/d: the Es are rests")
  keys("u")
  keys(":%s/d4/+12/g<CR>")
  eq(written(view), "q C4 q D5 q E4 q C4 | q D5 q E4 q C4 q D5", "an octave keeps the spelling")
end)
