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

A track records its input, which is either audio from an input of your
sound card, e.g., a microphone or a guitar, or notes from a MIDI keyboard.
To record, first arm the tracks that you want to record. Second, start the
recording and play, and third, stop the recording. Each armed track gets a new clip at the position where the recording
started. A track with an audio input records audio, and an armed track with
no input records MIDI.

For the first part of the lesson, you need a microphone or another input,
and for the second part, you need a MIDI keyboard. If you do not have them,
read the steps and press `<leader>hn` to skip a step. The recordings of the
practice project go in the folder of the tutor.]],
  idea = [[
In the arrange view, `I` shows the inputs that the track can use. The
audio inputs are each channel of the input device and each pair of
channels, for example `UR22mkII · 1/2`, and there is also an entry for no
audio input. The MIDI inputs are all ports, one port, or one MIDI channel.

`<A-i>`, or the `I` in the header, monitors the input, so you hear the
input, but paw does not record it.

`r` arms the track, and `R` starts the recording from the cursor. `R` again
stops the recording, but the song continues to play until you press
`<leader><Space>`.

`:midi.inputs` shows the MIDI ports, and `:midi.select` selects some of
them. `:audio` selects the input and output devices. Each take is one undo
step.]],
  vim = [[
In paw, `r` arms a track instead of replacing a character, and `R` records
instead of starting replace mode.]],
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
    before = function()
      api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
    end,
    after = function() api.engine_restart({ backend = "null" }) end,
  },
  steps = {
    {
      say = "The cursor is on Voice, a track with no device, and `I` shows the inputs that the track can use. Press `I`, and type some letters of the input of your microphone. Type `1/2` for the first pair of channels, or `· 1` for the first channel, and press `<CR>`.",
      keys = { "I", "1/2", "<CR>" },
      check = function(_, look) return look.track("Voice").input ~= nil end,
      done = "Voice gets its sound from the input that you selected, and the header shows the input and its level. With `<A-i>`, you hear the input without a recording.",
      hint = "If the list has no channels, no input device is open. `:audio` shows the devices, and you can select one there.",
    },
    {
      say = "`r` arms the track for a recording, and its `R` becomes red. Press `r`.",
      keys = { "r" },
      check = function(_, look) return look.track("Voice").armed end,
      done = "The track is armed, and you also hear the input of an armed track.",
    },
    {
      say = "`R` starts the recording from the cursor, as `<leader><Space>` plays from it. Press `R`, and sing or play for some seconds. Then press `R` to stop the recording, and `<leader><Space>` to stop the song.",
      keys = { "R", { wait = 1000 }, "R", "<leader><Space>" },
      check = function(_, look)
        local clip = look.clips("Voice")[1]
        return clip and clip.kind == "audio" and not paw.transport.playing and not paw.transport.recording
      end,
      hint = "Press `R` before `<leader><Space>`. If you press only `<leader><Space>`, record mode stays on, with `rec` lit in the status line, and the next `<leader><Space>` records again.",
      done = "A new audio clip with your take shows where the recording started, and the clip shows its waveform.",
    },
    {
      say = "Now we record MIDI. Press `r` to disarm Voice, `j` to go to Keys, and `r` to arm Keys.",
      keys = { "r", "j", "r" },
      check = function(_, look) return not look.track("Voice").armed and look.track("Keys").armed end,
      done = "Keys is armed and has no audio input, so it records MIDI. When you play your keyboard, you hear the synth.",
      hint = "`:midi.inputs` shows the MIDI ports that paw finds.",
    },
    {
      say = "Press `0` to put the cursor at the start, and `R` to record. Play some notes on your MIDI keyboard, and then press `R` and `<leader><Space>` to stop.",
      keys = { "0", "R", { sim = play_three_notes, instead = {} }, "R", "<leader><Space>" },
      check = function(_, look)
        local clip = look.clips("Keys")[1]
        return clip
          and clip.kind == "midi"
          and #clip:notes() > 0
          and not paw.transport.playing
          and not paw.transport.recording
      end,
      done = "A MIDI clip contains the notes that you played, and `<CR>` on the clip opens it in the piano roll.",
    },
    {
      say = "Press `r` to disarm Keys. Then press `gs` and `<leader><Space>` to listen, and `<leader><Space>` to stop.",
      keys = { "r", "gs", "<leader><Space>", { wait = 300 }, "<leader><Space>" },
      check = function(ctx, look) return not look.track("Keys").armed and look.played(ctx) end,
      done = "Your recordings play with the drums.",
    },
  },
  outro = "We selected an input with `I`, armed the track with `r`, recorded with `R` and stopped with `<leader><Space>`, and we made an audio take and a MIDI take.",
}
