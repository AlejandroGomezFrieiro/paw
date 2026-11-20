-- Write the course as Markdown into docs/tutorials/course/, from the tutor's lessons.
--
--   paw --clean --no-plugins -l extensions/tutor/make-docs.lua [dir]
--
-- Run it from the top of the repository after changing a lesson; the tests
-- fail while the files and the lessons disagree. keys.md is written by hand.
paw.opt.tutor_dir = (os.getenv("TMPDIR") or "/tmp") .. "/paw-tutor-docs"
paw.ext.load("extensions/tutor")
local tutor = require("tutor")
local docs = require("tutor.docs")
local dir = ... or "docs/tutorials/course"
pcall(paw.api.fs_mkdir, dir)
local n = 0
for name, text in pairs(docs.files(tutor.lessons)) do
  local file = assert(io.open(dir .. "/" .. name, "w"))
  file:write(text)
  file:close()
  n = n + 1
end
print(string.format("wrote %d files to %s", n, dir))
paw.api.quit(0)
