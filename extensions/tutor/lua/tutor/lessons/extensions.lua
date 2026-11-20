-- Lesson 16: what each bundled extension adds, one thing to try in each.
local function loaded(name)
  return paw.ext.loaded[name] ~= nil and paw.ext.loaded[name].ok
end

return {
  id = "extensions",
  title = "The bundled extensions",
  intro = [=[
In this lesson, we load seven of the extensions that come with paw, and we
try one feature of each.

Extensions give much of what paw can do. An extension is a folder of Lua in
`extensions/` next to the program. It uses the same `paw` module as your
`init.lua`. `:tutor.try` loads an extension for this session only. To load an
extension each time, link its folder into `~/.config/paw/extensions`.

The README.md of each extension tells all that it does. Each extension has
its keys under its own prefix. These are `]]` `[[` and `,S` (sections), `gz`
(musicops) and `,t` (pattern). They are also `,x` and `]d` `[d` (mixdiag),
`,u` `g-` `g+` (undotree) and `,V` (utau).]=],
  idea = [[
An extension adds commands, keys, text objects, operators and views with the
functions of lesson 15. So its additions obey the grammar that you know.
Sections are text objects (`dis`, `yis`), and musicops are operators
(`gzkip`). `.`, counts and macros work with them.]],
  vim = [[
`:tutor.try name` is like `:packadd`. `:extensions` shows the loaded
extensions.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_track({ name = "Drums", volume = -6 })
    drums:add_device("drums")
    local keys = paw.add_track({ name = "Keys", volume = -8 })
    keys:add_device("synth", { wave = 1, attack = 0.01, release = 0.3, cutoff = 2200 })
    keys:add_clip({ name = "tune", start = 0, length = 8, notes = look.notes("C4:0:1 D4:1:1 E4:2:1 G4:3:1 E4:4:1 D4:5:1 C4:6:2") })
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 8, true
  end,
  at = function() paw.cursor.set_track(paw.track("Drums")) end,
  test = {
    after = function() os.remove("tutor-song.rpp") end,
  },
  steps = {
    {
      say = "pattern writes drum parts as text. Type `:tutor.try pattern` and `<CR>`. Then type `:pattern.set bd*2 [~ sn]` and `<CR>`. A new clip on Drums plays the pattern.",
      keys = { ":tutor.try pattern", "<CR>", ":pattern.set bd*2 [~ sn]", "<CR>" },
      check = function(_, look)
        local clip = look.clips("Drums")[1]
        return loaded("pattern") and clip and #clip:notes() > 0
      end,
      done = "The clip plays kick, kick, rest, snare. `,tt` edits the text of the clip under the cursor.",
    },
    {
      say = "musicops adds musical operators under `gz`. Type `:tutor.try musicops` and `<CR>`. Press `j` to go to Keys. Press `gzkic` to move each note of the clip one step up the scale.",
      keys = { ":tutor.try musicops", "<CR>", "j", "gzkic" },
      check = function(_, look)
        return loaded("musicops") and look.melody(look.clip("Keys")) == "62@0+1 64@1+1 65@2+1 69@3+1 65@4+1 64@5+1 62@6+2"
      end,
      done = "The tune is D E F A F E D now. It moved in C major. `gzh` humanizes, `gzs` strums, and `.` repeats them.",
    },
    {
      say = "sections gives names to the parts of a song. Type `:tutor.try sections` and `<CR>`. Press `,Sa`, type `Verse` and press `<CR>` to mark a section at the cursor.",
      keys = { ":tutor.try sections", "<CR>", ",Sa", "Verse", "<CR>" },
      check = function()
        if not loaded("sections") then return false end
        for _, s in ipairs(require("sections").list()) do
          if s.name == "Verse" then return true end
        end
      end,
      done = "Verse shows on the ruler. `is` is now a text object: `yis` yanks the section on all tracks, and `]]` goes to the next section.",
    },
    {
      say = "undotree shows each state of the project. Type `:tutor.try undotree` and `<CR>`. Press `,uu` to open the undo tree. Look at it, then press `q` to close it.",
      keys = { ":tutor.try undotree", "<CR>", ",uu", "q" },
      check = function(ctx, look)
        if look.float() == "undotree" then ctx.seen = true end
        return loaded("undotree") and ctx.seen and not look.float()
      end,
      done = "paw keeps each change that you undo. `g-` and `g+` move through time, across branches.",
    },
    {
      say = "mixdiag measures the mix and shows problems. Type `:tutor.try mixdiag` and `<CR>`. Then press `,xa` to measure the song.",
      keys = { ":tutor.try mixdiag", "<CR>", ",xa" },
      check = function(ctx, look) return loaded("mixdiag") and look.ran(ctx, "mix.analyze") end,
      done = "mixdiag measures in the background. The message line shows the loudness when it is complete, and `,xx` shows the problems that it found.",
    },
    {
      say = "interop opens and writes REAPER projects and DAWproject files. Type `:tutor.try interop` and `<CR>`. Then type `:export tutor-song.rpp` and `<CR>`. A list of the items that REAPER cannot use opens. Press `q` to close it.",
      keys = { ":tutor.try interop", "<CR>", ":export tutor-song.rpp", "<CR>", "q" },
      check = function(ctx, look) return loaded("interop") and look.ran(ctx, "export") and not look.float() end,
      done = "tutor-song.rpp is in the folder where you started paw. As the list told you, the file does not contain the built-in devices.",
    },
    {
      say = "utau sings notes with lyrics through the engines of OpenUtau. Type `:tutor.try utau` and `<CR>`. Press `o` to add a track. Then type `:utau.voice` and `<CR>` to make it a vocal track.",
      keys = { ":tutor.try utau", "<CR>", "o", ":utau.voice", "<CR>" },
      check = function(_, look)
        for _, t in ipairs(paw.tracks()) do
          if look.device(t, "lua:utau") then return loaded("utau") end
        end
      end,
      done = "The track is a vocal track. It sings when you install `paw-utau-engine` and a voicebank (see extensions/utau/README.md). Then `,Vt` adds a vocal track and asks for its singer in one step.",
    },
    {
      say = "Listen to the pattern and the tune. Press `gs` and `<Space>`, and `<Space>` to stop.",
      keys = { "gs", "<Space>", { wait = 300 }, "<Space>" },
      check = function(ctx, look) return look.ran(ctx, "transport.start") and look.played(ctx) end,
      done = "You hear the drum pattern and the tune that musicops changed.",
    },
  },
  outro = "We tried one feature of pattern, musicops, sections, undotree, mixdiag, interop and utau. Their READMEs tell the rest.",
}
