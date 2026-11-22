-- Lesson 12: recording audio and MIDI.
local api = paw.api

--- What a person does with a MIDI keyboard, done by the tests: three notes.
local function play_three_notes()
  for _, pitch in ipairs({ "C4", "E4", "G4" }) do
    paw.midi.note_on(pitch, 100)
    api.sleep(150)
    paw.midi.note_off(pitch)
    api.sleep(50)
  end
end

return {
  id = "recording",
  title = "Record audio and MIDI",
  intro = [[
In this lesson, we record an audio take and a MIDI take on two tracks,
over a drum beat.

A track records its input. This is audio from an input of your sound card (a
microphone, a guitar), or notes from a MIDI keyboard. Arm the tracks that must
record, start the recording, play, and stop. Each armed track gets a new clip
at the position where the recording started.

A track with an audio input records audio. An armed track with no input
records MIDI. For the first part, you need a microphone or a different input.
For the second part, you need a MIDI keyboard. If you do not have them, read
the steps, and press `<leader>hn` to skip a step. The recordings of this practice
project go in the folder of the tutor.]],
  idea = [[
In the arrange view, `I` shows the inputs that the track can use. These are
no audio input, each channel of the input device, and each pair of channels
(for example `UR22mkII · 1/2`). They are also MIDI from all ports or from one
port, and one MIDI channel.
`<A-i>`, or the `I` in the header, monitors the input: you hear it, but paw
does not record it.

`r` arms the track. `R` starts the recording from the cursor. `R` again
stops the recording, but the song continues to play. Then `<leader><Space>` stops it.

`:midi.inputs` shows the MIDI ports and `:midi.select` selects some.
`:audio` selects the input and output devices. Each take is one undo step.]],
  vim = [[
Here, `r` arms a track. It does not replace text. `R` records. It is not
replace mode.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_track({ name = "Drums", volume = -6 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 16, notes = look.drums(look.beat, 4) })
    paw.add_track({ name = "Voice" })
    local keys = paw.add_track({ name = "Keys", volume = -6 })
    keys:add_device("synth", { wave = 3, attack = 0.01, release = 0.3, cutoff = 2000 })
  end,
  at = function() paw.cursor.set_track(paw.track("Voice")) end,
  -- The tests' audio engine plays a test tone as its input, the way the suite
  -- tests recording.
  test = {
    before = function() api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } }) end,
    after = function() api.engine_restart({ backend = "null" }) end,
  },
  steps = {
    {
      say = "The cursor is on Voice, a track with no device. `I` shows the inputs that it can use. Press `I`. Type some letters of the input of your microphone. Type `1/2` for the first pair of channels, or `· 1` for the first channel. Press `<CR>`.",
      keys = { "I", "1/2", "<CR>" },
      check = function(_, look) return look.track("Voice").input ~= nil end,
      done = "Voice gets its sound from that input. The header shows the input and its level. `<A-i>` lets you hear it without a recording.",
      hint = "If the list has no channels, no input device is open. `:audio` shows the devices and lets you select one.",
    },
    {
      say = "`r` arms the track for a recording, and its `R` becomes red. Press `r`.",
      keys = { "r" },
      check = function(_, look) return look.track("Voice").armed end,
      done = "The track is armed. You also hear the input of an armed track.",
    },
    {
      say = "`R` starts the recording from the cursor, as `<leader><Space>` plays from it. Press `R`. Sing or play for some seconds. Then press `R` to stop the recording, and `<leader><Space>` to stop the song.",
      keys = { "R", { wait = 1000 }, "R", "<leader><Space>" },
      check = function(_, look)
        local clip = look.clips("Voice")[1]
        return clip and clip.kind == "audio" and not paw.transport.playing and not paw.transport.recording
      end,
      hint = "Press `R` before `<leader><Space>`. If you press only `<leader><Space>`, record mode stays on (`rec` is lit in the status line), and the next `<leader><Space>` records again.",
      done = "A new audio clip with your take shows where the recording started. The clip shows its waveform.",
    },
    {
      say = "Now we record MIDI. Press `r` to disarm Voice, `j` to go to Keys, and `r` to arm Keys.",
      keys = { "r", "j", "r" },
      check = function(_, look) return not look.track("Voice").armed and look.track("Keys").armed end,
      done = "Keys is armed and has no audio input, so it records MIDI. Play your keyboard, and you hear the synth.",
      hint = "`:midi.inputs` shows the MIDI ports that paw finds.",
    },
    {
      say = "Press `0` to put the cursor at the start and `R` to record. Play some notes on your MIDI keyboard. Then press `R` and `<leader><Space>` to stop.",
      keys = { "0", "R", { sim = play_three_notes, instead = {} }, "R", "<leader><Space>" },
      check = function(_, look)
        local clip = look.clips("Keys")[1]
        return clip and clip.kind == "midi" and #clip:notes() > 0 and not paw.transport.playing and not paw.transport.recording
      end,
      done = "A MIDI clip contains the notes that you played. `<CR>` on the clip opens it in the piano roll.",
    },
    {
      say = "Press `r` to disarm Keys. Then listen: press `gs` and `<leader><Space>`, and `<leader><Space>` to stop.",
      keys = { "r", "gs", "<leader><Space>", { wait = 300 }, "<leader><Space>" },
      check = function(ctx, look) return not look.track("Keys").armed and look.played(ctx) end,
      done = "Your recordings play with the drums.",
    },
  },
  outro = "We selected an input with `I`, armed with `r`, recorded with `R` and stopped with `<leader><Space>`. We made an audio take and a MIDI take.",
}
