-- Lesson 13: saving and rendering.
return {
  id = "saving",
  title = "Save and render",
  intro = [[
In this lesson, we change a song, save it, and render it to a WAV file.

A project is a folder that contains all of the song. It has the tracks,
the devices and their settings, the clips, the notes, the automation and the
loop. Each part is in a file of its own. Recordings are in the `media`
folder of the project. To render, paw plays the whole song
into a WAV file, which other programs can play.

This practice project already has a folder of its own in the folder of the tutor, so `:w`
saves it there. paw saves your own projects where you tell it: `:w song`.]],
  idea = [[
`:w` saves, and `<C-s>` also saves. `:w name` saves under a new name.
`:e name` opens a project. `:e song.mid` makes a project from a MIDI
file, and the project has no folder until `:w name`. `:new` starts an
empty project. `:wq` or `ZZ` save and quit, and `:q` or `ZQ` quit without a
save.

The status line shows the name of the project, with `[+]` when there are
changes that are not saved. `:render name.wav` writes the song to a file.
`tail=2` adds two seconds for the echoes to stop, and `bits=16` makes a
16-bit file. A name without a folder goes into the folder of the project. `:pwd`
shows that folder, and `:cd` changes it.]],
  vim = [[
`:w`, `:e`, `:wq`, `:x`, `ZZ` and `ZQ` work as in Vim, but on projects, not
on files. Only one project is open at a time, and `:e` replaces it. `:w
name` is the `:saveas` of Vim: you continue to work in the new file. In
Vim, `:w name` writes a copy and you stay in the old file. paw does not make
such a copy.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_track({ name = "Drums", volume = -6 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 8, notes = look.drums(look.beat, 2) })
    local keys = paw.add_track({ name = "Keys", volume = -8 })
    keys:add_device("synth", { wave = 3, attack = 0.02, release = 0.5, cutoff = 1800 })
    keys:add_device("delay", { time = 450, feedback = 0.35, mix = 0.25 })
    local chords = look.chord({ "D4", "F4", "A4" }, 4)
    for _, n in ipairs(look.chord({ "C4", "E4", "G4" }, 4, 4)) do
      chords[#chords + 1] = n
    end
    keys:add_clip({ name = "chords", start = 0, length = 8, notes = chords })
  end,
  at = function() paw.cursor.set_track(paw.track("Keys")) end,
  test = {
    -- Rendering writes beside the practice project; the test tidies up.
    after = function() os.remove(paw.files.here() .. "/tutor-song.wav") end,
  },
  steps = {
    {
      say = "First, change the song: `&` puts a copy of the chords after them. Press `&`. The name of the project in the status line gets a `[+]`.",
      keys = { "&" },
      check = function() return paw.project.modified and #paw.track("Keys"):clips() == 2 end,
      done = "The `[+]` shows that some changes are not saved.",
    },
    {
      say = "Type `:w` and `<CR>` to save. `<C-s>` does the same.",
      keys = { ":w", "<CR>" },
      check = function(ctx, look) return look.saw(ctx, "project.saved") and not paw.project.modified end,
      done = "The project is saved. The `[+]` is gone, and the message line shows the file.",
    },
    {
      say = "`:render` plays the song into a WAV file. Type `:render tutor-song.wav tail=2` and `<CR>`.",
      keys = { ":render tutor-song.wav tail=2", "<CR>" },
      check = function(ctx, look) return look.ran(ctx, "render") and look.said(ctx, "tutor-song.wav") end,
      done = "tutor-song.wav is in the folder of the practice project. The message line shows its length and peak level.",
      hint = "`tail=2` keeps two more seconds after the last note, so the echo does not stop too early.",
    },
    {
      say = "`:messages` shows the messages that you did not see. Type `:messages` and `<CR>`, then press `q` to close the list.",
      keys = { ":messages", "<CR>", "q" },
      check = function(ctx, look) return look.ran(ctx, "messages") and not look.float() end,
      done = "The list showed all the messages since paw started, with the saves and the renders.",
    },
    {
      say = "You can play the rendered file in a different player. Here, `<leader><Space>` plays the song in paw. `<leader><Space>` stops.",
      keys = { "<leader><Space>", { wait = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.played(ctx) end,
      done = "The song is saved and rendered.",
    },
  },
  outro = "We saved with `:w`, saw `[+]` for changes that are not saved, rendered with `:render name.wav tail=2` and read `:messages`.",
}
