-- The commands git runs for projects: a script for `paw -l`, so that it runs
-- in a kernel without a window and ends. See README.md for how to set it up.
--
--   paw -l git.lua textconv <file>
--       prints the project as stable text, for `diff.paw.textconv`
--   paw -l git.lua merge <base> <ours> <theirs> [marker-size] [path]
--       merges the three versions into <ours>, for `merge.paw.driver`;
--       the exit code is 1 when there are conflicts left in the result
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
package.path = here .. "/lua/?.lua;" .. here .. "/lua/?/init.lua;" .. package.path

local projdiff = require("projdiff")
local command, a, b, c = ...

local function fail(message)
  io.stderr:write("paw: ", message, "\n")
  paw.api.quit(2)
end

if command == "textconv" then
  local doc, err = projdiff.file(a or "")
  if not doc then return fail(err) end
  io.write(projdiff.text.text(doc.project))
  paw.api.quit(0)
elseif command == "merge" then
  local base = projdiff.file(a or "")
  -- A project added on both sides has no common version.
  if not base then base = nil end
  local ours, ours_err = projdiff.file(b or "")
  if not ours then return fail(ours_err) end
  local theirs, theirs_err = projdiff.file(c or "")
  if not theirs then return fail(theirs_err) end
  local merged, conflicts = projdiff.merge.files(base, ours, theirs)
  local ok, content = pcall(paw.api.project_file_text, merged)
  if not ok then return fail("the merge is not a project that loads: " .. tostring(content):match("[^\n]*")) end
  local file, open_err = io.open(b, "wb")
  if not file then return fail(tostring(open_err)) end
  file:write(content)
  file:close()
  paw.api.quit(#conflicts > 0 and 1 or 0)
else
  fail("usage: git.lua textconv <file> | git.lua merge <base> <ours> <theirs>")
end
