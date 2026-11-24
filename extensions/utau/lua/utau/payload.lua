-- Per-note singing data: where it lives in the project, and the payload the
-- engine reads (`NotePayload` in engine/PawUtau.Protocol).
--
-- A note's lyric is `note.lyric`. Everything else the engine reads per note
-- is in `note.meta.utau`, in the shape `paw-utau-engine --convert` writes, so
-- an imported project is stored as it comes:
--
--   tu = 20                                      tuning, cents
--   po = "OpenUtau.Core.DiffSinger..."           phonemizer for this note
--   vb = { length, period, depth, in, out, shift, drift, vol_link }
--   pp = { snap = true, pts = { { x_ms, y_tenths, shape }, ... } }
--   ex = { { "vel", 120, -1 }, ... }             expression, value, phoneme (-1: all)
--   ph = { { index = 0, phoneme = "a", offset = 10, pre = 5, ovl = 2, atk = 0, rel = 0 }, ... }
local mp = require("utau.msgpack")

local M = {}

--- The lyric a note sings, falling back to `default`.
function M.lyric(note, default)
  local lyric = note.lyric
  if type(lyric) ~= "string" or lyric == "" then return default end
  return lyric
end

--- The utau properties of a note, or an empty table.
function M.props(note) return note.meta and type(note.meta.utau) == "table" and note.meta.utau or {} end

local PH_FIELDS = { { "phoneme", 1 }, { "offset", 2 }, { "pre", 4 }, { "ovl", 8 }, { "atk", 16 }, { "rel", 32 } }

--- The msgpack map the engine reads for one note.
function M.encode(id, lyric, props)
  local entries, out = {}, {}
  local function add(key, value)
    entries[#entries + 1] = true
    out[#out + 1] = mp.str(key) .. value
  end
  add("v", mp.uint(1))
  add("id", mp.uint(id))
  add("ly", mp.str(lyric))
  if type(props.po) == "string" and props.po ~= "" then add("po", mp.str(props.po)) end
  if tonumber(props.tu) and props.tu ~= 0 then add("tu", mp.int(props.tu)) end
  if type(props.pp) == "table" and type(props.pp.pts) == "table" and #props.pp.pts > 0 then
    add(
      "pp",
      mp.array(2)
        .. mp.bool(props.pp.snap ~= false)
        .. mp.list(
          props.pp.pts,
          function(p) return mp.array(3) .. mp.float(p[1]) .. mp.float(p[2]) .. mp.uint(p[3] or 0) end
        )
    )
  end
  if type(props.vb) == "table" and (props.vb[1] or 0) > 0 then
    local vb = { mp.array(8) }
    for i = 1, 8 do
      vb[i + 1] = mp.float(props.vb[i] or 0)
    end
    add("vb", table.concat(vb))
  end
  if type(props.ph) == "table" and #props.ph > 0 then
    add(
      "ph",
      mp.list(props.ph, function(p)
        local mask = 0
        for _, f in ipairs(PH_FIELDS) do
          if p[f[1]] ~= nil then mask = mask + f[2] end
        end
        return mp.array(8)
          .. mp.uint(p.index or 0)
          .. mp.uint(mask)
          .. mp.str(p.phoneme or "")
          .. mp.int(p.offset or 0)
          .. mp.float(p.pre or 0)
          .. mp.float(p.ovl or 0)
          .. mp.float(p.atk or 0)
          .. mp.float(p.rel or 0)
      end)
    )
  end
  if type(props.ex) == "table" and #props.ex > 0 then
    add(
      "ex",
      mp.list(props.ex, function(e) return mp.array(3) .. mp.str(e[1]) .. mp.float(e[2]) .. mp.int(e[3] or -1) end)
    )
  end
  return mp.map(#entries) .. table.concat(out)
end

return M
