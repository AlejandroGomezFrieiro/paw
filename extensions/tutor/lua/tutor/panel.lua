-- The tutor's panel along the bottom of the screen: what to do next, what
-- was just done, a hint when asked for, and the tutor's own keys.
local api = paw.api
local M = {}

M.height = 9

paw.ui.hl("TutorDone", { fg = "#9ece6a", bold = true })
paw.ui.hl("TutorKey", { fg = "#ff9e64", bold = true })
paw.ui.hl("TutorText", { fg = "#c0caf5" })
paw.ui.hl("TutorHint", { fg = "#e0af68" })
paw.ui.hl("TutorDim", { fg = "#565f89" })

--- Write keys the way the learner's leaders read: the lessons write the
--- default `,` and `\`, so `,hh` becomes `<space>hh` when the leader is a
--- space, and `\Sa` follows the local leader the same way.
function M.keys(text)
  local leader, localleader = paw.opt.leader, paw.opt.localleader
  if leader == "," and localleader == "\\" then return text end
  return (text:gsub("`([^`]*)`", function(code)
    if #code > 1 then
      local first = code:sub(1, 1)
      if first == "," then
        code = leader .. code:sub(2)
      elseif first == "\\" then
        code = localleader .. code:sub(2)
      end
    end
    return "`" .. code .. "`"
  end))
end

--- Split text into words, each with a style (`code` in the key style) and
--- whether a space comes before it.
local function words(text, style)
  local out = {}
  local pos = 1
  while pos <= #text do
    local s, e = text:find("`[^`]*`", pos)
    local plain = text:sub(pos, (s or #text + 1) - 1)
    for space, word in plain:gmatch("(%s*)(%S+)") do
      out[#out + 1] = { text = word, style = style, space = space ~= "" }
    end
    if not s then break end
    out[#out + 1] = { text = text:sub(s + 1, e - 1), style = "TutorKey", space = s > 1 and text:sub(s - 1, s - 1):match("%s") ~= nil }
    pos = e + 1
  end
  return out
end

--- Lay styled words out in lines of at most `width` columns. A word that
--- follows another without a space stays on its line.
local function wrap(list, width)
  local lines, line, used = {}, {}, 0
  for _, w in ipairs(list) do
    local len = api.str_width(w.text)
    local gap = (used > 0 and w.space) and 1 or 0
    if used > 0 and w.space and used + gap + len > width then
      lines[#lines + 1], line, used, gap = line, {}, 0, 0
    end
    line[#line + 1] = { text = w.text, style = w.style, x = used + gap }
    used = used + gap + len
  end
  if #line > 0 then lines[#lines + 1] = line end
  return lines
end

--- The panel's paragraphs: { text, style }.
function M.paragraphs()
  local tutor = require("tutor")
  local S = tutor.state()
  local out = {}
  local function add(text, style) out[#out + 1] = { text = M.keys(text), style = style or "TutorText" } end
  if not S.active then return out end
  local lesson, step, index = tutor.current()
  lesson = lesson or tutor.by_id[S.lesson]
  if not lesson then
    add("This lesson is no longer there. `:tutor list` shows the lessons.")
    return out
  end
  if S.paused then
    add("This is not the lesson's project, so the tutor is waiting. `:tutor` goes back to the lesson, `,hq` leaves the tutor.", "TutorHint")
    return out
  end
  if S.just_done then add("✓ " .. S.just_done, "TutorDone") end
  if S.finished then
    if lesson.outro then add(lesson.outro) end
    local n = tutor.number(lesson)
    local following = tutor.lessons[n + 1]
    if following then
      add(string.format("Lesson done. `,hn` goes on to lesson %d, %s; `,hl` lists the lessons; `,hq` leaves the tutor; `:help course-%d` is this lesson to read again.", n + 1, following.title, n))
    else
      add("That was the last lesson. `,hl` lists them all; `,hq` leaves the tutor.")
    end
    return out
  end
  if not step then return out end
  add(step.say)
  if step.unchecked then
    add("The tutor cannot see this one happen: press `,hn` when you have done it.", "TutorDim")
  end
  if S.hint then add("Hint: " .. (step.hint or "Do exactly the keys shown, in order. `,hr` starts the lesson again."), "TutorHint") end
  if S.error then add("The tutor's check failed: " .. S.error, "Error") end
  return out
end

local view = { focusable = false }

function view:render(buf)
  local tutor = require("tutor")
  local S = tutor.state()
  local lesson, step, index = tutor.current()
  lesson = lesson or tutor.by_id[S.lesson or ""]
  local title = "Tutor"
  if lesson then
    title = string.format("Tutor · lesson %d of %d: %s", tutor.number(lesson), #tutor.lessons, lesson.title)
    if step then title = title .. string.format(" · step %d of %d", index, #lesson.steps) end
  end
  local inner = paw.ui.box(buf, title, "BorderFocus")
  local w, h = inner.width, inner.height
  local y = 0
  local body_rows = h - 1
  local rows = {}
  for _, para in ipairs(M.paragraphs()) do
    for _, line in ipairs(wrap(words(para.text, para.style), w - 2)) do rows[#rows + 1] = line end
  end
  -- When it does not all fit, what was just done gives way to what to do.
  while #rows > body_rows and #rows > 0 and S.just_done do
    table.remove(rows, 1)
    if not rows[1] or rows[1][1].style ~= "TutorDone" then break end
  end
  for _, line in ipairs(rows) do
    if y >= body_rows then break end
    for _, piece in ipairs(line) do inner:text(1 + piece.x, y, piece.text, piece.style) end
    y = y + 1
  end
  local footer = "`,hh` hint · `,hn` skip · `,hr` restart · `,hl` lessons · `,hq` leave"
  -- The lesson's page of help, where there is room for it.
  local page = lesson and string.format(" · `:help course-%d` the lesson to read", tutor.number(lesson))
  if page and api.str_width((footer .. page):gsub("`", "")) < w - 2 then footer = footer .. page end
  footer = M.keys(footer)
  local x = 1
  for _, word in ipairs(words(footer, "TutorDim")) do
    if word.space and x > 1 then x = x + 1 end
    x = x + inner:text(x, h - 1, word.text, word.style == "TutorKey" and "TutorKey" or "TutorDim")
  end
end

paw.ui.view("tutor", view)

function M.show()
  if not paw.ui.visible("tutor") then paw.ui.dock("tutor", { side = "bottom", size = M.height }) end
  paw.ui.show("tutor")
end

function M.hide()
  if paw.ui.visible("tutor") then paw.ui.hide("tutor") end
end

--- The panel as lines of text, for tests and for reading.
function M.text()
  local lines = {}
  for _, para in ipairs(M.paragraphs()) do lines[#lines + 1] = para.text end
  return table.concat(lines, "\n")
end

M.words, M.wrap = words, wrap
return M
