-- MIDI LSP's checks of a rendered master, as one-shot servers on this
-- program's `render` subject (docs/servers.md there, "One-shot servers"):
--
--   midilsp-delivery  reaper-midi-lsp-delivery: loudness, true peak, clipping,
--                     loudness range against a delivery target (analysis/delivery.py)
--   midilsp-settings  reaper-midi-lsp-settings: the render's format, dither,
--                     normalising and sample rate, and a limiter on the master
--                     (settings_check/), given the plain settings it reads from
--                     REAPER, made here from the render's options and the master's devices
--
-- Each finding becomes a diagnostic on the render, at the time it names,
-- with a fix wherever one can be made: the master lowered by what is over,
-- a render made again with dither or at the project's rate, a bypassed
-- limiter switched on.
local api = paw.api
local A = paw.address

local M = { DELIVERY = "midilsp-delivery", SETTINGS = "midilsp-settings" }

paw.option.define("midilsp_render_checks", true)    -- check every render with the engine's delivery and settings checks
paw.option.define("midilsp_delivery_target", "spotify") -- "spotify", "ebu-r128", or "" for information only

-- A program installed beside the engine (as the engine's package installs
-- them), else on the PATH.
local function tool(name)
  local engine = require("midilsp").engine()
  local dir = engine and engine[1]:match("^(.*)/[^/]+$")
  if dir then
    local f = io.open(dir .. "/" .. name)
    if f then
      f:close()
      return dir .. "/" .. name
    end
  end
  local found = io.popen("command -v " .. name .. " 2>/dev/null"):read("*l")
  return found and found ~= "" and found or nil
end

-- The master lowered by `db`, as a fix.
local function lower_master(db)
  if not db or db <= 0 then return nil end
  db = math.ceil(db * 10) / 10
  return { title = string.format("Lower the master by %.1f dB", db),
    edit = { { uri = A.track(0), set = { volume = api.track_get(0, "volume") - db } } } }
end

-- Where a finding is: the render, at its time.
local function located(doc, f)
  return { uri = doc.address, selector = f.time_s and { seconds = { f.time_s, f.time_s } } or nil }
end

function M.delivery_diagnostic(f, doc)
  local fix
  if f.rule == "delivery.true_peak" and f.limit and f.value and f.value > f.limit then
    fix = lower_master(f.value - f.limit + 0.1)
  elseif f.rule == "delivery.integrated" and f.limit and f.value and f.value > f.limit and f.severity ~= "info" then
    fix = lower_master(f.value - f.limit)
  elseif f.rule == "delivery.clip" and doc.data.peak then
    fix = lower_master(math.max(1, 20 * math.log10(math.max(doc.data.peak, 1e-9)) + 1))
  end
  return { location = located(doc, f), fixes = { fix } }
end


-- The render's file format as REAPER's RENDER_FORMAT has it (formats.py there).
local function format_of(r)
  local kind = tostring(r.format or (r.path or ""):match("%.(%w+)$") or "wav"):lower()
  if kind == "flac" then
    local bits = r.bits or 24
    return paw.bytes.base64("calf" .. string.char(bits % 256, math.floor(bits / 256) % 256, 0, 0))
  elseif kind == "mp3" then return "l3pm"
  elseif kind == "ogg" then return "vggo"
  elseif kind == "opus" then return "SggO"
  end
  local bits = r.bits or 24
  return paw.bytes.base64("evaw" .. string.char(bits == 32 and 32 or bits))
end

--- The plain settings `reaper-midi-lsp-settings --settings-json` reads, from
--- a render subject: the options the render was made with and the master's
--- devices. Normalising is REAPER's peak mode for `normalize`, LUFS-I with
--- the peak as brickwall for `loudness`.
function M.settings_of(doc)
  local r = doc.data
  local opts = r.opts or {}
  local norm, target, brickwall = 0, 0, 0
  if opts.loudness then
    norm, target = 1, 10 ^ (opts.loudness / 20)
    if opts.normalize then norm, brickwall = norm + 64, 10 ^ (opts.normalize / 20) end
  elseif opts.normalize then
    norm, target = 1 + 4, 10 ^ (opts.normalize / 20)
  end
  local fx = {}
  for _, d in ipairs(r.master and r.master.devices or {}) do
    fx[#fx + 1] = { name = d.name, ident = d.kind or "", original_name = d.name, enabled = not d.bypass, offline = false }
  end
  return {
    schema = 1, source = "paw",
    project_srate = api.engine_get().sample_rate, project_srate_forced = true,
    render = {
      settings = 0, srate = opts.sample_rate or 0, dither = opts.dither and 1 or 0,
      normalize = norm, normalize_target = target, brickwall = brickwall,
      format = format_of(r), format2 = "",
    },
    master = { fx_enabled = true, fx = fx },
  }
end

function M.settings_diagnostic(f, doc)
  local fix
  if f.rule == "render.no_dither" then
    fix = { title = "Render it again with dither", edit = { { uri = doc.address, set = { dither = true } } } }
  elseif f.rule == "render.srate_mismatch" and f.limit then
    fix = { title = string.format("Render it again at %d Hz", f.limit), edit = { { uri = doc.address, set = { sample_rate = f.limit } } } }
  elseif f.rule == "master.limiter_bypassed" then
    local i = tonumber(tostring(f.where or ""):match("(%d+)$"))
    local d = i and doc.data.master and doc.data.master.devices[i]
    if d then fix = { title = "Switch " .. d.name .. " on", edit = { { uri = A.device(d.id), set = { bypass = false } } } } end
  end
  return { location = { uri = doc.address }, fixes = { fix } }
end

--- Configure both checks (when their programs are there) and start them.
function M.start()
  if not paw.opt.midilsp_render_checks then return end
  local delivery, settings = tool("reaper-midi-lsp-delivery"), tool("reaper-midi-lsp-settings")
  if delivery then
    local target = paw.opt.midilsp_delivery_target
    paw.lsp.config(M.DELIVERY, {
      kind = "oneshot", cmd = { delivery, "--target", "{target}", "{file}" },
      attach = { subjects = { "render" } },
      settings = { target = target ~= "" and target or nil },
      -- It reads WAV files.
      accepts = function(doc) return tostring(doc.data.path):lower():match("%.wav$") ~= nil end,
      timeout_ms = 120000,
      diagnostic = M.delivery_diagnostic,
    })
    paw.lsp.enable(M.DELIVERY)
  end
  if settings then
    paw.lsp.config(M.SETTINGS, {
      kind = "oneshot", cmd = { settings, "--settings-json", "{input}" },
      attach = { subjects = { "render" } },
      input = M.settings_of,
      timeout_ms = 30000,
      diagnostic = M.settings_diagnostic,
    })
    paw.lsp.enable(M.SETTINGS)
  end
end

function M.stop()
  paw.lsp.enable(M.DELIVERY, false)
  paw.lsp.enable(M.SETTINGS, false)
end

return M
