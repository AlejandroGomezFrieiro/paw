-- Lesson 13: save and export.
return {
  id = "saving",
  title = "Save and export",
  intro = [[
In this lesson, we change a song, save it, and export it to a WAV file.

A project is a folder that contains the whole song, e.g., the parts, the
devices and their settings, the clips and the notes. It also contains the
automation and the loop, and each part is in a file of its own. Recordings
are in the `media` folder of the project. To export, paw plays the whole
song into a WAV file, which other programs can play.

The practice project already has a folder of its own in the folder of the
tutor, so `:w` saves it there. paw saves your own projects where you tell
it to, e.g., `:w song`.]],
  idea = [[
`:w` and `<C-s>` save, and `:w name` saves under a new name. `:e name`
opens a project, and `:e song.mid` makes a project from a MIDI file, which
has no folder until you type `:w name`. `:new` starts an empty project.
`:wq` or `ZZ` save and quit, and `:q` or `ZQ` quit without a save.

The status line shows the name of the project, with `[+]` when there are
changes that are not saved. `:export name.wav` writes the song to a file.
`tail=2` adds two seconds for the echoes to stop, and `bits=16` makes a
16-bit file.

A file name without a folder goes into the folder `renders` of the
project. `:pwd` shows the folder of the project, and `:cd` changes it.]],
  vim = [[
`:w`, `:e`, `:wq`, `:x`, `ZZ` and `ZQ` work as in Vim, but on projects
instead of files. Only one project is open at a time, and `:e` replaces it.
`:w name` works as `:saveas` in Vim, so you continue to work in the new
project. In Vim, `:w name` writes a copy and you stay in the old file, but
paw does not make such a copy.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_part({ name = "Drums", volume = -6 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 8, notes = look.drums(look.beat, 2) })
    local keys = paw.add_part({ name = "Keys", volume = -8 })
    keys:add_device("synth", { wave = 3, attack = 0.02, release = 0.5, cutoff = 1800 })
    keys:add_device("delay", { time = 450, feedback = 0.35, mix = 0.25 })
    local chords = look.chord({ "D4", "F4", "A4" }, 4)
    for _, n in ipairs(look.chord({ "C4", "E4", "G4" }, 4, 4)) do
      chords[#chords + 1] = n
    end
    keys:add_clip({ name = "chords", start = 0, length = 8, notes = chords })
  end,
  at = function() paw.cursor.set_part(paw.part("Keys")) end,
  test = {
    -- The export writes into the renders folder of the practice project; the test tidies up.
    after = function() os.remove(paw.files.here() .. "/renders/tutor-song.wav") end,
  },
  steps = {
    {
      say = "First, change the song. `&` puts a copy of the chords after them, so press `&`, and the name of the project in the status line gets a `[+]`.",
      keys = { "&" },
      check = function() return paw.project.modified and #paw.part("Keys"):clips() == 2 end,
      done = "The `[+]` shows that some changes are not saved.",
    },
    {
      say = "Type `:w` and `<CR>` to save. `<C-s>` does the same.",
      keys = { ":w", "<CR>" },
      check = function(ctx, look) return look.saw(ctx, "project.saved") and not paw.project.modified end,
      done = "The project is saved, the `[+]` is gone, and the message line shows the file.",
    },
    {
      say = "`:export` plays the song into a WAV file. Type `:export tutor-song.wav tail=2` and `<CR>`.",
      keys = { ":export tutor-song.wav tail=2", "<CR>" },
      check = function(ctx, look) return look.ran(ctx, "export") and look.said(ctx, "tutor-song.wav") end,
      done = "tutor-song.wav is in the folder `renders` of the practice project, and the message line shows its length and peak level.",
      hint = "`tail=2` keeps two more seconds after the last note, so the echo does not stop too early.",
    },
    {
      say = "`:messages` shows the messages that you missed. Type `:messages` and `<CR>`, and then press `q` to close the list.",
      keys = { ":messages", "<CR>", "q" },
      check = function(ctx, look) return look.ran(ctx, "messages") and not look.float() end,
      done = "The list showed all the messages since paw started, with the saves and the export.",
    },
    {
      say = "You can play the rendered file in a different player. In paw, press `<leader><Space>` to play the song, and `<leader><Space>` again to stop.",
      keys = { "<leader><Space>", { advance = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.played(ctx) end,
      done = "The song is saved and exported.",
    },
  },
  outro = "We saved with `:w`, and we saw `[+]` for changes that are not saved. Then we exported with `:export name.wav tail=2` and read `:messages`.",
}
