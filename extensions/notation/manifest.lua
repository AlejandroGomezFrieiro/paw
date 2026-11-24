-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
-- It waits for its first use: a score is slow to load and a view over MIDI,
-- so a project plays without it (docs/reference/extensions.md, "Load on first use").
return {
  name = "notation",
  version = "0.1.0",
  description = "A MIDI clip as staff notation, read and edited in the terminal and in a window",
  requires = { paw = "^1.0" },
  needs = {},
  cmd = {
    { "notation", desc = "Show the clip under the cursor as notation, to read and edit" },
    { "score", desc = "Show a score to edit, a staff for each part with MIDI" },
    { "part", desc = "Show a part to play from, to edit as it is written" },
    "notation.*",
    "score.*",
    "part.*",
  },
  keys = {
    { "<leader>nn", desc = "Show the clip under the cursor as notation" },
    { "<leader>vn", desc = "Show the clip under the cursor as notation" },
    { "<leader>ns", desc = "Show every part with MIDI as a score, a staff each" },
    { "<leader>nc", desc = "Show the score's pages as they will be exported, to check them" },
    { "<leader>ne", desc = "Export the clip as MusicXML, a file named after it" },
    { "<leader>nE", desc = "Export the clip as an engraved PDF, a file named after it" },
    { "<localleader>n", view = "arrange", desc = "Show the clip as notation" },
    { "<localleader>n", view = "pianoroll", desc = "Show this clip as notation" },
  },
  view = "notation",
}
