-- The heads of the core (paw/heads.tl), made of the pieces of
-- paw/heads/pieces.tl: the default head of a part, and the master's.
-- A user replaces one with a head of the same name in init.lua:
--
--   paw.heads.define("default", { render = paw.heads.compose({ ... }) })
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
require("paw.heads.pieces")

local heads = require("paw.heads")

-- A part: its badge and name, then the volume on one row, the bake, the
-- automation and the chips; under them the input's button and the meter,
-- then the route, the sends and the input, as many as there are rows for.
heads.builtin(
  "default",
  {
    title = "Part",
    render = heads.compose(
      {
        {left = {"badge", "name"}, right = {"volume", "bake", "automation", "chips"}},
        {left = {"input_button", "meter"}, right = {}},
        "route",
        "sends",
        "input",
      }
    ),
  }
)

-- The master: its name, the volume on one row and the automation, then
-- its meter, with both sides, and its route.
heads.builtin(
  "master",
  {
    title = "Master",
    render = heads.compose(
      {
        {left = {"name"}, right = {"volume", "automation"}},
        "meter",
        "route",
        "sends",
      }
    ),
  }
)

return heads
