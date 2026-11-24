-- The default commands and key mappings, one file for each area in
-- paw/defaults/. They use nothing but the public `paw` module: anything
-- there can be redefined from `init.lua` with the same calls. The order
-- counts: a later part maps keys over an earlier one's.
for _, part in ipairs({
  "transport",
  "cursor",
  "parts",
  "clips",
  "devices",
  "automation",
  "views",
  "project",
  "modal",
  "keys",
  "sizes",
  "values",
  "lanes",
  "pickers",
}) do
  require("paw.defaults." .. part)
end
