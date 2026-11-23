-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
-- It waits for its first use. Its lesson on extensions uses musicops,
-- sections and undotree when they are there (`:tutor.try` loads them).
return {
  name = "tutor",
  version = "0.1.0",
  description = "A course for first-time users, inside the program",
  requires = { paw = "^1.0" },
  optional = { musicops = "*", sections = "*", undotree = "*" },
  needs = {},
  cmd = {
    { "tutor", desc = "The course: where you left off, or `tutor 3`, `tutor list`" },
    { "tutor!", desc = "Start a lesson even if the open project has unsaved changes, which are lost" },
    "tutor.*",
  },
  keys = {
    { "<leader>hh", desc = "Tutor: a hint" },
    { "<leader>hl", desc = "Tutor: the lessons" },
    { "<leader>hn", desc = "Tutor: skip this step, or go on to the next lesson" },
    { "<leader>hq", desc = "Tutor: leave, and reopen your project" },
    { "<leader>hr", desc = "Tutor: start the lesson again" },
  },
  view = "tutor",
}
