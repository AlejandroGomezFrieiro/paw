-- The harness of the end-to-end scenarios: it runs ONE day of a scenario in
-- this paw process, keeps the reference model (tests/e2e/model.lua) in step
-- with each action, and makes the checks of the day. tests/tools/e2e.sh
-- starts a new paw for each day. docs/explanation/about-the-e2e-tests.md
-- tells the design.
local paw = require("paw")
local api = paw.api
local Model = dofile("tests/e2e/model.lua")
local speed = dofile("tests/tools/speed.lua")

local E = { Model = Model, ANY = Model.ANY }
E.__index = E

-- Seeded randomness -------------------------------------------------------------

--- A generator of numbers from a seed (Park and Miller): the same seed gives
--- the same numbers on every machine and every version of LuaJIT.
local function rng(seed)
  local x = seed % 2147483646 + 1
  local r = {}
  function r.next()
    x = (16807 * x) % 2147483647
    return x
  end
  --- An integer from `a` to `b`.
  function r.int(a, b) return a + r.next() % (b - a + 1) end
  --- One item of a list.
  function r.pick(list) return list[r.int(1, #list)] end
  --- True with the chance `p`.
  function r.chance(p) return r.next() / 2147483647 < p end
  return r
end
E.rng = rng

-- The run of a day -------------------------------------------------------------

--- A new run: `opts` = { scenario, day, seed, workdir, live }. A run that is
--- not live only applies the actions to the model: it rebuilds the state
--- that the days before this one left.
function E.new(opts)
  local self = setmetatable({}, E)
  self.scenario, self.day, self.seed, self.workdir = opts.scenario, opts.day, opts.seed, opts.workdir
  self.live = opts.live
  self.model = opts.model or Model.new()
  self.step = 0
  self.key_ms = {}
  self.rng = rng(self.seed * 1000 + self.day)
  return self
end

--- Where a failure happened, for the message and the repeat command.
function E:where(what)
  return string.format("scenario %s, seed %d, day %d, step %d%s", self.scenario, self.seed, self.day, self.step,
    what and (" (" .. what .. ")") or "")
end

function E:fail(what, text)
  error({ e2e = true, where = self:where(what), text = text }, 0)
end

-- What paw holds, in the shape of the model -----------------------------------------

local function basename(path) return path and (path:match("([^/]+)$")) or nil end

--- The state of the project as the model describes it, read through the
--- public Lua objects of paw.
function E.snapshot()
  local p = api.project_get()
  local out = { tempo = p.tempo, markers = {}, tracks = {} }
  for _, m in ipairs((p.meta or {}).markers or {}) do out.markers[#out.markers + 1] = { name = m.name, beat = m.beat } end
  table.sort(out.markers, function(a, b) return a.beat < b.beat end)
  local names = {}
  for _, t in ipairs(paw.tracks()) do names[t.id] = t.name end
  for _, t in ipairs(paw.tracks()) do
    local g = t:get()
    local track = { name = g.name, color = t.color, volume = g.volume, pan = g.pan, mute = g.mute, solo = g.solo,
      devices = {}, sends = {}, clips = {}, notes = {} }
    for _, d in ipairs(t:devices()) do track.devices[#track.devices + 1] = d.kind end
    for _, s in ipairs(g.sends or {}) do track.sends[#track.sends + 1] = { target = names[s.target], level = s.level } end
    for _, c in ipairs(t:clips()) do
      local cg = c:get()
      local clip = { kind = cg.kind, start = cg.start, length = cg.length, name = cg.name, muted = cg.muted }
      if cg.kind == "audio" then
        clip.file = basename(cg.file)
      else
        clip.notes = {}
        for _, n in ipairs(c:notes()) do
          clip.notes[#clip.notes + 1] = { pitch = n.pitch, start = n.start, length = n.length, velocity = n.velocity }
          if n.start >= 0 and n.start < cg.length then
            track.notes[#track.notes + 1] = { pitch = n.pitch, start = cg.start + n.start, length = n.length, velocity = n.velocity }
          end
        end
        Model.sort_notes(clip.notes)
      end
      track.clips[#track.clips + 1] = clip
    end
    Model.sort_notes(track.notes)
    out.tracks[#out.tracks + 1] = track
  end
  return out
end

--- Fail with the first differences between the model and paw.
function E:compare(what, want, got)
  local diffs = Model.diff(want or self.model, got or E.snapshot())
  if #diffs > 0 then
    local shown = {}
    for i = 1, math.min(8, #diffs) do shown[i] = "  " .. diffs[i] end
    if #diffs > 8 then shown[#shown + 1] = string.format("  ... and %d more", #diffs - 8) end
    self:fail(what, "paw differs from the model:\n" .. table.concat(shown, "\n"))
  end
end

-- Actions ------------------------------------------------------------------------

local function last_message() return paw.ui.message and paw.ui.message.text or "" end

--- Type keys as a person does: each item is one burst of typing, after
--- which the kernel closes the undo step. Gives the processor time of the
--- slowest burst.
function E:type(list)
  local slowest = 0
  for _, text in ipairs(list) do
    local t0 = speed.cpu_ms()
    paw.keymap.feed(text)
    paw.flush()
    api.undo_checkpoint()
    slowest = math.max(slowest, speed.cpu_ms() - t0)
  end
  return slowest
end

--- One action of the user. `a` = {
---   name,                 what the user does, in words
---   keys = { ... },       the keys, each item one burst
---   apply = fn(model),    the same change on the model (nil: no change)
---   focus = "mixer",      the view that has the keyboard after it
---   says = "pattern",     the message that paw shows after it
---   slow = true,          a command that does real work (render, import): not a key of rule 7
---   check = fn(self),     a check of its own, after the model compare
--- }
function E:act(a)
  self.step = self.step + 1
  if a.apply then a.apply(self.model, self) end
  if not self.live then return end
  local before = #paw.ui.messages
  local ok, err = pcall(function()
    local ms = self:type(a.keys)
    if not a.slow then self.key_ms[#self.key_ms + 1] = { ms = ms, name = a.name } end
  end)
  if not ok then self:fail(a.name, "the keys raised an error: " .. tostring(err)) end
  for i = before + 1, #paw.ui.messages do
    local m = paw.ui.messages[i]
    if m.level == "error" and not (a.error and m.text:find(a.error)) then
      self:fail(a.name, "paw showed an error: " .. m.text)
    end
  end
  if a.says and not last_message():find(a.says) then
    self:fail(a.name, string.format("the message %q does not say %q", last_message(), a.says))
  end
  if a.focus and paw.ui.focused ~= a.focus then
    self:fail(a.name, string.format("the view with the keyboard is %s, not %s", tostring(paw.ui.focused), a.focus))
  end
  self:compare(a.name)
  if a.check then a.check(self) end
end

-- Helpers for scenarios: keys for common moves ----------------------------------------

--- Keys that put the arrange cursor on track `i` (1 = first) at bar `bar`.
--- The arrange view has the keyboard: the scenarios go back to it after
--- each visit to another view.
function E.go(i, bar)
  return { "<Esc>", tostring(i) .. "G", tostring(bar or 1) .. "|" }
end

--- The keys of insert mode that draw `notes` one after the other from the
--- cursor, each `{ pitch, length }` (length in steps of a quarter beat), the
--- first from C4 (60). Gives the keys and the notes as the model holds them.
function E.draw(notes, velocity)
  local keys, out, pitch, at = { "i" }, {}, 60, 0
  for i, n in ipairs(notes) do
    local d = n[1] - pitch
    local k = ""
    if d > 0 then k = d .. "k" elseif d < 0 then k = (-d) .. "j" end
    keys[#keys + 1] = k .. n[2] .. "l"
    if i < #notes then keys[#keys + 1] = "<CR>" end
    out[#out + 1] = { pitch = n[1], start = at, length = n[2] / 4, velocity = velocity or 100 }
    pitch, at = n[1], at + n[2] / 4
  end
  keys[#keys + 1] = "<Esc>"
  return keys, out, at
end

-- The checks of a day ---------------------------------------------------------------

local function files_of(dir)
  local out = {}
  local pipe = io.popen("cd '" .. dir .. "' && find . -type f ! -name '*.bak' | sort")
  for line in pipe:lines() do
    local f = io.open(dir .. "/" .. line, "rb")
    out[line] = f:read("*a")
    f:close()
  end
  pipe:close()
  return out
end
E.files_of = files_of

--- Files that a save after open may write again, each with the reason: a
--- known bug, printed on each run until it is fixed. Remove the entry with
--- the fix.
E.known_unstable = {}

--- The project opened from disk is the model of the days before, and a
--- save with no change writes the same bytes.
function E:check_opened()
  self.step = 0
  if not paw.project.path then self:fail("open", "paw did not open the project") end
  self:compare("the project as it opened")
  local dir = paw.project.path:match("^(.*)/project%.toml$")
  local before = files_of(dir)
  self:type({ ":wa<CR>" })
  local after = files_of(dir)
  for path, data in pairs(after) do
    if before[path] ~= data then
      if E.known_unstable[path] then
        print("e2e: known: " .. path .. " changed in a save after open: " .. E.known_unstable[path])
      else
        self:fail("save after open", "a save with no change wrote " .. path .. " again, different")
      end
    end
  end
  for path in pairs(before) do
    if not after[path] then self:fail("save after open", "a save with no change removed " .. path) end
  end
end

--- Every change of the day undone gives the state the day began with, and
--- redone gives the state it ended with.
function E:check_undo(start_state)
  local finish = E.snapshot()
  self:type({ "<Esc>", "999u", "999u" })
  self:compare("undo every change of the day", start_state)
  self:type({ "999<C-r>", "999<C-r>" })
  self:compare("redo every change of the day", finish)
end

--- The keys of the day were quick: the slowest under the limit of rule 7.
function E:check_keys(limit)
  local worst = { ms = 0, name = "none" }
  for _, k in ipairs(self.key_ms) do
    if k.ms > worst.ms then worst = k end
  end
  local ok, err = pcall(speed.quick, worst.ms, limit or 100, "the slowest key of the day, " .. worst.name)
  if not ok then self:fail("speed", tostring(err)) end
  return worst
end

--- `:checkhealth` shows no ERROR.
function E:check_health()
  self:type({ ":checkhealth<CR>" })
  local lines = {}
  for _, line in ipairs(paw.ui.views.pager.lines) do
    if line.text:find("- ERROR", 1, true) then lines[#lines + 1] = line.text end
  end
  paw.ui.close()
  if #lines > 0 then self:fail("checkhealth", table.concat(lines, "\n")) end
end

--- The loudness of a WAV file of 16 bits, in dB, for each window of
--- `seconds` (a fingerprint of the mix).
local function fingerprint(info, seconds)
  local f = assert(io.open(info.path, "rb"))
  local data = f:read("*a")
  f:close()
  local at = data:find("data", 1, true) + 8
  local frame = 4
  local per = math.floor(seconds * info.sample_rate)
  local out = {}
  local sum, n = 0, 0
  for i = at, #data - 3, frame do
    local lo, hi = data:byte(i, i + 1)
    local v = lo + hi * 256
    if v >= 32768 then v = v - 65536 end
    v = v / 32768
    sum, n = sum + v * v, n + 1
    if n == per then
      out[#out + 1] = math.floor(10 * 10 * math.log10(math.max(sum / n, 1e-10)) + 0.5) / 10
      sum, n = 0, 0
    end
  end
  return out
end
E.fingerprint = fingerprint

--- Render the song offline: it is not silent, and its fingerprint is the
--- approved one of this seed and day (when one is approved). Gives the
--- fingerprint.
function E:check_render(golden)
  local path = self.workdir .. "/render-day" .. self.day .. ".wav"
  local info = paw.render(path, { tail = 0, bits = 16 })
  if not info or (info.peak or 0) < 0.001 then self:fail("render", "the song renders silent") end
  local print_ = fingerprint(info, 1)
  if golden then
    if #golden ~= #print_ then
      self:fail("render", string.format("the render has %d windows of 1 s, the approved one %d", #print_, #golden))
    end
    for i = 1, #golden do
      if math.abs(golden[i] - print_[i]) > 1.5 then
        self:fail("render", string.format("second %d: %.1f dB, the approved %.1f dB (±1.5)", i, print_[i], golden[i]))
      end
    end
  end
  os.remove(path)
  return print_
end

--- No message of the day was an error (each action checks its own; this
--- catches those of timers and the engine).
function E:check_errors(from)
  for i = from + 1, #paw.ui.messages do
    local m = paw.ui.messages[i]
    if m.level == "error" then self:fail("messages", "paw showed an error during the day: " .. m.text) end
  end
end

return E
