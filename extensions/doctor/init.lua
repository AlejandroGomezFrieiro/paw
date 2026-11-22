-- A guided check of the real hardware: audio, MIDI, recording, plugins and
-- the environment, with a written report. `:doctor` opens it, `paw doctor`
-- runs what needs nobody from the shell. See README.md beside this file.
paw.option.define("doctor_plugins", {}) -- name fragments of plugins to load and play: { "MT-PowerDrumKit", "Ugritone" }
paw.option.define("doctor_seconds", 20) -- seconds each of the two dropout runs lasts
paw.option.define("doctor_dir", "") -- where reports go; "" is `doctor` in the state directory

local doctor = require("doctor")
local panel = require("doctor.panel")
require("doctor.gui")

local command, map = paw.command, paw.keymap.set

-- Where a window has no terminal to float over, the page is only in its own
-- window, and the keyboard goes there through this hidden place in the layout.
paw.ui.dock("doctor", { side = "bottom", hidden = true })

--- Show the page: floating over the terminal if there is one, and in a
--- window of its own where a graphical frontend is attached.
local function open()
  if paw.api.ui_attached() then
    paw.ui.open("doctor", { title = "Doctor", width = 100, height = 30 })
  else
    paw.ui.focus("doctor")
  end
  paw.canvas.open("doctor", { title = "Doctor", width = 900, height = 560 })
end

local function close()
  if doctor.running() then doctor.cancel() end
  paw.canvas.close("doctor")
  if paw.ui.float and paw.ui.float.name == "doctor" then paw.ui.close() end
  if paw.ui.focused == "doctor" then paw.canvas.back("doctor") end
  -- Taking the keyboard showed its place in the layout: it goes again.
  paw.ui.hide("doctor")
end

local function names()
  local out = { "all", "unattended", "stop", "report" }
  for _, check in ipairs(doctor.checks) do
    out[#out + 1] = doctor.id_of(check)
  end
  return out
end

command("doctor", function(ctx)
  local what = ctx.args[1] and tostring(ctx.args[1])
  open()
  if what == "report" then
    local run = doctor.run()
    return paw.notify(
      run and run.report and ("report: " .. run.report) or "no report yet: `:doctor all` runs the checks",
      run and run.report and nil or "warn"
    )
  end
  if what == "stop" then return doctor.cancel() end
  if what == nil then return end
  if doctor.running() then return paw.notify("the doctor is running: `:doctor stop` ends it", "warn") end
  local ok, err
  if what == "all" then
    ok, err = pcall(doctor.start)
  elseif what == "unattended" then
    ok, err = pcall(doctor.start, { unattended = true })
  else
    ok, err = pcall(doctor.start, { only = { tonumber(what) or what } })
  end
  if not ok then paw.notify(tostring(err):gsub("^[^:]*:%d+: ", ""), "warn") end
end, {
  desc = "Check the hardware: `doctor` opens the page, `doctor all` runs every check, `doctor input` one, `doctor unattended` those that need nobody",
  complete = names,
})

command("doctor.close", close, { desc = "Close the doctor's page, and stop a run that is going" })

-- The page's keys. A key that answers the question being asked does that;
-- otherwise it does what is written here.
local function pmap(lhs, rhs, desc, opts) map(lhs, rhs, paw.util.merge({ view = "doctor", desc = desc }, opts)) end
local function move(by)
  return function(ctx)
    panel.row = panel.row + by * (ctx.count or 1)
    panel:current()
    paw.api.ui_redraw()
  end
end
pmap("j", move(1), "Down a check", { motion = true })
pmap("k", move(-1), "Up a check", { motion = true })
pmap("<Down>", move(1), "Down a check", { motion = true })
pmap("<Up>", move(-1), "Up a check", { motion = true })
-- The answers are a prompt's keys, as Vim's `y/n` questions are: they mean
-- what the question on the page offers (`prompt` tells the key rule so).
for _, key in ipairs(panel.answer_keys) do
  pmap(key, function()
    if doctor.answer(key) then return end
    if key == "s" then doctor.skip() end
  end, key == "s" and 'Skip the check, or answer "skip"' or "Answer the question with this key", { prompt = true })
end
pmap("<CR>", function()
  if doctor.running() then return end
  local row = panel:current()
  if row then doctor.start({ only = { row.index } }) end
end, "Run the check under the cursor")
pmap("A", function()
  if not doctor.running() then doctor.start() end
end, "Run every check")
pmap("u", function()
  if not doctor.running() then doctor.start({ unattended = true }) end
end, "Run the checks that need nobody")
pmap("o", function()
  local run = doctor.run()
  paw.notify(run and run.report and ("report: " .. run.report) or "no report yet", run and run.report and nil or "warn")
end, "Where the report is")
-- Escape cancels the run and stays, as it cancels anything in every view;
-- `q` closes the page.
pmap("<Esc>", function()
  if doctor.running() then
    doctor.cancel()
  else
    paw.keymap.escape_hint()
  end
end, "Stop the run", { repeatable = false })
paw.keymap.classic("<Esc>", function()
  if doctor.running() then
    doctor.cancel()
  else
    close()
  end
end, { view = "doctor", desc = "Stop the run; close the page when none is going" })
pmap("q", close, "Close the page")

if paw.ui.keybar then
  paw.ui.keybar.set("doctor", "n", {
    { "<CR>", "run this" },
    { "A", "run all" },
    { "u", "no person" },
    { "y", "yes" },
    { "n", "no" },
    { "s", "skip" },
    { "o", "report" },
    { "<Esc>", "stop" },
    { "q", "close" },
  })
end

return doctor
