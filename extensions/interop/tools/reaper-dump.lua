-- A REAPER startup script (__startup.lua) that opens one project and
-- writes what REAPER read from it to a text file, then quits. Run by
-- reaper-open.sh; RPP_FILE is the project, RPP_DUMP the file to write.
--
-- Each line is a kind and its values, separated by tabs:
--   tempo bpm num den
--   tempomarker seconds bpm num den linear
--   marker seconds name color             region start end name color
--   track index name volume pan mute solo depth color mainsend fx-count
--   fx track index name
--   send track dest volume mute
--   env track name point-count
--   point track env-name seconds value shape
--   item track index position length loop fadein fadeout volume mute offset rate pitch file
--   note track item start end pitch velocity channel muted     (seconds)
--   cc track item seconds status channel data1 data2
--   end
local file, dump = os.getenv("RPP_FILE"), os.getenv("RPP_DUMP")
local build = os.getenv("RPP_BUILD")
if build and build ~= "" then
  -- Make a project with a script of REAPER's API, and save it as RPP_FILE.
  dofile(build)
  reaper.Main_SaveProjectEx(0, file, 0)
else
  reaper.Main_openProject("noprompt:" .. file)
end
local out = assert(io.open(dump .. ".part", "w"))
local function w(...)
  local parts = { ... }
  for i, v in ipairs(parts) do
    if type(v) == "number" then
      parts[i] = (string.format("%.6f", v):gsub("%.?0+$", ""))
      if parts[i] == "-0" or parts[i] == "" then parts[i] = "0" end
    else
      parts[i] = tostring(v)
    end
  end
  out:write(table.concat(parts, "\t"), "\n")
end
local function b(x) return x and 1 or 0 end
-- A custom colour as #rrggbb (REAPER's own reading of the native value), or "none".
local function colour(native)
  native = math.floor(native)
  if native & 0x1000000 == 0 then return "none" end
  local r, g, bl = reaper.ColorFromNative(native & 0xffffff)
  return string.format("#%02x%02x%02x", r, g, bl)
end

local num, den = reaper.TimeMap_GetTimeSigAtTime(0, 0)
w("tempo", reaper.Master_GetTempo(), num, den)
for i = 0, reaper.CountTempoTimeSigMarkers(0) - 1 do
  local _, t, _, _, bpm_i, n, d, linear = reaper.GetTempoTimeSigMarker(0, i)
  w("tempomarker", t, bpm_i, n, d, b(linear))
end
local i = 0
while true do
  local ret, isrgn, pos, rgnend, name, _, color = reaper.EnumProjectMarkers3(0, i)
  if ret == 0 then break end
  if isrgn then w("region", pos, rgnend, name, color) else w("marker", pos, name, color) end
  i = i + 1
end

local function track_number(tr)
  if tr == reaper.GetMasterTrack(0) then return 0 end
  return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
end

local function envelopes(tr, index)
  for e = 0, reaper.CountTrackEnvelopes(tr) - 1 do
    local env = reaper.GetTrackEnvelope(tr, e)
    local _, name = reaper.GetEnvelopeName(env)
    local n = reaper.CountEnvelopePoints(env)
    w("env", index, name, n)
    for p = 0, n - 1 do
      local _, t, v, shape = reaper.GetEnvelopePoint(env, p)
      -- A volume envelope with fader scaling gives its values scaled: as amplitudes.
      if reaper.GetEnvelopeScalingMode(env) == 1 then v = reaper.ScaleFromEnvelopeMode(1, v) end
      w("point", index, name, t, v, shape)
    end
  end
end

local master = reaper.GetMasterTrack(0)
w("track", 0, "MASTER", reaper.GetMediaTrackInfo_Value(master, "D_VOL"), reaper.GetMediaTrackInfo_Value(master, "D_PAN"),
  reaper.GetMediaTrackInfo_Value(master, "B_MUTE"), 0, 0, 0, 1, reaper.TrackFX_GetCount(master))
for f = 0, reaper.TrackFX_GetCount(master) - 1 do
  local _, name = reaper.TrackFX_GetFXName(master, f, "")
  w("fx", 0, f + 1, name)
end
envelopes(master, 0)

for t = 0, reaper.CountTracks(0) - 1 do
  local tr = reaper.GetTrack(0, t)
  local index = t + 1
  local _, name = reaper.GetTrackName(tr)
  w("track", index, name, reaper.GetMediaTrackInfo_Value(tr, "D_VOL"), reaper.GetMediaTrackInfo_Value(tr, "D_PAN"),
    reaper.GetMediaTrackInfo_Value(tr, "B_MUTE"), reaper.GetMediaTrackInfo_Value(tr, "I_SOLO"),
    reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH"), colour(reaper.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR")),
    reaper.GetMediaTrackInfo_Value(tr, "B_MAINSEND"), reaper.TrackFX_GetCount(tr))
  for f = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local _, fxname = reaper.TrackFX_GetFXName(tr, f, "")
    w("fx", index, f + 1, fxname)
  end
  for s = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
    local dest = reaper.GetTrackSendInfo_Value(tr, 0, s, "P_DESTTRACK")
    w("send", index, track_number(dest), reaper.GetTrackSendInfo_Value(tr, 0, s, "D_VOL"),
      reaper.GetTrackSendInfo_Value(tr, 0, s, "B_MUTE"))
  end
  envelopes(tr, index)
  for it = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local item = reaper.GetTrackMediaItem(tr, it)
    local take = reaper.GetActiveTake(item)
    local function iv(key) return reaper.GetMediaItemInfo_Value(item, key) end
    local function tv(key) return take and reaper.GetMediaItemTakeInfo_Value(take, key) or 0 end
    local src = take and reaper.GetMediaItemTake_Source(take)
    local srcfile = src and reaper.GetMediaSourceFileName(src, "") or ""
    w("item", index, it + 1, iv("D_POSITION"), iv("D_LENGTH"), iv("B_LOOPSRC"), iv("D_FADEINLEN"), iv("D_FADEOUTLEN"),
      iv("D_VOL") * math.abs(tv("D_VOL")), iv("B_MUTE"), tv("D_STARTOFFS"), tv("D_PLAYRATE"), tv("D_PITCH"), srcfile)
    if take and reaper.TakeIsMIDI(take) then
      local _, notes, ccs = reaper.MIDI_CountEvts(take)
      for n = 0, notes - 1 do
        local _, _, muted, s, e, chan, pitch, vel = reaper.MIDI_GetNote(take, n)
        w("note", index, it + 1, reaper.MIDI_GetProjTimeFromPPQPos(take, s), reaper.MIDI_GetProjTimeFromPPQPos(take, e),
          pitch, vel, chan, b(muted))
      end
      for c = 0, ccs - 1 do
        local _, _, _, ppq, status, chan, d1, d2 = reaper.MIDI_GetCC(take, c)
        w("cc", index, it + 1, reaper.MIDI_GetProjTimeFromPPQPos(take, ppq), status, chan, d1, d2)
      end
    end
  end
end
w("end")
out:close()
os.rename(dump .. ".part", dump)
reaper.Main_OnCommand(40004, 0) -- File: Quit
