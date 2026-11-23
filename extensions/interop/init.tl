-- interop: the projects of other programs, opened, brought in and written.
-- Two formats, each a module that `paw.formats` takes through
-- `interop.register`: REAPER projects (.rpp) and DAWproject files
-- (.dawproject: Bitwig Studio, Studio One, Cubase). See README.md beside
-- this file, which shows how to add another.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local interop = require("interop")

interop.register(
  {
    name = "rpp",
    desc = "REAPER projects",
    extensions = {"rpp"},
    project = true,
    module = "interop.rpp",
  }
)

interop.register(
  {
    name = "dawproject",
    desc = "DAWproject files (Bitwig Studio, Studio One, Cubase)",
    extensions = {"dawproject"},
    project = true,
    module = "interop.dawproject",
  }
)
