-- Tests of help (paw/help.tl and paw/markdown.tl): the Markdown made into
-- text, tags, `:help` and its completion, following links and coming back,
-- `K`, `:helpgrep`, pages of extensions that are not loaded, and help in a
-- window of the graphical frontend. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local L = paw.layout
local H = paw.help
local md = paw.markdown

local initial = L.capture()

local function clean()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  for _, buf in ipairs(L.buffers_list()) do
    if buf.type == "textbuf" then L.buf_delete(buf) end
  end
  L.restore(initial)
  paw.ui.focus("arrange")
end

local function start()
  fresh()
  clean()
  -- The help windows a test opened go with it, whatever happens.
  T.after(clean)
end

--- The help window the keyboard is in: its buffer's name, the line under
--- its cursor and the cursor.
local function here()
  local win, buf, t, s = paw.textbuf.here()
  if not win then return nil end
  return buf.name, t:line(s.row), s
end

--- Put the cursor on the first line that holds `text`, on its first character.
local function cursor_on(text)
  local _, _, t, s = paw.textbuf.here()
  for row = 1, t:count() do
    local at = t:line(row):find(text, 1, true)
    if at then
      s.row, s.col = row, md.width(t:line(row):sub(1, at - 1))
      return row
    end
  end
  error("no line holds " .. text, 2)
end

local function message() return paw.ui.message and paw.ui.message.text or "" end

-- Markdown --------------------------------------------------------------------------

test("Markdown is made into text: headings with their tag, bullets, aligned tables, code apart, links", function()
  local doc = md.render(
    md.parse(table.concat({
      "# Title",
      "",
      "## A section",
      "",
      "Some **bold** and *italic* words with `gU` and a [link](other.md#there).",
      "",
      "- one item that is long enough to wrap onto the next line of the page, so that the hanging indent shows",
      "  - a nested item",
      "1. first",
      "",
      "| Key | What |",
      "| --- | --- |",
      "| `dd` | delete a track |",
      "| `yy` | yank it |",
      "",
      "```lua",
      'paw.opt.keys = "classic"',
      "```",
    }, "\n")),
    { width = 60, heading_tag = function(b) return b.level == 1 and "title" or "a-section" end }
  )
  local text = {}
  for i, line in ipairs(doc.lines) do
    text[i] = line.text
  end
  local shown = table.concat(text, "\n")
  eq(text[1]:match("^Title %s+%*title%*$") ~= nil, true, "the title with its tag at the right: " .. text[1])
  eq(md.width(text[1]), 60, "the tag ends at the page's edge")
  eq(text[3], string.rep("─", 60), "a rule above a section")
  eq(shown:find("Some bold and italic words with gU and a link.", 1, true) ~= nil, true, "marks taken out: " .. shown)
  eq(shown:find("  • one item that is long enough", 1, true) ~= nil, true, "a bullet")
  eq(
    shown:find("\n    so that the hanging indent shows", 1, true) ~= nil or shown:find("\n    [^ ]", 1) ~= nil,
    true,
    "the item goes on under its text"
  )
  eq(shown:find("      • a nested item", 1, true) ~= nil, true, "a nested item deeper")
  eq(shown:find("\n 1. first", 1, true) ~= nil, true, "a number")
  eq(
    shown:find(
      "Key  What\n───  ──────────────\ndd   delete a track\nyy   yank it",
      1,
      true
    ) ~= nil,
    true,
    "the table's columns aligned: " .. shown
  )
  eq(shown:find('\n    paw.opt.keys = "classic"', 1, true) ~= nil, true, "code indented")
  -- What each piece is drawn as, and the link's target.
  local para
  for _, line in ipairs(doc.lines) do
    if line.text:find("^Some") then para = line end
  end
  local styles = {}
  for _, span in ipairs(para.spans) do
    styles[#styles + 1] = span[3]
  end
  eq(table.concat(styles, " "), "HelpBold HelpItalic HelpCode HelpLink", "bold, italic, code, link")
  eq(para.links[1][3], "other.md#there", "the link's target")
  eq(para.codes[1][3], "gU", "the code, for tags")
end)

test("a table too wide for the page wraps its widest column", function()
  local long = string.rep("word ", 30)
  local doc = md.render(md.parse("| A | B |\n| --- | --- |\n| `x` | " .. long .. " |\n| `y` | short |"), { width = 40 })
  for _, line in ipairs(doc.lines) do
    eq(md.width(line.text) <= 40, true, "within the page: " .. line.text)
  end
  eq(doc.lines[3].text:match("^x  word") ~= nil, true, "the first column keeps its width")
  eq(doc.lines[4].text:match("^   word") ~= nil, true, "the cell goes on under itself")
end)

-- Tags -------------------------------------------------------------------------------

test("tags are found for keys, commands, options, Lua modules, sections and pages", function()
  start()
  local function where(topic)
    local tag = H.lookup(topic)
    return tag and tag.source.name .. " " .. tag.name or "none"
  end
  eq(where("gL"), "keys.md gL", "a key: its row in the key table")
  eq(where(":s"), "ex.md :s", "a command")
  eq(where("'timebind'"), "options.md 'timebind'", "an option")
  eq(where("paw.qf"), "lua-addresses.md paw.qf", "a Lua module")
  eq(where("key-rule"), "key-rule.md key-rule", "a section named in the page")
  eq(where("quickfix-list"), "quickfix.md quickfix-list", "a heading")
  eq(where("terminal"), "grammar.md terminal", "an old page's name, kept as a tag")
  eq(where("grammar"), "grammar.md grammar", "a page")
  eq(where("course-5"), "course/05-grammar.md course-5", "a lesson")
  eq(where("notation"), "notation/README.md notation", "an extension")
  eq(where("notation-keys"), "notation/doc/reference.md notation-keys", "an extension's heading, on a page of its doc/")
  eq(where("notation-popovers"), "notation/doc/reference.md notation-popovers", "another")
  eq(where("ic"), "keys.md ic", "a text object: its row in the key table")
  eq(where("<C-w>o"), where("Ctrl-w o"), "a key written either way")
  -- Each lands on the line that names it.
  local tag = H.lookup("gU")
  eq(tag.source.doc.lines[tag.row].text:find("gU", 1, true) ~= nil, true, "the tag's line names it")
end)

test(
  "the manual's pages are found by kind: their folder's, else the section of docs/README.md that lists them",
  function()
    start()
    local docs = T.scratch .. "/helpkinds/docs"
    for _, dir in ipairs({ "tutorials/course", "how-to", "reference", "explanation" }) do
      os.execute("mkdir -p '" .. docs .. "/" .. dir .. "'")
    end
    T.write_file(
      docs .. "/README.md",
      table.concat({
        "# Manual",
        "",
        "## Tutorials",
        "",
        "- [Course](tutorials/course/README.md)",
        "",
        "## Reference",
        "",
        "- [Zeta](reference/zeta.md)",
        "- [Old](old.md)",
        "- [Alpha](reference/alpha.md)",
        "",
        "## Explanation",
        "",
        "- [Why](why.md)",
      }, "\n")
    )
    local files = {
      "tutorials/course/README.md",
      "tutorials/course/02-two.md",
      "tutorials/course/01-one.md",
      "how-to/record.md",
      "reference/record.md",
      "reference/alpha.md",
      "reference/zeta.md",
      "reference/keys.md",
      "explanation/about-x.md",
      "old.md",
      "why.md",
      "loose.md",
    }
    for _, rel in ipairs(files) do
      T.write_file(docs .. "/" .. rel, "# " .. rel .. "\n")
    end
    local got = {}
    for _, s in ipairs(H.manual_sources(H.normalize(docs))) do
      got[#got + 1] = s.group .. ":" .. s.name .. "=" .. s.aliases[1]
    end
    eq(
      table.concat(got, " "),
      table.concat({
        -- Reference first, as docs/README.md orders it, then the rest by name.
        "reference:zeta.md=zeta",
        "reference:old.md=old",
        "reference:alpha.md=alpha",
        "reference:keys.md=keys",
        "reference:loose.md=loose",
        "reference:reference/record.md=reference-record",
        "how-to:how-to/record.md=how-to-record",
        "explanation:why.md=why",
        "explanation:about-x.md=about-x",
        "tutorials:course/README.md=course",
        "tutorials:course/01-one.md=course-1",
        "tutorials:course/02-two.md=course-2",
      }, " "),
      "kinds, names and order"
    )
    -- The contents show them under the four headings, in Diátaxis' order.
    local text = {}
    for _, line in ipairs(H.index().sources[1].doc.lines) do
      text[#text + 1] = line.text
    end
    text = table.concat(text, "\n")
    local at = {}
    for _, heading in ipairs({ "Tutorials", "How-to guides", "Reference", "Explanation", "Extensions" }) do
      at[#at + 1] = text:find("\n" .. heading .. " ", 1, true) or text:find("\n" .. heading .. "\n", 1, true) or 0
    end
    eq(
      at[1] > 0 and at[1] < at[2] and at[2] < at[3] and at[3] < at[4] and at[4] < at[5],
      true,
      "the kinds in order: " .. table.concat(at, " ")
    )
  end
)

test("a link to the manual's contents page goes to help's contents", function()
  start()
  local index = H.index()
  local readme = index.sources[1].readme
  eq(readme ~= nil and readme:match("/docs/README%.md$") ~= nil, true, "the contents stand for docs/README.md")
  eq(index.by_path[readme], index.sources[1], "found by its path")
end)

test("a topic finds the tag itself first, then those that start with it, then those that hold its letters", function()
  start()
  local found = H.find("key-r", 3)
  eq(found[1].name, "key-rule", "the start of a tag")
  found = H.find("qflst", 5)
  eq(found[1] ~= nil and found[1].name:find("q") ~= nil, true, "letters in order")
  eq(H.find("gU", 1)[1].name, "gU", "the tag itself")
  local completion = paw.commands.complete("help key-r")
  eq(completion[1] and completion[1].text, "help key-rule", "Tab completes the tag")
  completion = paw.commands.complete("help quickfx")
  local any = false
  for _, c in ipairs(completion) do
    any = any or c.label == "quickfix-list"
  end
  eq(any, true, "a fuzzy match is offered too")
end)

-- The help window -------------------------------------------------------------------

test(":help opens the contents in a window split off, which cannot be changed", function()
  start()
  local before = #L.windows()
  paw.cmd("help")
  local name, line = here()
  eq(name, "help://index", "the contents")
  eq(#L.windows(), before + 1, "in a window of its own")
  eq(line:find("paw help", 1, true) ~= nil, true, "at the top")
  local count = paw.textbuf.buf().state.text:count()
  paw.keymap.feed("dd")
  paw.keymap.feed("x")
  eq(paw.textbuf.buf().state.text:count(), count, "dd removed nothing")
  eq(message():find("cannot be changed", 1, true) ~= nil, true, "and says why: " .. message())
  paw.keymap.feed("i")
  eq(paw.keymap.mode, "n", "no insert mode")
  -- Text in it can be chosen and yanked as any text.
  paw.keymap.feed("ggVy")
  eq(paw.keymap.getreg('"').kind, "lines", "yanked")
  -- A second :help reuses the window.
  paw.cmd("help", { "gU" })
  eq(#L.windows(), before + 1, "the same window")
  local _, at = here()
  eq(at:find("gU", 1, true) ~= nil, true, "on the key: " .. at)
end)

test("help is made at idle in short slices, and the first :help after it is quick", function()
  start()
  H.dirty = true -- every page made again, as at the start of a session
  H.prepare()
  eq(H.preparing(), true, "made at idle")
  local longest = 0
  for _ = 1, 5000 do
    if not H.preparing() then break end
    local t0 = T.cpu_ms()
    paw.wait(1)
    longest = math.max(longest, T.cpu_ms() - t0)
  end
  eq(H.preparing(), false, "and done")
  T.quick(longest, 40, "the longest slice, which a key waits for")
  local t0 = T.cpu_ms()
  T.keys(":help gU<CR>")
  T.quick(T.cpu_ms() - t0, 100, "the first :help after help was made at idle")
  eq((here() or ""):match("^help://") ~= nil, true, "it opens the page")
end)

test(":help with a topic puts the cursor on its line, and says when there is none", function()
  start()
  paw.cmd("help", { "key-rule" })
  local name, line = here()
  eq(name, "help://key-rule.md", "the page")
  eq(line:find("The key rule", 1, true) ~= nil, true, "the heading: " .. line)
  paw.cmd("help", { "zzzzqqqqxxxx" })
  eq(message():find("no help for zzzzqqqqxxxx", 1, true) ~= nil, true, message())
end)

test("Ctrl-] follows a link, Ctrl-t and Ctrl-o come back", function()
  start()
  paw.cmd("help")
  local row = cursor_on("Motions, operators and modes")
  paw.keymap.feed("<C-]>")
  local name = here()
  eq(name, "help://grammar.md", "followed")
  paw.keymap.feed("<C-t>")
  local back, _, s = here()
  eq(back, "help://index", "Ctrl-t comes back")
  eq(s.row, row, "to the line")
  paw.keymap.feed("<C-]>")
  eq((here()), "help://grammar.md", "followed again")
  paw.keymap.feed("<C-o>")
  eq((here()), "help://index", "Ctrl-o comes back too")
  -- On code, Ctrl-] goes to its tag; Enter does what Ctrl-] does.
  paw.cmd("help", { "windows-buffers-and-tabs" })
  cursor_on(":only")
  paw.keymap.feed("<CR>")
  local _, line = here()
  eq(line:find(":only", 1, true) ~= nil, true, "Enter followed the code: " .. line)
end)

test("K looks up the word under the cursor", function()
  start()
  paw.cmd("help", { "ex" })
  cursor_on("quickfix")
  paw.keymap.feed("K")
  local name, line = here()
  eq(name ~= nil, true, "a page")
  eq(line:lower():find("quickfix", 1, true) ~= nil, true, "where quickfix is: " .. line)
end)

test(":helpgrep puts every line that holds the words in the quickfix list and goes to the first", function()
  start()
  paw.cmd("helpgrep", { "timebind" })
  local list = paw.qf.current()
  eq(list.title, "helpgrep timebind", "the list")
  eq(#list.entries > 1, true, "with entries")
  for _, e in ipairs(list.entries) do
    eq(e.text:lower():find("timebind", 1, true) ~= nil, true, "each holds it")
  end
  eq(
    paw.qf.where(list.entries[1]):match("^.+:%d+$") ~= nil,
    true,
    "named by page and line: " .. paw.qf.where(list.entries[1])
  )
  local _, line = here()
  eq(line and line:lower():find("timebind", 1, true) ~= nil, true, "the cursor on the first")
  paw.cmd("cnext")
  local _, second = here()
  eq(second:lower():find("timebind", 1, true) ~= nil, true, "]q goes on to the next")
end)

test("the page of an extension that is not loaded says how to load it", function()
  start()
  local dir = T.scratch .. "/helpdemo"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(dir .. "/README.md", "# helpdemo\n\nAn extension for the help tests.\n\n## Popovers\n\nThey pop.\n")
  H.add(dir .. "/README.md", { tag = "helpdemo", ext = "helpdemo", dir = dir })
  paw.cmd("help", { "helpdemo-popovers" })
  local name = here()
  eq(name, "help://helpdemo.md", "its page")
  eq(message():find("helpdemo is not loaded", 1, true) ~= nil, true, "said: " .. message())
  local text =
    table.concat(paw.textbuf.buf().state.text.lines[3] and { paw.textbuf.buf().state.text.lines[3].text } or {}, "")
  local all = {}
  for _, l in ipairs(paw.textbuf.buf().state.text.lines) do
    all[#all + 1] = l.text
  end
  all = table.concat(all, " ")
  eq(all:find("This extension is not loaded", 1, true) ~= nil, true, "the page says so: " .. text)
  eq(all:find('paw.ext.load("' .. H.normalize(dir) .. '")', 1, true) ~= nil, true, "and how to load it")
  table.remove(H.extra)
  H.dirty = true
  -- A bundled one is loaded by its name.
  local name
  for _, ext in ipairs(paw.ext.bundled()) do
    if not paw.ext.loaded[ext] and io.open("extensions/" .. ext .. "/README.md") then name = name or ext end
  end
  if name then
    paw.cmd("help", { name })
    local text = {}
    for _, l in ipairs(paw.textbuf.buf().state.text.lines) do
      text[#text + 1] = l.text
    end
    eq(table.concat(text, "\n"):find(":ext.load " .. name, 1, true) ~= nil, true, name .. "'s page names :ext.load")
  end
end)

test("Ctrl-] in the keys picker opens the help of the key chosen", function()
  start()
  paw.pick("keys", { query = "Ctrl-w o" })
  paw.keymap.feed("<C-]>")
  local name, line = here()
  eq(name, "help://keys.md", "the key table: " .. message())
  eq(line:find("<C-w>o", 1, true) ~= nil, true, "at the key: " .. tostring(line))
  -- And in the commands picker, the command's.
  paw.pick("commands", { query = "helpgrep" })
  paw.keymap.feed("<C-]>")
  local _, at = here()
  eq(at:find(":helpgrep", 1, true) ~= nil, true, "at the command: " .. tostring(at))
end)

test("the keys picker shows the help of the key chosen, wide columns, and a key line", function()
  start()
  paw.pick("keys", { query = "Ctrl-w o" })
  local text = table.concat(api.ui_snapshot(200, 40), "\n")
  eq(text:find("Ctrl-w o", 1, true) ~= nil, true, "the key is listed")
  -- A key's help is its row in the key table, so the preview names that page.
  eq(text:find("Keys, by idea", 1, true) ~= nil, true, "the manual's page is named in the preview")
  local shown = {}
  for _, e in ipairs(paw.ui.keybar.entries()) do
    shown[#shown + 1] = e[1] .. " " .. e[2]
  end
  eq(table.concat(shown, " · "), "Enter run · Ctrl-] help · Esc close", "the key line")
  paw.ui.close()
end)

test("the key line names the view's topic of help, and every such topic is a tag", function()
  start()
  eq(H.topic_of("arrange"), "arrange-view", "the arrange view's")
  for view, topic in pairs(H.view_topics) do
    eq(H.index().tags[topic] ~= nil, true, view .. "'s topic " .. topic .. " is a tag")
  end
  paw.ui.message = nil
  local W = 200
  local bottom = api.ui_snapshot(W, 40)[40]
  eq(bottom:find(":help arrange-view", 1, true) ~= nil, true, "on the bottom line: " .. bottom)
end)

test("in the graphical frontend help opens as a docked pane, and pops out on request", function()
  start()
  local listeners = paw.remote.listeners
  paw.remote.listeners = function() return { { client = 9, watching = true } } end
  local ok, err = pcall(paw.cmd, "help", { "gU" })
  paw.remote.listeners = listeners
  assert(ok, err)
  eq(paw.canvas.open_views.textbuf, nil, "no window of its own")
  eq(paw.ui.focused, "textbuf", "the pane has the keyboard")
  local name, line = here()
  eq(name:match("^help://") ~= nil, true, "a help pane in the layout")
  eq(line:find("gU", 1, true) ~= nil, true, "at the key")
  T.keys("<C-w>f")
  eq(paw.canvas.open_views.textbuf ~= nil, true, "Ctrl-w f pops it out to a window of its own")
  paw.canvas.close("textbuf")
end)

test("help made at idle is the job help of paw.slices, and its tags come sorted by name", function()
  start()
  H.dirty = true -- every page made again, as at the start of a session
  local job = H.prepare()
  eq(paw.slices.job("help"), job, "the job help runs")
  eq(H.prepare(), job, "a second prepare joins the job that runs")
  T.until_(function() return not H.preparing() end, "help to be made at idle")
  eq(paw.slices.job("help"), nil, "and ends")
  eq(job.slices > 1, true, "in more than one slice")
  -- The tags are sorted in pieces (a merge sort that pauses).
  local list = H.index().list
  for i = 2, #list do
    if list[i - 1].name >= list[i].name then eq(list[i].name, "after " .. list[i - 1].name, "the tags in order") end
  end
end)
