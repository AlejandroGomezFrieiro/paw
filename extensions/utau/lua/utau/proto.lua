-- The paw-utau-engine wire protocol, version 1.0, written down by engine/PawUtau.Protocol/Messages.cs.
--
-- A frame is a little-endian u32 length, a type byte and a msgpack array
-- whose fields are positional. Frames of type 0x80 and up carry a binary
-- payload after their msgpack header. Times are OpenUtau ticks (480 per
-- beat) inside a part, and project seconds for audio.
local mp = require("utau.msgpack")

local M = {}

M.VERSION = 0x00010000
M.TICKS = 480

M.type = {
  Hello = 0x01,
  Error = 0x02,
  Log = 0x03,
  Ping = 0x04,
  Pong = 0x05,
  SyncProject = 0x10,
  ApplyDelta = 0x11,
  Transport = 0x12,
  SetTrackConfig = 0x13,
  RequestSingers = 0x14,
  RequestRenderers = 0x15,
  RequestPhonemizers = 0x16,
  RunBatchEdit = 0x17,
  SetRenderPolicy = 0x18,
  Shutdown = 0x19,
  Audition = 0x1A,
  Invalidate = 0x1B,
  PhraseLayout = 0x40,
  Phonemes = 0x41,
  RenderedPitch = 0x42,
  Progress = 0x43,
  SingerList = 0x44,
  RendererList = 0x45,
  PhonemizerList = 0x46,
  BatchEditResult = 0x47,
  PhraseAudio = 0x80,
}
local T = M.type
M.name = {}
for name, code in pairs(T) do
  M.name[code] = name
end

M.state = { pending = 0, rendering = 1, draft = 2, final = 3, error = 4 }
M.state_name = { [0] = "pending", "rendering", "draft", "final", "error" }

--- One frame around an encoded body.
function M.frame(kind, body) return mp.le32(#body + 1) .. string.char(kind) .. body end

-- Encoders, by the struct names of the protocol --------------------------------

local function config(c)
  local options = {}
  for key, value in pairs(c.options or {}) do
    options[#options + 1] = { key, tostring(value) }
  end
  table.sort(options, function(a, b) return a[1] < b[1] end)
  return mp.array(7)
    .. mp.str(c.singer or "")
    .. mp.str(c.phonemizer or "")
    .. mp.str(c.renderer or "")
    .. mp.str(c.resampler or "")
    .. mp.str(c.wavtool or "")
    .. mp.float(c.pitch_bend_range or 12)
    .. mp.list(options, function(kv) return mp.array(2) .. mp.str(kv[1]) .. mp.str(kv[2]) end)
end

local function track_info(t)
  return mp.array(4) .. mp.str(t.id) .. mp.str(t.name or "") .. mp.bool(t.muted) .. config(t.config or {})
end

local function vpart_info(p)
  return mp.array(6)
    .. mp.str(p.id)
    .. mp.str(p.track)
    .. mp.int(p.pos)
    .. mp.int(p.dur)
    .. mp.str(p.name or "")
    .. mp.bool(p.muted)
end

local function note_msg(n)
  return mp.array(5) .. mp.uint(n.id) .. mp.int(n.pos) .. mp.int(n.dur) .. mp.int(n.tone) .. mp.bin(n.payload)
end

local function knot(k)
  return mp.array(4) .. mp.double(k[1]) .. mp.double(k[2]) .. mp.uint(k[3] or 1) .. mp.float(k[4] or 0)
end

local function curve(c) return mp.array(2) .. mp.str(c.abbr) .. mp.list(c.knots, knot) end

local function tempos(list)
  return mp.list(list, function(t) return mp.array(3) .. mp.int(t.tick) .. mp.double(t.bpm) .. mp.double(t.sec) end)
end

local function sigs(list)
  return mp.list(list, function(s) return mp.array(3) .. mp.int(s.tick) .. mp.uint(s.num) .. mp.uint(s.den) end)
end

local function vpart_data(p)
  return mp.array(3) .. vpart_info(p) .. mp.list(p.notes, note_msg) .. mp.list(p.curves, curve)
end

local function vpart_ids(entry) return mp.array(2) .. mp.str(entry.vpart) .. mp.list(entry.ids, mp.uint) end

local function vpart_notes(entry) return mp.array(2) .. mp.str(entry.vpart) .. mp.list(entry.notes, note_msg) end

local function vpart_curves(entry) return mp.array(2) .. mp.str(entry.vpart) .. mp.list(entry.curves, curve) end

local encode = {}
M.encode = encode

function encode.hello(pid)
  return M.frame(
    T.Hello,
    mp.array(6)
      .. mp.uint(M.VERSION)
      .. mp.uint(0)
      .. mp.str("paw-utau 0.1")
      .. mp.str("")
      .. mp.uint(pid or 0)
      .. mp.array(0)
  )
end

--- `{ seq, tempos, sigs, tracks, parts }`
function encode.sync_project(s)
  return M.frame(
    T.SyncProject,
    mp.array(6)
      .. mp.uint(s.seq)
      .. mp.str(s.project or "")
      .. tempos(s.tempos)
      .. sigs(s.sigs)
      .. mp.list(s.tracks, track_info)
      .. mp.list(s.vparts, vpart_data)
  )
end

--- `{ seq, tempos?, sigs?, remove_tracks, upsert_tracks, remove_parts,
--- upsert_parts, remove_notes, upsert_notes, curves }`
function encode.apply_delta(d)
  return M.frame(
    T.ApplyDelta,
    mp.array(11)
      .. mp.uint(d.seq)
      .. mp.bool(d.tempos ~= nil)
      .. tempos(d.tempos or {})
      .. sigs(d.sigs or {})
      .. mp.strs(d.remove_tracks or {})
      .. mp.list(d.upsert_tracks or {}, track_info)
      .. mp.strs(d.remove_vparts or {})
      .. mp.list(d.upsert_vparts or {}, vpart_info)
      .. mp.list(d.remove_notes or {}, vpart_ids)
      .. mp.list(d.upsert_notes or {}, vpart_notes)
      .. mp.list(d.curves or {}, vpart_curves)
  )
end

function encode.transport(playing, pos_sec, cursor_sec)
  return M.frame(T.Transport, mp.array(3) .. mp.bool(playing) .. mp.double(pos_sec) .. mp.double(cursor_sec))
end

function encode.track_config(track_id, c) return M.frame(T.SetTrackConfig, mp.array(2) .. mp.str(track_id) .. config(c)) end

function encode.request_singers(rescan) return M.frame(T.RequestSingers, mp.array(1) .. mp.bool(rescan)) end

--- `{ draft, draft_steps, final_steps, final_delay_ms, threads, ahead }`
function encode.request_renderers() return M.frame(T.RequestRenderers, mp.array(0)) end

function encode.request_phonemizers() return M.frame(T.RequestPhonemizers, mp.array(0)) end

--- A batch edit the engine runs, answered by `BatchEditResult` with the
--- same `request`: `{ request, name, parts = { part ids }, notes = { note ids }, args = json }`.
--- The engine knows "retake" (AI pitch and timbre takes) and "graph".
function encode.run_batch_edit(b)
  return M.frame(
    T.RunBatchEdit,
    mp.array(5)
      .. mp.uint(b.request)
      .. mp.str(b.name)
      .. mp.strs(b.vparts or {})
      .. mp.list(b.notes or {}, mp.uint)
      .. mp.str(b.args or "")
  )
end

--- Sing one note with a track's voice, outside the project: answered by a
--- `PhraseAudio` with `purpose` 1 and the request id as its hash.
function encode.audition(request, track_id, tone, lyric, ms)
  return M.frame(
    T.Audition,
    mp.array(5) .. mp.uint(request) .. mp.str(track_id) .. mp.int(tone) .. mp.str(lyric or "a") .. mp.uint(ms or 500)
  )
end

function encode.render_policy(p)
  return M.frame(
    T.SetRenderPolicy,
    mp.array(6)
      .. mp.bool(p.draft ~= false)
      .. mp.uint(p.draft_steps or 4)
      .. mp.uint(p.final_steps or 0)
      .. mp.uint(p.final_delay_ms or 1500)
      .. mp.uint(p.threads or 0)
      .. mp.bool(p.ahead ~= false)
  )
end

function encode.invalidate(track_id, vpart_id)
  return M.frame(T.Invalidate, mp.array(2) .. mp.str(track_id) .. mp.str(vpart_id or ""))
end

function encode.pong(nonce) return M.frame(T.Pong, mp.array(1) .. mp.uint(nonce)) end

function encode.shutdown() return M.frame(T.Shutdown, mp.array(0)) end

-- Decoders: positional arrays into named fields --------------------------------

local function named(fields, list)
  local out = {}
  for i, field in ipairs(fields) do
    out[field] = list and list[i]
  end
  return out
end

local function each(list, fn)
  local out = {}
  for i, item in ipairs(list or {}) do
    out[i] = fn(item)
  end
  return out
end

local decode = {}
M.decode = decode

decode[T.Hello] = function(a) return named({ "version", "role", "engine", "openutau", "pid", "capabilities" }, a) end
decode[T.Error] = function(a) return named({ "code", "message", "fatal", "ref_seq" }, a) end
decode[T.Log] = function(a) return named({ "level", "source", "message" }, a) end
decode[T.Ping] = function(a) return named({ "nonce" }, a) end
decode[T.Progress] = function(a) return named({ "task", "label", "fraction", "queued" }, a) end

decode[T.PhraseLayout] = function(a)
  local m = named({ "track", "seq", "phrases" }, a)
  m.phrases = each(m.phrases, function(p)
    local s = named({ "hash", "start", "stop", "state" }, p)
    s.hash = mp.key(s.hash)
    return s
  end)
  return m
end

decode[T.Phonemes] = function(a)
  local m = named({ "vpart", "seq", "notes" }, a)
  m.notes = each(m.notes, function(n)
    local note = named({ "id", "phonemes" }, n)
    note.phonemes = each(
      note.phonemes,
      function(p) return named({ "phoneme", "alias", "start", "stop", "preutter", "overlap", "flags" }, p) end
    )
    return note
  end)
  return m
end

decode[T.RenderedPitch] = function(a)
  local m = named({ "vpart", "seq", "step", "start", "cents" }, a)
  m.cents = mp.floats(m.cents or "")
  return m
end

decode[T.SingerList] = function(a)
  return each(a[1], function(s)
    local singer = named({ "id", "name", "type", "image", "location", "author", "colors", "subbanks", "phonemizer" }, s)
    singer.subbanks = each(singer.subbanks, function(b) return named({ "color", "prefix", "suffix" }, b) end)
    return singer
  end)
end

decode[T.RendererList] = function(a)
  return {
    renderers = each(a[1], function(r)
      local renderer = named({ "id", "name", "singer_types", "expressions" }, r)
      renderer.expressions = each(
        renderer.expressions,
        function(e) return named({ "abbr", "name", "min", "max", "default", "kind", "options" }, e) end
      )
      return renderer
    end),
    resamplers = a[2] or {},
    wavtools = a[3] or {},
  }
end

decode[T.PhonemizerList] = function(a)
  return each(a[1], function(p) return named({ "id", "name", "tag", "language" }, p) end)
end

decode[T.BatchEditResult] = function(a) return named({ "request", "ok", "message", "remove_notes", "upsert_notes" }, a) end

decode[T.PhraseAudio] = function(a)
  local m = named({ "track", "hash", "start", "rate", "channels", "quality", "frames", "seq", "purpose" }, a)
  m.hash = mp.key(m.hash)
  return m
end

--- Take every whole frame from the front of `buf`. Returns the frames as
--- `{ type, body, raw }` and what is left over.
function M.split(buf)
  local frames, pos = {}, 1
  while #buf - pos + 1 >= 5 do
    local len = mp.read_le32(buf, pos)
    if len < 1 or len > 256 * 1024 * 1024 then error("bad frame length " .. len) end
    if #buf - pos + 1 < 4 + len then break end
    local kind = buf:byte(pos + 4)
    local first, last = pos + 5, pos + 3 + len
    local frame = { type = kind }
    if kind >= 0x80 then
      local meta_len = mp.read_le32(buf, first)
      frame.body = buf:sub(first + 4, first + 3 + meta_len)
      frame.raw = buf:sub(first + 4 + meta_len, last)
    else
      frame.body = buf:sub(first, last)
    end
    frames[#frames + 1] = frame
    pos = last + 1
  end
  return frames, buf:sub(pos)
end

--- A frame's message as named fields, or nil for a type this side ignores.
function M.message(frame)
  local fn = decode[frame.type]
  if not fn then return nil end
  local list = mp.decode(frame.body, 1)
  return fn(list)
end

return M
