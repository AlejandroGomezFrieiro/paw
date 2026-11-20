-- The bottom row: a prompt while typing a command or answering a question,
-- otherwise the latest message.
local api = paw.api
local M = {}

local active      -- { prompt, chars, pos, on_submit, complete, preview, note, history, index, matches, match, anchor, on_key, ghost }
local histories = {}
-- A prompt open in one seat is that seat's; the history is everyone's.
paw.seats.keep("cmdline", function() return active end, function(a) active = a end, function() return nil end)

local function text()
  return table.concat(active.chars)
end

local function set_text(value)
  active.chars = {}
  for ch in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do active.chars[#active.chars + 1] = ch end
  active.pos = #active.chars
end

--- Tell the preview what the line is now (nil when the prompt closes),
--- and keep the few words it says back.
local function preview(value)
  local a = active
  if not (a and a.preview) then return end
  local ok, note, level = pcall(a.preview, value)
  a.note, a.note_level = ok and note or nil, ok and level or nil
end

local function finish(submit)
  local state, value = active, text()
  preview(nil)
  active = nil
  paw.ui.grabber = nil
  paw.keymap.set_mode(state.back or "n")
  api.ui_redraw()
  if submit and state.on_submit then
    if value ~= "" and state.history[#state.history] ~= value then table.insert(state.history, value) end
    -- What the answer changes is an undo step named by the question.
    if state.label then api.undo_label(state.label) end
    state.on_submit(value)
  end
end

--- Candidates as `{ text, label, desc }`: a completer may give plain
--- strings, each the whole text it would make.
local function candidates()
  local ok, list = pcall(active.complete, text())
  local out = {}
  for _, c in ipairs(ok and type(list) == "table" and list or {}) do
    if type(c) == "table" then
      local t = tostring(c.text or c[1])
      out[#out + 1] = { text = t, label = c.label or t, desc = c.desc }
    else
      out[#out + 1] = { text = tostring(c), label = tostring(c) }
    end
  end
  return out
end

--- Work out what could finish the text as it is now; nothing is chosen yet.
local function refresh()
  if not active.complete then return end
  local matches = candidates()
  -- One candidate that is what is typed already has nothing to offer.
  if #matches == 1 and matches[1].text == text() then matches = {} end
  active.matches, active.match = matches, 0
end

--- Move through the candidates, putting the one chosen in the line.
local function complete(step)
  if not active.complete then return end
  if not active.matches then refresh() end
  local n = #active.matches
  if n == 0 then return end
  active.match = (active.match - 1 + step) % n + 1
  local matches, match = active.matches, active.match
  set_text(matches[match].text)
  active.matches, active.match = matches, match
end

local function on_key(key, pasted)
  local a = active
  -- Text a prompt came with is selected: the first key typed replaces it, a
  -- key that deletes clears it, and a motion key takes the selection off.
  local selected = a.selected
  a.selected = false
  if selected and (pasted or key == "<Space>" or key == "<lt>" or not key:match("^<.+>$")
    or key == "<BS>" or key == "<Del>" or key == "<C-u>" or key == "<C-w>") then
    set_text("")
    if key == "<BS>" or key == "<Del>" or key == "<C-u>" or key == "<C-w>" then
      if a.complete then refresh() end
      preview(text())
      return api.ui_redraw()
    end
  elseif selected and (key == "<Left>" or key == "<Home>" or key == "<C-a>") then
    a.pos = 0
    return api.ui_redraw()
  end
  if pasted then
    for ch in key:gsub("[\r\n]", " "):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      a.pos = a.pos + 1
      table.insert(a.chars, a.pos, ch)
    end
    preview(text())
    return api.ui_redraw()
  end
  local keep_matches = false
  local chosen = a.matches and a.matches[a.match]
  -- The prompt's own keys first: a lyric's Space puts the syllable down
  -- and goes on to the next note with the prompt still open.
  if a.on_key then
    local ok, took = pcall(a.on_key, key, text())
    if ok and took ~= nil and active == a then
      if type(took) == "string" then
        set_text(took)
        a.matches = nil
      end
      preview(text())
      return api.ui_redraw()
    end
  end
  if key == "<CR>" then
    -- A directory chosen from the list is gone into rather than run.
    if chosen and chosen.label:match("/$") then
      refresh()
      return api.ui_redraw()
    end
    return finish(true)
  elseif key == "<Esc>" or key == "<C-c>" then
    return finish(false)
  elseif key == "<Tab>" or key == "<S-Tab>" or key == "<C-n>" or key == "<C-p>"
    or (chosen and (key == "<Down>" or key == "<Up>")) then
    complete((key == "<Tab>" or key == "<C-n>" or key == "<Down>") and 1 or -1)
    keep_matches = true
  elseif key == "<BS>" then
    if #a.chars == 0 then return finish(false) end
    if a.pos > 0 then
      table.remove(a.chars, a.pos)
      a.pos = a.pos - 1
    end
  elseif key == "<Del>" then
    table.remove(a.chars, a.pos + 1)
  elseif key == "<Left>" then
    a.pos = math.max(0, a.pos - 1)
  elseif key == "<Right>" then
    a.pos = math.min(#a.chars, a.pos + 1)
  elseif key == "<Home>" or key == "<C-a>" then
    a.pos = 0
  elseif key == "<End>" or key == "<C-e>" then
    a.pos = #a.chars
  elseif key == "<C-u>" then
    set_text("")
  elseif key == "<C-w>" then
    while a.pos > 0 and a.chars[a.pos] == " " do
      table.remove(a.chars, a.pos)
      a.pos = a.pos - 1
    end
    while a.pos > 0 and a.chars[a.pos] ~= " " do
      table.remove(a.chars, a.pos)
      a.pos = a.pos - 1
    end
  elseif key == "<Up>" or key == "<Down>" then
    local h = a.history
    a.index = paw.util.clamp((a.index or #h + 1) + (key == "<Up>" and -1 or 1), 1, #h + 1)
    set_text(h[a.index] or "")
  else
    local ch = key == "<Space>" and " " or key == "<lt>" and "<" or key
    if not ch:match("^<.+>$") then
      a.pos = a.pos + 1
      table.insert(a.chars, a.pos, ch)
    end
  end
  if not keep_matches then
    a.matches = nil
    -- The list follows what is typed, once there is something typed.
    if a.complete and #a.chars > 0 and key ~= "<Up>" and key ~= "<Down>" then refresh() end
  end
  preview(text())
  api.ui_redraw()
end

--- Start a prompt. `opts`: `prompt`, `text` (initial), `complete(text)` which
--- returns what the text could become, and `history` (a name; prompts with
--- the same name share their history), `label` (what the undo step the
--- answer makes is called; by default the prompt), `preview(text)` (called
--- as the text changes, and with nil when the prompt closes; it may return
--- a few words to show at the right end, and "error" as a second value when
--- they say what is wrong; `on_change` is another name for it), `anchor()`
--- (where to draw the prompt: `{ x, y }` in cells of the screen, beside
--- what it is about, or nil for the bottom row), `on_key(key, text)` (a
--- key the prompt handles itself before the line does: it returns true
--- when it took the key, or the new text of the line), `mode` (the mode to
--- go back to when it closes, "n" unless said), `ghost` (examples shown
--- dimly in the empty line). `text` comes selected, so
--- that typing replaces it (`select = false` keeps it to be added to; so
--- does the `:` line). Candidates are strings, or
--- `{ text = whole line, label = the part shown, desc = ... }`. They are
--- listed above the prompt as it is typed; Tab and Shift-Tab (or Ctrl-n,
--- Ctrl-p) choose one into the line, Enter runs the line.
function M.open(opts, on_submit)
  opts = opts or {}
  local name = opts.history or opts.prompt or ""
  histories[name] = histories[name] or {}
  active = {
    prompt = opts.prompt or "", on_submit = on_submit, complete = opts.complete, preview = opts.preview or opts.on_change,
    anchor = opts.anchor, on_key = opts.on_key, back = opts.mode, ghost = opts.ghost,
    label = opts.label or (opts.prompt or ""):match("^(%a[^:]*%a)"),
    history = histories[name], history_name = name, chars = {}, pos = 0,
  }
  set_text(opts.text or "")
  active.selected = #active.chars > 0 and opts.select ~= false and opts.prompt ~= ":"
  if #active.chars > 0 then preview(text()) end
  paw.ui.grabber = on_key
  paw.keymap.set_mode("c")
  api.ui_redraw()
end

--- Ask a question answered with one key, as Vim's `:s///c` does: the
--- prompt shows until a key is typed, and `on_key(key)` gets it (`<Esc>`
--- too). It may ask again.
function M.ask_key(prompt, on_key)
  active = { prompt = prompt, chars = {}, pos = 0, history = {}, single = true }
  paw.ui.grabber = function(key)
    if active and active.single then
      active = nil
      paw.ui.grabber = nil
      paw.keymap.set_mode("n")
    end
    on_key(key)
    api.ui_redraw()
  end
  paw.keymap.set_mode("c")
  api.ui_redraw()
end

--- Where an anchored prompt is drawn now, `{ x, y }` in cells, or nil.
local function anchored(a)
  if not (a and a.anchor) then return nil end
  local ok, at = pcall(a.anchor)
  if ok and type(at) == "table" and at.x and at.y then return at end
end

--- The prompt that is open, for a frontend that draws its own: what it asks,
--- the text so far, and how many characters of it are before the cursor;
--- `anchored` when it is drawn beside what it is about.
function M.state()
  if not active then return nil end
  return {
    prompt = active.prompt, before = table.concat(active.chars, "", 1, active.pos),
    after = table.concat(active.chars, "", active.pos + 1), selected = active.selected or nil,
    matches = active.matches, match = active.match, note = active.note, note_level = active.note_level,
    anchored = active.anchor ~= nil, history = active.history_name, ghost = active.ghost,
  }
end

--- Add a line to a prompt's history, as if typed there.
function M.remember(name, line)
  histories[name] = histories[name] or {}
  local h = histories[name]
  if line ~= "" and h[#h] ~= line then h[#h + 1] = line end
end

local MAX_ROWS = 10

--- A description in the list: its first line, without the examples.
local function brief(desc)
  return (desc:match("^[^\n]*"):gsub(":? `.*$", ""))
end

--- The list of candidates, over the bottom of the screen immediately above
--- the command line. It starts below the word that they complete.
function M.draw_popup(buf)
  local a = active
  local at = anchored(a)
  if at then return M.draw_anchored(buf, a, at) end
  if not (a and a.matches and #a.matches > 0) then return end
  local n = #a.matches
  local rows = math.min(MAX_ROWS, n, buf.height - 2)
  if rows < 1 then return end
  local top = 1
  if a.match > rows then top = a.match - rows + 1 end
  local label_w, desc_w = 0, 0
  for i = top, top + rows - 1 do
    local c = a.matches[i]
    label_w = math.max(label_w, api.str_width(c.label))
    if c.desc and c.desc ~= "" then desc_w = math.max(desc_w, api.str_width(brief(c.desc))) end
  end
  label_w = math.min(label_w, math.max(8, math.floor(buf.width / 2) - 4))
  desc_w = math.min(desc_w, 56)
  local width = 2 + label_w + (desc_w > 0 and 2 + desc_w or 0) + 2
  width = math.min(width, buf.width)
  desc_w = math.max(0, width - 2 - label_w - 2 - 2)
  -- Under the start of the word being completed.
  local current = a.matches[math.max(1, a.match)]
  local offset = api.str_width(current.text) - api.str_width(current.label)
  if a.match == 0 then
    -- Nothing chosen yet: the typed text is a prefix of what it completes.
    offset = math.min(offset, api.str_width(text()))
  end
  local x = api.str_width(a.prompt) + math.max(0, offset) - 2
  x = math.max(0, math.min(x, buf.width - width))
  local y = buf.height - 1 - rows
  a.popup = { x = x, y = y, w = width, rows = rows, top = top }
  for row = 0, rows - 1 do
    local i = top + row
    local c = a.matches[i]
    local sel = i == a.match
    buf:fill(x, y + row, width, 1, " ", sel and "PmenuSel" or "Pmenu")
    if sel then buf:text(x, y + row, "▶", "PmenuSel") end
    buf:text(x + 2, y + row, paw.util.fit(c.label, label_w), sel and "PmenuSel" or "Pmenu")
    if desc_w > 0 and c.desc then
      buf:text(x + 2 + label_w + 2, y + row, paw.util.fit(brief(c.desc), desc_w), sel and "PmenuSelDesc" or "PmenuDesc")
    end
  end
  -- More than fit: a thumb on the right edge says where in the list this is.
  if n > rows then
    local size = math.max(1, math.floor(rows * rows / n))
    local at = math.floor((top - 1) / (n - rows) * (rows - size) + 0.5)
    for row = 0, rows - 1 do
      buf:text(x + width - 1, y + row, (row >= at and row < at + size) and "┃" or "│", "PmenuThumb")
    end
  end
end
paw.ui.draw_popup = M.draw_popup

--- A prompt drawn beside what it is about (`anchor`): one line in a small
--- float with the few words its preview says, and the candidates under it
--- (over it when there is no room below).
function M.draw_anchored(buf, a, at)
  local typed = text()
  local note = a.note or ""
  local ghost = typed == "" and a.ghost or nil
  local width = api.str_width(a.prompt) + math.max(api.str_width(typed) + 1, ghost and api.str_width(ghost) + 1 or 12) + 2
  if note ~= "" then width = width + api.str_width(note) + 2 end
  width = math.min(math.max(width, 24), buf.width)
  local x = math.max(0, math.min(at.x, buf.width - width))
  local y = math.max(0, math.min(at.y, buf.height - 2))
  buf:fill(x, y, width, 1, " ", "Pmenu")
  local used = buf:text(x + 1, y, a.prompt, "PmenuSel")
  local room = width - used - 2
  buf:text(x + 1 + used, y, paw.util.fit(typed, math.max(1, room)), "Pmenu")
  -- Examples of what to type, dim, until something is typed over them.
  if ghost then buf:text(x + 1 + used, y, paw.util.fit(ghost, math.max(1, room)), "PmenuDesc") end
  if note ~= "" then
    local w = math.min(api.str_width(note), math.max(0, room - api.str_width(typed) - 2))
    if w >= 4 then buf:text(x + width - 1 - w, y, paw.util.fit(note, w), a.note_level == "error" and "Warn" or "PmenuDesc") end
  end
  local before = table.concat(a.chars, "", 1, a.pos)
  api.ui_cursor(x + 1 + used + api.str_width(before), y)
  a.popup = nil
  local n = a.matches and #a.matches or 0
  if n == 0 then return end
  local below = buf.height - y - 2
  local rows = math.min(MAX_ROWS, n, math.max(below, y))
  if rows < 1 then return end
  local top = 1
  if a.match > rows then top = a.match - rows + 1 end
  local label_w, desc_w = 0, 0
  for i = top, top + rows - 1 do
    local c = a.matches[i]
    label_w = math.max(label_w, api.str_width(c.label))
    if c.desc and c.desc ~= "" then desc_w = math.max(desc_w, api.str_width(brief(c.desc))) end
  end
  local list_w = math.min(buf.width, 2 + label_w + (desc_w > 0 and 2 + math.min(desc_w, 40) or 0) + 1)
  desc_w = math.max(0, list_w - 2 - label_w - 3)
  local lx = math.max(0, math.min(x, buf.width - list_w))
  local ly = below >= rows and y + 1 or y - rows
  a.popup = { x = lx, y = ly, w = list_w, rows = rows, top = top }
  for row = 0, rows - 1 do
    local i = top + row
    local c = a.matches[i]
    local sel = i == a.match
    buf:fill(lx, ly + row, list_w, 1, " ", sel and "PmenuSel" or "Pmenu")
    buf:text(lx + 1, ly + row, paw.util.fit(c.label, label_w), sel and "PmenuSel" or "Pmenu")
    if desc_w > 0 and c.desc then
      buf:text(lx + 2 + label_w + 1, ly + row, paw.util.fit(brief(c.desc), desc_w), sel and "PmenuSelDesc" or "PmenuDesc")
    end
  end
end

-- The pointer on the list: a click puts a candidate in the line, a second
-- click on it (or a double click) runs the line; the wheel moves through
-- the list.
paw.mouse.overlays[#paw.mouse.overlays + 1] = function(e)
  local a = active
  local p = a and a.matches and #a.matches > 0 and a.popup
  if not p or e.x < p.x or e.x >= p.x + p.w or e.y < p.y or e.y >= p.y + p.rows then return false end
  if e.kind == "down" then
    local i = p.top + e.y - p.y
    if a.matches[i] then
      local again = i == a.match
      complete(i - a.match)
      if again or e.double then on_key("<CR>") end
    end
  else
    local step = paw.mouse.wheel(e)
    if step then complete(step) end
  end
  api.ui_redraw()
  return true
end

--- Read a typed value against the one there is now. A number is the value
--- itself, with its sign: `-6` is -6, `+3` is 3 (`=-6` is -6 too). `+=2`
--- and `-=3` change `now` by a step. `parse(text)` reads one absolute
--- value (default: a number, with any unit after it ignored). Nil when the
--- text says nothing usable.
function M.read_value(text, now, parse)
  parse = parse or function(t) return tonumber((t:match("^%s*([%+%-]?[%d%.]+)"))) end
  text = text:match("^%s*(.-)%s*$")
  if text == "" then return nil end
  local sign, rest = text:match("^([%+%-])=%s*(.+)$")
  if sign then
    local by = parse(rest)
    if not by then return nil end
    return now + (sign == "-" and -by or by)
  end
  return parse((text:gsub("^=%s*", "")))
end

--- Ask for an exact value on the command line: a number is the value, with
--- its sign (`-6` is -6 dB), and `+=2` and `-=3` change the current value
--- by a step.
---   paw.ui.ask_value({ label = "Volume", now = -8, unit = "dB", min = -60, max = 12 }, function(v) ... end)
--- The options are `show(value)`, which writes the current value,
--- `parse(text)`, which reads one absolute value, and `min` and `max`, the
--- limits of the value.
function M.ask_value(opts, set)
  local now = opts.now
  local shown = opts.show and opts.show(now) or (string.format("%g", now) .. (opts.unit and opts.unit ~= "" and " " .. opts.unit or ""))
  M.open({ prompt = string.format("%s %s → (-6 sets, +=2 -=3 step): ", opts.label, shown), history = "value",
    label = "Set " .. opts.label }, function(text)
    local value = M.read_value(text, now, opts.parse)
    if not value then return paw.notify("not a value: `" .. text .. "`", "warn") end
    if opts.min then value = math.max(opts.min, value) end
    if opts.max then value = math.min(opts.max, value) end
    set(value)
  end)
end
paw.ui.ask_value = M.ask_value

local levels = { info = "Info", warn = "Warn", error = "Error" }

-- An error stays mentioned on the key line until the messages are looked
-- at, or for a minute.
local ERROR_SHOWN = 60000
local seen_at = 0

--- The last error, if it has not been read in the messages since.
function M.unread_error()
  local list = paw.ui.messages
  for i = #list, math.max(1, #list - 50), -1 do
    local m = list[i]
    if m.level == "error" then
      if m.time > seen_at and api.now() - m.time < ERROR_SHOWN then return m end
      return nil
    end
  end
end

--- How to see every message: the key for the messages, and the command.
function M.messages_hint()
  for _, map in ipairs(paw.keymap.list("n")) do
    if map.rhs == "pick.messages" or map.rhs == "messages" then return paw.keymap.human(map.lhs) .. " or :messages" end
  end
  return ":messages"
end

paw.on("command.pre", function(e)
  if e.command == "messages" or e.command == "pick.messages" then seen_at = api.now() end
end)

paw.ui.view("cmdline", {
  focusable = false,
  -- Nothing in it moves on its own as the song plays (paw/ui.lua).
  still = true,
  render = function(_, buf, ctx)
    if active and not anchored(active) then
      local used = buf:text(0, 0, active.prompt, "Accent")
      local typed = buf:text(used, 0, text(), active.selected and "Visual" or "Normal")
      if typed == 0 and active.ghost then buf:text(used, 0, paw.util.fit(active.ghost, math.max(1, buf.width - used - 1)), "Dim") end
      -- What the line would do, at the right end while there is room.
      local note = active.note
      if note and note ~= "" then
        local w = api.str_width(note)
        local room = buf.width - used - typed - 3
        if room >= 8 then
          buf:text(buf.width - math.min(w, room) - 1, 0, w > room and paw.util.fit(note, room) or note,
            active.note_level == "error" and "Warn" or "Dim")
        end
      end
      local before = table.concat(active.chars, "", 1, active.pos)
      api.ui_cursor(ctx.x + used + api.str_width(before), ctx.y)
      return
    end
    local pending = paw.keymap.pending()
    if pending ~= "" then buf:text(buf.width - #pending - 2, 0, pending, "Accent") end
    local message = paw.ui.message
    if message and paw.keymap.mode == "i" and paw.opt.keybar and #paw.ui.keybar.entries() > 0 then
      -- While typing, the keys are what is needed: the message goes at the
      -- right end, cut to its share, and the keys keep the rest.
      local first = message.text:match("^[^\n]*")
      local share = math.floor(buf.width * 0.4)
      local shown = api.str_width(first) > share and paw.util.fit(first, share) or first
      local w = api.str_width(shown)
      buf:text(buf.width - w - 1, 0, shown, levels[message.level] or "Info")
      paw.draw.keys(buf, 1, 0, paw.ui.keybar.entries(), buf.width - w - 4)
    elseif message then
      local first = message.text:match("^[^\n]*")
      local how = M.messages_hint()
      local more = (message.text:find("\n") or message.level == "error") and ("  " .. how .. " shows it all") or ""
      local room = math.max(10, buf.width - api.str_width(more) - 1)
      local used = buf:text(0, 0, api.str_width(first) > room and paw.util.fit(first, room) or first, levels[message.level] or "Info")
      if more ~= "" then buf:text(used, 0, more, "Dim") end
    elseif paw.opt.keybar and pending == "" then
      -- With nothing to say, the line shows the keys worth knowing here,
      -- and a word on how to read an error that has gone by unread.
      -- The note goes at the right end, the keys keep their places.
      local room = buf.width - 2
      if M.unread_error() then
        -- Short, so that the keys keep their room: the key, and what it shows.
        local key = M.messages_hint():match("^(.-) or ") or ":messages"
        local w = api.str_width(key) + 12
        local x = buf.width - w
        x = x + buf:text(x, 0, key, "KeyBarKey") + 1
        buf:text(x, 0, "last error", "Error")
        room = buf.width - w - 3
      else
        -- Else the topic of help for the view, where there is room for it.
        local topic = paw.help and paw.help.topic_of(paw.ui.focused)
        local hint = topic and ":help " .. topic
        if hint and api.str_width(hint) + 40 < room then
          buf:text(buf.width - api.str_width(hint) - 1, 0, hint, "KeyBarText")
          room = room - api.str_width(hint) - 3
        end
      end
      paw.draw.keys(buf, 1, 0, paw.ui.keybar.entries(), room)
    end
  end,
})

return M
