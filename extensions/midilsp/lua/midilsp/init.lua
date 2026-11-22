-- MIDI LSP's entry for `paw.lsp`, as an nvim-lspconfig entry is for one
-- server: find the engine, say how to start it, and keep its settings (a
-- preset and rules switched on or off) with the project.
local api = paw.api
require("midilsp.adapter")

local M = {
  -- The servers this extension configures: the engine's language role
  -- (diagnostics, fixes, hover, the chords and key it hears) and its
  -- suggestion role (completion), each a process of its own as MIDI LSP
  -- runs them, so that a slow suggestion never holds up a diagnostic.
  LSP = "midi-lsp",
  SUGGEST = "midi-lsp-suggest",
}

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

local function words(text)
  local out = {}
  for word in tostring(text):gmatch("%S+") do
    out[#out + 1] = word
  end
  return out
end

local on_path = paw.api.which

--- The engine's command, without the transport: `paw.opt.midilsp_cmd`
--- (words, or a list), else `$MIDI_LSP_ENGINE`, else `reaper-midi-lsp`
--- on the PATH. Nil when there is none.
function M.engine()
  local opt = paw.opt.midilsp_cmd
  if type(opt) == "table" and #opt > 0 then return opt end
  if type(opt) == "string" and opt:match("%S") then return words(opt) end
  local env = os.getenv("MIDI_LSP_ENGINE")
  if env and env:match("%S") then return words(env) end
  local found = on_path("reaper-midi-lsp")
  return found and { found } or nil
end

local function command(...)
  local engine = M.engine()
  if not engine then return nil end
  local out = {}
  for _, w in ipairs(engine) do
    out[#out + 1] = w
  end
  for _, w in ipairs({ ... }) do
    out[#out + 1] = w
  end
  return out
end

-- Settings ---------------------------------------------------------------------

--- What the engine is configured with, kept in the project:
--- `{ preset = "default", rules = { ["parallel-perfect"] = { enabled = false } } }`.
function M.settings()
  local stored = (api.project_get().meta or {}).midilsp
  local out = { preset = "default", rules = {} }
  if type(stored) == "table" then
    out.preset = stored.preset or out.preset
    for id, on in pairs(type(stored.rules) == "table" and stored.rules or {}) do
      out.rules[id] = { enabled = on == true }
    end
  end
  return out
end

local function store(preset, rules)
  local meta = api.project_get().meta or {}
  local flat = {}
  for id, r in pairs(rules) do
    flat[id] = r.enabled
  end
  meta.midilsp = { preset = preset, rules = next(flat) and flat or nil }
  api.project_set("meta", meta)
  M.configure()
end

-- The settings as the engine takes them: no rules is no `rules` at all
-- (an empty table would be sent as a list).
local function wire()
  local s = M.settings()
  if not next(s.rules) then s.rules = nil end
  return s
end

-- The rule catalog the engine announced at `initialize`.
local function catalog()
  for _, c in ipairs(paw.lsp.clients()) do
    local exp = c.capabilities and c.capabilities.experimental
    local midi = type(exp) == "table" and exp.midi
    if c.name == M.LSP and type(midi) == "table" and type(midi.rules) == "table" then return midi.rules end
  end
end

--- The presets the engine has (empty until it has started).
function M.presets()
  local out = {}
  for name in pairs((catalog() or {}).presets or {}) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

--- The ids of the engine's rules (empty until it has started).
function M.rule_ids()
  local out = {}
  for _, r in ipairs((catalog() or {}).rules or {}) do
    out[#out + 1] = r.id
  end
  table.sort(out)
  return out
end

-- Whether a rule is on: as the settings say, else as the preset has it.
local function rule_on(id, settings)
  local r = settings.rules[id]
  if r then return r.enabled end
  for _, rid in ipairs(((catalog() or {}).presets or {})[settings.preset] or {}) do
    if rid == id then return true end
  end
  return false
end

function M.set_preset(name)
  local presets = M.presets()
  if #presets > 0 and not contains(presets, name) then error("midilsp: no preset `" .. name .. "`") end
  store(name, M.settings().rules)
end

--- Switch a rule on (true), off (false) or over ("toggle").
function M.set_rule(id, on)
  local ids = M.rule_ids()
  if #ids > 0 and not contains(ids, id) then error("midilsp: no rule `" .. id .. "`") end
  local s = M.settings()
  if on == "toggle" then on = not rule_on(id, s) end
  s.rules[id] = { enabled = on }
  store(s.preset, s.rules)
  paw.notify(string.format("midilsp: %s %s", id, on and "on" or "off"))
end

--- The engine's rules in a picker, on or off; Enter switches one.
function M.pick_rules()
  local rules = (catalog() or {}).rules
  if not rules then return paw.notify("midilsp: the engine is not running", "warn") end
  local s, items = M.settings(), {}
  for _, r in ipairs(rules) do
    items[#items + 1] =
      { text = string.format("%s  %-24s %s", rule_on(r.id, s) and "on " or "off", r.id, r.title or ""), id = r.id }
  end
  paw.pick({
    title = "MIDI LSP rules (" .. s.preset .. ")",
    items = items,
    on_choose = function(item)
      if item then M.set_rule(item.id, "toggle") end
    end,
  })
end

-- Starting ------------------------------------------------------------------------

--- Tell `paw.lsp` how to start the engine and what to send it.
function M.configure()
  paw.lsp.config(M.LSP, {
    cmd = function() return command("--stdio") end,
    framing = "lines",
    adapter = "midi-lsp",
    attach = { kinds = { "clip" } },
    settings = wire(),
    restart = { max = 3, within_s = 60 },
  })
  paw.lsp.config(M.SUGGEST, {
    cmd = function() return command("--role", "suggest", "--stdio") end,
    framing = "lines",
    adapter = "midi-lsp",
    attach = { kinds = { "clip" } },
    restart = { max = 3, within_s = 60 },
  })
end

--- Start the engine (both roles, the second as `paw.opt.midilsp_suggest`
--- says). `loud`: say so when there is no engine.
function M.start(loud)
  M.configure()
  if not M.engine() then
    if loud then
      paw.notify(
        "midilsp: no engine: set paw.opt.midilsp_cmd or $MIDI_LSP_ENGINE, or put reaper-midi-lsp on the PATH",
        "warn"
      )
    end
    return false
  end
  paw.lsp.enable(M.LSP)
  if paw.opt.midilsp_suggest then paw.lsp.enable(M.SUGGEST) end
  require("midilsp.checks").start()
  return true
end

function M.stop()
  paw.lsp.enable(M.LSP, false)
  paw.lsp.enable(M.SUGGEST, false)
  require("midilsp.checks").stop()
end

--- What `:midilsp` shows.
function M.info_lines()
  local engine = M.engine()
  local s = M.settings()
  local lines = {
    { text = "Engine", style = "Title" },
    "  "
      .. (
        engine and table.concat(engine, " ")
        or "not found: paw.opt.midilsp_cmd, $MIDI_LSP_ENGINE or reaper-midi-lsp on the PATH"
      ),
    "",
    { text = "Settings, kept with the project", style = "Title" },
    "  preset " .. s.preset,
  }
  for id, r in pairs(s.rules) do
    lines[#lines + 1] = string.format("  rule %s %s", id, r.enabled and "on" or "off")
  end
  lines[#lines + 1] = ""
  for _, line in ipairs(paw.lsp.info_lines()) do
    lines[#lines + 1] = line
  end
  return lines
end

-- Problems --------------------------------------------------------------------------

--- Every server's diagnostics (and any other plugin's), each followed by
--- its fixes: Enter on a diagnostic goes to it, on a fix applies it.
function M.problems()
  local items = {}
  for _, d in ipairs(paw.diagnostic.get()) do
    local ok, c = pcall(api.clip_get, d.clip)
    local where = ok and string.format("%s %s", c.name, paw.time.format(c.start + d.at)) or "?"
    items[#items + 1] = {
      text = string.format(
        "%-7s %-16s %s",
        paw.diagnostic.severity[d.severity],
        paw.util.fit(where, 16),
        paw.diagnostic.format(d):gsub("^%a+ ", "")
      ),
      diagnostic = d,
    }
    for _, fix in ipairs(d.fixes) do
      items[#items + 1] = { text = "        fix: " .. tostring(fix.title), diagnostic = d, fix = fix }
    end
  end
  if #items == 0 then return paw.notify("no problems") end
  paw.pick({
    title = "Problems",
    items = items,
    on_choose = function(item)
      if not item then return end
      if item.fix then
        paw.diagnostic.apply(item.diagnostic, item.fix)
      else
        paw.diagnostic.show(item.diagnostic)
      end
    end,
  })
end

-- Settings follow the project: another project, other settings.
paw.on("project.loaded", function()
  M.configure()
  for _, c in ipairs(paw.lsp.clients()) do
    if c.name == M.LSP and c.status == "running" then
      paw.lsp.notify(M.LSP, "workspace/didChangeConfiguration", { settings = wire() })
    end
  end
end)

return M
