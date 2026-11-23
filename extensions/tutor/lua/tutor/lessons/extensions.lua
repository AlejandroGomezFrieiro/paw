-- Lesson 16: what each bundled extension adds, one thing to try in each.
local function loaded(name) return paw.ext.loaded[name] ~= nil and paw.ext.loaded[name].ok end

return {
  id = "extensions",
  title = "The bundled extensions",
  intro = [=[
In this lesson, we load seven of the extensions that come with paw, and we
try one feature of each.

Much of what paw can do comes from extensions. An extension is a folder of
Lua in `extensions/` next to the program, and it uses the same `paw` module
as your `init.lua`. `:tutor.try` loads an extension for this session only.
To load an extension each time, link its folder into
`~/.config/paw/extensions`.

The README.md of each extension describes all that it does. Each extension
has its keys under its own prefix, e.g., `]]` `[[` and `\S` for sections,
`gz` for musicops and `\t` for pattern. Moreover, mixdiag uses
`<leader>m`, undotree uses `<leader>p` `g-` `g+`, and utau uses `\V`.]=],
  idea = [[
An extension adds commands, keys, text objects, operators and views with the
functions of lesson 15, so what it adds follows the grammar that you know.
For example, sections are text objects (`dis`, `yis`), and musicops are
operators (`gzkip`), so `.`, counts and macros work with them.]],
  vim = [[
`:tutor.try name` works as `:packadd` does in Vim, and `:extensions` shows
the loaded extensions.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_track({ name = "Drums", volume = -6 })
    drums:add_device("drums")
    local keys = paw.add_track({ name = "Keys", volume = -8 })
    keys:add_device("synth", { wave = 1, attack = 0.01, release = 0.3, cutoff = 2200 })
    keys:add_clip({
      name = "tune",
      start = 0,
      length = 8,
      notes = look.notes("C4:0:1 D4:1:1 E4:2:1 G4:3:1 E4:4:1 D4:5:1 C4:6:2"),
    })
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 8, true
  end,
  at = function() paw.cursor.set_track(paw.track("Drums")) end,
  test = {
    after = function() os.remove("tutor-song.rpp") end,
  },
  steps = {
    {
      say = "pattern writes drum parts as text. Type `:tutor.try pattern` and `<CR>`, and then type `:pattern.set bd*2 [~ sn]` and `<CR>`. A new clip on Drums plays the pattern.",
      keys = { ":tutor.try pattern", "<CR>", ":pattern.set bd*2 [~ sn]", "<CR>" },
      check = function(_, look)
        local clip = look.clips("Drums")[1]
        return loaded("pattern") and clip and #clip:notes() > 0
      end,
      done = "The clip plays kick, kick, rest and snare, and `\\tt` edits the text of the clip under the cursor.",
    },
    {
      say = "musicops adds musical operators under `gz`. Type `:tutor.try musicops` and `<CR>`, and press `j` to go to Keys. Then press `gzkic` to move each note of the clip one step up the scale.",
      keys = { ":tutor.try musicops", "<CR>", "j", "gzkic" },
      check = function(_, look)
        return loaded("musicops")
          and look.melody(look.clip("Keys")) == "62@0+1 64@1+1 65@2+1 69@3+1 65@4+1 64@5+1 62@6+2"
      end,
      done = "The tune is now D E F A F E D, because it moved in C major. `gzh` humanizes, `gzs` strums, and `.` repeats them.",
    },
    {
      say = "sections gives names to the parts of a song. Type `:tutor.try sections` and `<CR>`, and then press `\\Sa`, type `Verse` and press `<CR>` to mark a section at the cursor.",
      keys = { ":tutor.try sections", "<CR>", "\\Sa", "Verse", "<CR>" },
      check = function()
        if not loaded("sections") then return false end
        for _, s in ipairs(require("sections").list()) do
          if s.name == "Verse" then return true end
        end
      end,
      done = "Verse shows on the ruler, and `is` is now a text object. `yis` yanks the section on all tracks, and `]]` goes to the next section.",
    },
    {
      say = "undotree shows each state of the project. Type `:tutor.try undotree` and `<CR>`, and press `<leader>pu` to open the undo tree. Look at the tree, and then press `q` to close it.",
      keys = { ":tutor.try undotree", "<CR>", "<leader>pu", "q" },
      check = function(ctx, look)
        if look.float() == "undotree" then ctx.seen = true end
        return loaded("undotree") and ctx.seen and not look.float()
      end,
      done = "paw keeps each change that you undo, and `g-` and `g+` move through the states in order of time, across branches.",
    },
    {
      say = "mixdiag measures the mix and shows problems. Type `:tutor.try mixdiag` and `<CR>`, and then press `<leader>ma` to measure the song.",
      keys = { ":tutor.try mixdiag", "<CR>", "<leader>ma" },
      check = function(ctx, look) return loaded("mixdiag") and look.ran(ctx, "mix.analyze") end,
      done = "mixdiag measures in the background, and the message line shows the loudness when the measurement is complete. `<leader>mx` shows the problems that it found.",
    },
    {
      say = "interop opens and writes REAPER projects and DAWproject files. Type `:tutor.try interop` and `<CR>`, and then type `:export tutor-song.rpp` and `<CR>`. A list of the items that REAPER cannot use opens, and `q` closes it.",
      keys = { ":tutor.try interop", "<CR>", ":export tutor-song.rpp", "<CR>", "q" },
      check = function(ctx, look) return loaded("interop") and look.ran(ctx, "export") and not look.float() end,
      done = "tutor-song.rpp is in the folder where you started paw. As the list said, the file does not contain the built-in devices.",
    },
    {
      say = "utau sings notes with lyrics through the engines of OpenUtau. Type `:tutor.try utau` and `<CR>`, and press `o` to add a track. Then type `:utau.voice` and `<CR>` to make it a vocal track.",
      keys = { ":tutor.try utau", "<CR>", "o", ":utau.voice", "<CR>" },
      browser_lacks = "native code for the engines of utau",
      check = function(_, look)
        for _, t in ipairs(paw.tracks()) do
          if look.device(t, "lua:utau") then return loaded("utau") end
        end
      end,
      done = "The track is a vocal track, and it sings when you install `paw-utau-engine` and a voicebank (see extensions/utau/README.md). After that, `\\Vt` adds a vocal track and asks for its singer in one step.",
    },
    {
      say = "Listen to the pattern and the tune. Press `gs` and `<leader><Space>`, and `<leader><Space>` to stop.",
      keys = { "gs", "<leader><Space>", { advance = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.ran(ctx, "transport.start") and look.played(ctx) end,
      done = "You hear the drum pattern and the tune that musicops changed.",
    },
  },
  outro = "We tried one feature of each of pattern, musicops, sections, undotree, mixdiag, interop and utau, and their READMEs describe the rest.",
}
