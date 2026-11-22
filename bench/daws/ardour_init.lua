ardour {
  ["type"] = "SessionInit",
  name = "Paw Demo",
  description = [[The paw demo song: its MIDI file as tracks with ACE Reasonable Synth, ACE Delay on the keys, a reverb bus, looped and playing]],
}

-- DEMO_MID, DAW_OUT and DAW_VIEW come in through the environment.
function factory()
  return function()
    local log = io.open(os.getenv("DAW_OUT") .. "/started", "w")
    local function say(...)
      log:write(string.format(...) .. "\n")
      log:flush()
    end
    local ok, err = pcall(function()
      local files = C.StringVector()
      files:push_back(os.getenv("DEMO_MID"))
      Editor:do_import(
        files,
        Editing.ImportDistinctFiles,
        Editing.ImportAsTrack,
        ARDOUR.SrcQuality.SrcBest,
        ARDOUR.MidiTrackNameSource.SMFTrackName,
        ARDOUR.MidiTempoMapDisposition.SMFTempoUse,
        Temporal.timepos_t(0),
        ARDOUR.PluginInfo(),
        ARDOUR.Track(),
        false
      )

      local bus = Session:new_audio_route(
        2,
        2,
        ARDOUR.RouteGroup(),
        1,
        "Reverb",
        ARDOUR.PresentationInfo.Flag.AudioBus,
        ARDOUR.PresentationInfo.max_order
      ):front()
      bus:add_processor_by_index(
        ARDOUR.LuaAPI.new_plugin(Session, "urn:ardour:a-reverb", ARDOUR.PluginType.LV2, ""),
        0,
        nil,
        true
      )
      local n = 0
      for r in Session:get_routes():iter() do
        local name = r:name()
        if not r:to_track():to_midi_track():isnil() then
          local synth = ARDOUR.LuaAPI.new_plugin(Session, "ACE Reasonable Synth", ARDOUR.PluginType.LV2, "")
          if synth:isnil() then say("no synth for %s", name) end
          r:add_processor_by_index(synth, 0, nil, true)
        end
        if name:find("Keys") then
          r:add_processor_by_index(
            ARDOUR.LuaAPI.new_plugin(Session, "urn:ardour:a-delay", ARDOUR.PluginType.LV2, ""),
            -1,
            nil,
            true
          )
        end
        if r:to_track():isnil() == false and not name:find("Bass") then
          Session:add_internal_send(bus, r:main_outs(), r)
        end
        n = n + 1
        local procs, i = {}, 0
        while true do
          local p = r:nth_plugin(i)
          if p:isnil() then break end
          procs[#procs + 1] = p:name()
          i = i + 1
        end
        say("route %s: %s", name, table.concat(procs, ", "))
      end

      local sr = Session:nominal_sample_rate()
      local stop = math.floor(32 * 60 / 108 * sr + 0.5)
      Editor:set_loop_range(Temporal.timepos_t(0), Temporal.timepos_t(stop), "Loop")
      if os.getenv("DAW_VIEW") == "mixer" then Editor:access_action("Common", "show-mixer") end
      say("routes %d, loop to %d at %d Hz", n, stop, sr)
    end)
    if not ok then say("error: %s", tostring(err)) end
    log:close()
  end
end
