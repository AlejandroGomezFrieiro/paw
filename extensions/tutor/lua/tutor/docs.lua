-- The course as Markdown, made from the same lesson tables the tutor runs,
-- so the text in `docs/tutorials/course/` cannot say something the tutor does not.
--
--   paw --clean --no-plugins -l extensions/tutor/make-docs.lua    writes docs/tutorials/course/
--
-- The tests compare these with the files on disk.
local M = {}

local GENERATED = "<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->"

--- A file name for a lesson: "05-grammar.md".
function M.file(n, lesson)
  return string.format("%02d-%s.md", n, lesson.id)
end

--- The keys as the default leader reads: `<leader>hn` is `<Space>hn`.
local function keys(text)
  return (text:gsub("`(<[Ll]eader>[^`]*)`", function(code)
    return "`" .. code:gsub("<[Ll]eader>", "<Space>") .. "`"
  end))
end

local function paragraphs(text)
  -- Lines within a paragraph are joined, so that Markdown flows them.
  local out = {}
  for para in (text .. "\n\n"):gmatch("(.-)\n%s*\n") do
    para = para:gsub("%s*\n%s*", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if para ~= "" then out[#out + 1] = para end
  end
  return table.concat(out, "\n\n")
end

function M.lesson(n, lesson, lessons)
  local out = { GENERATED, "", string.format("# Lesson %d: %s", n, lesson.title), "" }
  local function add(line) out[#out + 1] = line end
  add(string.format("*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor %d`.*", n))
  add("")
  if lesson.intro then add(paragraphs(lesson.intro)) add("") end
  if lesson.idea then add("## The idea") add("") add(paragraphs(lesson.idea)) add("") end
  if lesson.vim then add("## If you know Vim") add("") add(paragraphs(lesson.vim)) add("") end
  add("## Steps")
  add("")
  add("The tutor opens a practice project for this lesson. It checks each step when you do it.")
  add("")
  for i, step in ipairs(lesson.steps) do
    add(string.format("%d. %s", i, step.say))
    if step.hint then add("   - *Hint:* " .. step.hint) end
    if step.unchecked then
      add("   - *The tutor cannot check this step* (" .. step.unchecked:gsub("%.$", "") .. "). `<leader>hn` moves to the next step.")
    elseif step.done then
      add("   - ✓ " .. step.done)
    end
  end
  add("")
  if lesson.outro then add("## What we did") add("") add(lesson.outro) add("") end
  local nav = {}
  if lessons[n - 1] then nav[#nav + 1] = string.format("Previous: [%s](%s)", lessons[n - 1].title, M.file(n - 1, lessons[n - 1])) end
  nav[#nav + 1] = "[All lessons](README.md)"
  if lessons[n + 1] then nav[#nav + 1] = string.format("Next: [%s](%s)", lessons[n + 1].title, M.file(n + 1, lessons[n + 1])) end
  add(table.concat(nav, " · "))
  return keys(table.concat(out, "\n")) .. "\n"
end

function M.index(lessons)
  local out = { GENERATED, "", "# The course", "" }
  local function add(line) out[#out + 1] = line end
  add(paragraphs([[
In this course, we use paw to make and change small songs. Each lesson
takes about ten minutes and opens a small practice project of its own. At the
end of each lesson, we hear what we made or changed. The same lessons run in
paw. There, the tutor tells you what to do next and sees when you do it. To
load the tutor, add this line to your configuration:]]))
  add("")
  add("```lua")
  add('paw.ext.load("extensions/tutor")   -- in ~/.config/paw/init.lua, or link the directory into ~/.config/paw/extensions')
  add("```")
  add("")
  add(paragraphs([[
Then type `:tutor` in paw. The tutor makes these pages from its lessons, so
the pages and the tutor give the same steps. [Keys, by idea](../../reference/keys.md)
is a page of keys to keep near the keyboard.]]))
  add("")
  add("| | Lesson | What we do |")
  add("| --- | --- | --- |")
  for n, lesson in ipairs(lessons) do
    local first = (lesson.outro or ""):gsub("|", "\\|")
    add(string.format("| %d | [%s](%s) | %s |", n, lesson.title, M.file(n, lesson), first))
  end
  add("")
  add(paragraphs([[
Lessons 1 to 4 are the base: the screen, the cursor, and how to make tracks
and notes. Lessons 5 to 8 are the grammar of the keys,
which all of paw uses. Lessons 9 to 13 are the studio: devices, the mix, loops,
recordings, and how to save and render. Lessons 14 to 16 help you find keys,
make paw your own, and use the extensions. Lesson 17 edits by line, as Ex
does in Vim: ranges of bars and tracks, `:s` and `:g`.]]))
  add("")
  add(paragraphs([[
The five lessons of [Make music with paw](../make-music/README.md) make one
song, from the first note to an MP3 file. They use the keys of this course.]]))
  return keys(table.concat(out, "\n")) .. "\n"
end

--- Every file of the course: { [name] = text }.
function M.files(lessons)
  local files = { ["README.md"] = M.index(lessons) }
  for n, lesson in ipairs(lessons) do files[M.file(n, lesson)] = M.lesson(n, lesson, lessons) end
  return files
end

return M
