-- A ReaScript that makes a small song with REAPER's own API, for the test
-- that imports a project which REAPER saved (reaper-open.sh ... build.lua).
-- It uses media/tone.wav beside the project.
local dir = os.getenv("RPP_FILE"):match("^(.*)/[^/]*$")
reaper.SetCurrentBPM(0, 110, false)
reaper.SetTempoTimeSigMarker(0, -1, 0, -1, -1, 110, 3, 4, false)

local function track(i, name)
  reaper.InsertTrackAtIndex(i, true)
  local tr = reaper.GetTrack(0, i)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr
end

local bus = track(0, "Bus")
local keys = track(1, "Keys")
local gtr = track(2, "Gtr")
local verb = track(3, "Verb")
reaper.SetMediaTrackInfo_Value(bus, "I_FOLDERDEPTH", 1)
reaper.SetMediaTrackInfo_Value(gtr, "I_FOLDERDEPTH", -1)
reaper.SetMediaTrackInfo_Value(bus, "I_CUSTOMCOLOR", reaper.ColorToNative(200, 40, 10) | 0x1000000)
reaper.SetMediaTrackInfo_Value(keys, "D_VOL", 0.5)
reaper.SetMediaTrackInfo_Value(keys, "D_PAN", -0.25)
reaper.SetMediaTrackInfo_Value(gtr, "B_MUTE", 1)
local send = reaper.CreateTrackSend(keys, verb)
reaper.SetTrackSendInfo_Value(keys, 0, send, "D_VOL", 0.25)
reaper.SetTrackSendInfo_Value(keys, 0, send, "I_SENDMODE", 3)

-- A MIDI item: notes, a controller and the pitch wheel.
local item = reaper.CreateNewMIDIItemInProj(keys, 60 / 110 * 2, 60 / 110 * 6, false)
local take = reaper.GetActiveTake(item)
local function ppq(qn) return reaper.MIDI_GetPPQPosFromProjQN(take, qn) end
reaper.MIDI_InsertNote(take, false, false, ppq(2), ppq(3), 0, 60, 100, true)
reaper.MIDI_InsertNote(take, false, false, ppq(3.5), ppq(4), 1, 64, 80, true)
reaper.MIDI_InsertCC(take, false, false, ppq(2), 0xB0, 0, 1, 64, true)
reaper.MIDI_InsertCC(take, false, false, ppq(3), 0xE0, 0, 0, 96, true)
reaper.MIDI_Sort(take)
reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "chords", true)

-- An audio item: a fade in, half a second into the file.
local audio = reaper.AddMediaItemToTrack(gtr)
local atake = reaper.AddTakeToMediaItem(audio)
reaper.SetMediaItemTake_Source(atake, reaper.PCM_Source_CreateFromFile(dir .. "/media/tone.wav"))
reaper.SetMediaItemInfo_Value(audio, "D_POSITION", 1)
reaper.SetMediaItemInfo_Value(audio, "D_LENGTH", 1)
reaper.SetMediaItemInfo_Value(audio, "D_FADEINLEN", 0.25)
reaper.SetMediaItemTakeInfo_Value(atake, "D_STARTOFFS", 0.5)

-- The volume envelope of Keys, a marker and a region.
reaper.SetOnlyTrackSelected(keys)
reaper.Main_OnCommand(40406, 0) -- Track: Toggle track volume envelope visible
local env = reaper.GetTrackEnvelopeByName(keys, "Volume")
if env then
  -- Values in the scaling of the envelope (a fader's), from amplitudes.
  local mode = reaper.GetEnvelopeScalingMode(env)
  reaper.InsertEnvelopePoint(env, 0, reaper.ScaleToEnvelopeMode(mode, 1), 0, 0, false, true)
  reaper.InsertEnvelopePoint(env, 2, reaper.ScaleToEnvelopeMode(mode, 0.5), 1, 0, false, true)
  reaper.InsertEnvelopePoint(env, 4, reaper.ScaleToEnvelopeMode(mode, 0.25), 0, 0, false, true)
  reaper.Envelope_SortPoints(env)
end
reaper.AddProjectMarker2(0, false, 1.5, 0, "Verse", 1, 0)
reaper.AddProjectMarker2(0, true, 3, 5, "Chorus", 2, 0)
reaper.UpdateArrange()
