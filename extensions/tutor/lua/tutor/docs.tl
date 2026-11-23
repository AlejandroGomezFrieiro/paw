-- The course as Markdown, made from the same lesson tables the tutor runs,
-- so the text in `docs/tutorials/course/` cannot say something the tutor does not.
--
--   paw --clean --no-plugins -l extensions/tutor/make-docs.lua    writes docs/tutorials/course/
--
-- The tests compare these with the files on disk. The files are one page for
-- each lesson, the index, and one page with every lesson beside a live paw
-- (web/browserpod/site/paw-live.js reads its spans).

--- One item of a step's `keys`: keys to type, or a table that waits, stands in
--- for what a person does away from the keyboard (`sim`, with the keys typed
--- `instead`), or gives the keys when the step starts (`keys`).
local record KeyAction
  wait: integer
  sim: string | function
  instead: {string}
  keys: function(): string
end

local type StepKey = string | KeyAction

local record Step
  say: string
  keys: {StepKey}
  done: string
  hint: string
  unchecked: string
  --- What the step needs that paw in a browser does not have, as the end of
  --- "In the browser, paw has no ...". The page then gives the step a button
  --- that skips it.
  browser_lacks: string
end

local record Lesson
  id: string
  title: string
  intro: string
  idea: string
  vim: string
  outro: string
  --- What the lesson needs that paw in a browser does not have, as the end of
  --- "In the browser, paw has no ...". The page then gives no keys to type.
  browser_lacks: string
  steps: {Step}
end

local record M
  --- The name of the page with every lesson and a live paw.
  page_file: string
end

M.page_file = "in-the-browser.md"

local GENERATED = "<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->"

--- A file name for a lesson: "05-grammar.md".
function M.file(n: integer, lesson: Lesson): string
  return string.format("%02d-%s.md", n, lesson.id)
end

--- The keys as the default leader reads: `<leader>hn` is `<Space>hn`.
local function keys(text: string): string
  return (
    text:gsub(
      "`(<[Ll]eader>[^`]*)`",
      function(code: string): string return "`" .. code:gsub("<[Ll]eader>", "<Space>") .. "`" end
    )
  )
end

local function paragraphs(text: string): string
  -- Lines within a paragraph are joined, so that Markdown flows them.
  local out: {string} = {}
  for para in (text .. "\n\n"):gmatch("(.-)\n%s*\n") do
    para = para:gsub("%s*\n%s*", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if para ~= "" then
      out[#out + 1] = para
    end
  end
  return table.concat(out, "\n\n")
end

--- The lines of a step's hint and result, under line `n` of a list. They are
--- indented as far as the text of the line ("10. " is four characters), or
--- Markdown ends the list there.
local function step_notes(n: integer, step: Step, add: function(string))
  local bullet = string.rep(" ", #tostring(n) + 2) .. "- "
  if step.hint then
    add(bullet .. "*Hint:* " .. step.hint)
  end
  if step.unchecked then
    add(
      bullet
        .. "*The tutor cannot check this step* ("
        .. step.unchecked:gsub("%.$", "")
        .. "). `<leader>hn` moves to the next step."
    )
  elseif step.done then
    add(bullet .. "✓ " .. step.done)
  end
end

function M.lesson(n: integer, lesson: Lesson, lessons: {Lesson}): string
  local out = {GENERATED, "", string.format("# Lesson %d: %s", n, lesson.title), ""}
  local function add(line: string)
    out[#out + 1] = line
  end
  add(
    string.format("*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor %d`.*", n)
  )
  add("")
  if lesson.intro then
    add(paragraphs(lesson.intro))
    add("")
  end
  if lesson.idea then
    add("## The idea")
    add("")
    add(paragraphs(lesson.idea))
    add("")
  end
  if lesson.vim then
    add("## If you know Vim")
    add("")
    add(paragraphs(lesson.vim))
    add("")
  end
  add("## Steps")
  add("")
  add("The tutor opens a practice project for the lesson, and it checks each step when you do it.")
  add("")
  for i, step in ipairs(lesson.steps) do
    add(string.format("%d. %s", i, step.say))
    step_notes(i, step, add)
  end
  add("")
  if lesson.outro then
    add("## What we did")
    add("")
    add(lesson.outro)
    add("")
  end
  local nav: {string} = {}
  if lessons[n - 1] then
    nav[#nav + 1] = string.format("- Previous: [%s](%s)", lessons[n - 1].title, M.file(n - 1, lessons[n - 1]))
  end
  if lessons[n + 1] then
    nav[#nav + 1] = string.format("- Next: [%s](%s)", lessons[n + 1].title, M.file(n + 1, lessons[n + 1]))
  end
  nav[#nav + 1] = "- [All lessons](README.md)"
  add(table.concat(nav, "\n"))
  return keys(table.concat(out, "\n")) .. "\n"
end

function M.index(lessons: {Lesson}): string
  local out = {GENERATED, "", "# The course", ""}
  local function add(line: string)
    out[#out + 1] = line
  end
  add(
    paragraphs(
      [[
In this course, we use paw to make and change small songs. Each lesson
takes about ten minutes and opens a small practice project of its own, and
at the end of each lesson, we hear what we made or changed. The same lessons
run in paw, where the tutor tells you what to do next and checks each step
when you do it. To load the tutor, add this line to your configuration:]]
    )
  )
  add("")
  add("```lua")
  add(
    'paw.ext.load("extensions/tutor")   -- in ~/.config/paw/init.lua, or link the directory into ~/.config/paw/extensions'
  )
  add("```")
  add("")
  add(
    paragraphs(
      [[
Then type `:tutor` in paw. The tutor makes these pages from its lessons, so
the pages and the tutor give the same steps.
[Keys, by idea](../../reference/keys.md) is a page of keys to keep near the
keyboard.]]
    )
  )
  add("")
  add(
    paragraphs(
      [[
You can also do the course without an install.
[The course in your browser](in-the-browser.md) has every lesson on one page,
with paw running beside the steps.]]
    )
  )
  add("")
  add("| | Lesson | What we do |")
  add("| --- | --- | --- |")
  for n, lesson in ipairs(lessons) do
    local first = (lesson.outro or ""):gsub("|", "\\|")
    add(string.format("| %d | [%s](%s) | %s |", n, lesson.title, M.file(n, lesson), first))
  end
  add("")
  add(
    paragraphs(
      [[
Lessons 1 to 4 teach the screen, the cursor, and how to make tracks and
notes. Lessons 5 to 8 teach the grammar of the keys, which all of paw uses.
Lessons 9 to 13 teach devices, the mix, loops and recordings, and how to
save and render. Lessons 14 to 16 help you find keys, make paw your own, and
use the extensions. Lesson 17 edits by line, with ranges
of bars and tracks, `:s` and `:g`.]]
    )
  )
  add("")
  add(
    paragraphs(
      [[
The five lessons of [Make music with paw](../make-music/README.md) make one
song, from the first note to an MP3 file, with the keys of the course.]]
    )
  )
  return keys(table.concat(out, "\n")) .. "\n"
end

-- The page in the browser -------------------------------------------------------------

--- A wait of a step is as long as a test needs. A person listens for two
--- seconds at least, so a wait in the page is never shorter.
local LISTEN_MS = 2000

--- The pause between two parts of a step's keys. The person sees each part
--- happen, and the tutor, which looks a few times a second, sees it too.
local BEAT_MS = 400

--- Text for an attribute in single quotes.
local function attribute(text: string): string
  return (text:gsub("[&<>']", {["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ["'"] = "&#39;"}))
end

local function json_string(text: string): string
  return '"' .. text:gsub('[\\"]', "\\%0") .. '"'
end

--- What the "Type it" button of a step types: a JSON list of key strings and
--- waits in milliseconds. nil when a person must do the step away from the
--- keyboard (a microphone, a MIDI keyboard), or when it has no keys.
local function typed(step: Step): string
  if step.unchecked or step.browser_lacks then
    return '["<leader>hn"]'
  end
  local parts: {string} = {}
  local waited = true -- the last part is a wait, or there is no part yet
  local function wait(ms: integer)
    parts[#parts + 1] = tostring(ms)
    waited = true
  end
  local function type_keys(text: string)
    if not waited then
      wait(BEAT_MS)
    end
    parts[#parts + 1] = json_string(text)
    waited = false
  end
  for _, item in ipairs(step.keys) do
    if item is string then
      type_keys(item)
    elseif item.wait then
      wait(math.max(item.wait, LISTEN_MS))
    elseif item.sim == "quit" then
      type_keys(table.concat(item.instead, ""))
    else
      -- A step done away from the keyboard, or keys made when it starts.
      return nil
    end
  end
  if #parts == 0 then
    return nil
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

--- The state of paw where a lesson starts, for `PawPod.open`: the lesson,
--- with its introduction closed (the page shows it already).
local function lesson_state(n: integer): string
  return string.format('{"lesson":%d,"keys":"<Esc>"}', n)
end

local function page_lesson(n: integer, lesson: Lesson, add: function(string))
  local state = attribute(lesson_state(n))
  add(string.format("## Lesson %d: %s", n, lesson.title))
  add("")
  if lesson.intro then
    add(paragraphs(lesson.intro))
    add("")
  end
  if lesson.browser_lacks then
    add(string.format("In the browser, paw has no %s, so do the lesson in paw on your computer.", lesson.browser_lacks))
    add("")
  else
    add(string.format("<span data-paw-open='%s' data-paw-label='Open lesson %d in paw'></span>", state, n))
    add("")
  end
  for i, step in ipairs(lesson.steps) do
    local line = string.format("%d. %s", i, step.say)
    if step.browser_lacks and not lesson.browser_lacks then
      line = line .. string.format(" In the browser, paw has no %s, so skip the step.", step.browser_lacks)
    end
    local typing = not lesson.browser_lacks and typed(step)
    if typing then
      local label = (step.unchecked or step.browser_lacks) and "Next step" or "Type it"
      line = line
        .. string.format(
          " <span data-paw-keys='%s' data-paw-state='%s' data-paw-label='%s'></span>", attribute(typing), state, label
        )
    end
    add(line)
    step_notes(i, step, add)
  end
  add("")
  if lesson.outro then
    add(lesson.outro)
    add("")
  end
  add(
    string.format(
      "[Lesson %d](%s) has the same steps with the idea of the lesson and notes for Vim users.", n, M.file(n, lesson)
    )
  )
  add("")
end

--- Every lesson on one page, beside a live paw in the browser.
function M.page(lessons: {Lesson}): string
  local out = {GENERATED, "", "# The course in your browser", ""}
  local function add(line: string)
    out[#out + 1] = line
  end
  add(
    paragraphs(
      [[
In this course, we make and change small songs with paw, and paw runs
here, beside the steps. Each lesson takes about ten minutes and opens
a practice project of its own. The tutor at the bottom of paw tells you
what to do next, and it checks each step when you do it.]]
    )
  )
  add("")
  add("## How to use the page")
  add("")
  add(
    paragraphs(
      [[
First, press "Start paw" beside the lessons, and after a few seconds paw
shows a short song. Second, press the button of a lesson, and paw opens
the practice project of the lesson. Third, do each step. You can click
paw and type the keys of the step, or you can press "Type it" beside the
step, and the page types the keys for you.]]
    )
  )
  add("")
  add(
    paragraphs(
      [[
When you press "Start paw", your browser loads BrowserPod from
browserpod.io, about 6 MB, and paw from this site, about 26 MB. BrowserPod
runs Linux programs in a browser tab, and it runs paw here. Nothing loads
before you press the button, and nothing that you type leaves your
browser. The page works best in Chromium, on a screen that is wide enough
for paw to show beside the lessons.]]
    )
  )
  add("")
  local lacking: {string} = {}
  for n, lesson in ipairs(lessons) do
    if lesson.browser_lacks then
      lacking[#lacking + 1] = tostring(n)
    end
  end
  if #lacking > 0 then
    add(
      string.format(
        "paw in the browser has no plugins, no MIDI ports and no sound input, so the page gives no keys for lesson %s.",
        table.concat(lacking, " and ")
      )
    )
    add("")
  end
  add("## Do the course on your computer")
  add("")
  add("1. Install paw, as [How to install paw with Nix](../../how-to/install-paw.md) shows.")
  add("2. Start paw, type `:ext.load tutor` and press Enter.")
  add("3. Type `:tutor 1` and press Enter, and lesson 1 starts.")
  add("")
  add(
    paragraphs(
      [[
The tutor keeps your place, so `:tutor` starts the next lesson the next
time. [The course](README.md) has a page for each lesson.]]
    )
  )
  add("")
  add('<div class="paw-course">')
  add('<div class="paw-live" data-paw-live data-paw-worker="../../../coi-sw.js"></div>')
  add('<div class="paw-course-text">')
  add("")
  for n, lesson in ipairs(lessons) do
    page_lesson(n, lesson, add)
  end
  add("</div>")
  add("</div>")
  add("")
  add('<script type="module" src="../../../pod/paw-live.js"></script>')
  return keys(table.concat(out, "\n")) .. "\n"
end

--- Every file of the course: { [name] = text }.
function M.files(lessons: {Lesson}): {string: string}
  local files = {["README.md"] = M.index(lessons), [M.page_file] = M.page(lessons)}
  for n, lesson in ipairs(lessons) do
    files[M.file(n, lesson)] = M.lesson(n, lesson, lessons)
  end
  return files
end

return M
