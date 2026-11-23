-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
-- It waits for its first use.
return {
  name = "mixdiag",
  version = "0.1.0",
  description = "The mix measured (LUFS, true peak, phase) and reported as findings to jump to",
  requires = { paw = "^1.0" },
  needs = {},
  cmd = {
    { "mix.analyze", desc = "Measure the mix and list what is wrong" },
    { "mix.file", desc = "Measure an audio file: `mix.file master.wav`" },
    { "mix.report", desc = "The mix report: the loudness, peaks and range measured, and the findings to go to" },
    "mix.*",
  },
  keys = {
    { "<leader>ma", mode = { "n", "x" }, desc = "Measure the mix (the selection in visual mode)" },
    { "<leader>mk", desc = "Measure the cursor track's contribution" },
    { "<leader>ml", desc = "Measure the loop" },
    { "<leader>mr", desc = "The mix report" },
    { "<leader>mp", desc = "The painted report (pixels, where the terminal shows them)" },
  },
  view = { "mixdiag", "mixdiag_strip" },
}
