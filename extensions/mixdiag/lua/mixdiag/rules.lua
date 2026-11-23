-- The built-in rules. Each looks at one measurement (`ctx.result`, see the
-- README for its fields) and the project, and calls `add` with findings:
--
--   add({ severity = "warn", message = "what, how much, where", fix = "what to do",
--         beat = 44, part = 3 })
--
-- Thresholds are fields of the rule, so a configuration can change them:
--   require("mixdiag").rules.dc.limit = 0.005
local api = paw.api
local mixdiag = require("mixdiag")
local rules = mixdiag.rules

local function db(x) return string.format("%+.1f", x) end
local function lu(x) return string.format("%.1f", x) end

-- The measurement -------------------------------------------------------------

rules.silent = {
  desc = "The measured stretch makes no sound",
  check = function(ctx, add)
    if ctx.result.sound_start then return end
    add({
      severity = "error",
      message = "the " .. ctx.range.label .. " is silent (nothing above -60 dBFS)",
      fix = "check the master and part mutes, solos and instruments",
      beat = ctx.range.start,
    })
  end,
}

rules.clip = {
  desc = "The master goes over full scale",
  -- Runs closer than this many beats are one finding.
  merge = 4,
  -- At most this many findings; the rest are counted in the last.
  max = 20,
  check = function(ctx, add, rule)
    local r = ctx.result
    if r.clip_runs == 0 then return end
    local groups = {}
    for _, run in ipairs(r.runs) do
      local beat = ctx.beat(run.at)
      local last = groups[#groups]
      if last and beat and last.beat and beat - last.last <= rule.merge then
        last.count, last.last, last.peak = last.count + 1, beat, math.max(last.peak, run.peak)
        last.frames = last.frames + run.frames
      else
        groups[#groups + 1] =
          { beat = beat, last = beat, seconds = run.at, count = 1, peak = run.peak, frames = run.frames }
      end
    end
    local need = math.max(0, r.true_peak)
    local who = ctx.kind == "part" and (ctx.part_name(ctx.range.part) .. " alone drives the master")
      or ctx.kind == "file" and "the file"
      or "the master"
    for i, g in ipairs(groups) do
      if i > rule.max then
        add({
          severity = "error",
          message = string.format("%d more clipped passages after these", #groups - rule.max + (r.clip_runs - #r.runs)),
          beat = g.beat,
          seconds = g.seconds,
          part = ctx.range.part or 0,
        })
        break
      end
      add({
        severity = "error",
        message = string.format(
          "%s clips at %s: %d run%s, %d samples, up to %s dBFS",
          who,
          ctx.where(g.beat, g.seconds),
          g.count,
          g.count == 1 and "" or "s",
          g.frames,
          db(g.peak)
        ),
        fix = ctx.kind == "file" and "use an unclipped source or re-render it lower"
          or string.format(
            "lower the master or what feeds it by at least %.1f dB, or end the master chain with a limiter",
            need + 0.1
          ),
        beat = g.beat,
        seconds = g.seconds,
        part = ctx.range.part or 0,
      })
    end
  end,
}

rules.true_peak = {
  desc = "True peak above the target's ceiling, or over 0 dBTP",
  check = function(ctx, add)
    local r, t = ctx.result, ctx.target
    local ceiling, why = t.true_peak, t.name
    if ceiling and t.true_peak_loud and r.integrated and r.integrated > (t.integrated or 0) then
      ceiling, why = t.true_peak_loud, t.name .. ", louder than " .. t.integrated .. " LUFS"
    end
    if ctx.kind == "part" then ceiling = nil end
    local beat = ctx.beat(r.true_peak_at)
    if ceiling and r.true_peak > ceiling then
      add({
        severity = t.kind == "deliver" and "error" or "warn",
        message = string.format(
          "true peak %s dBTP at %s, over the %s dBTP ceiling for %s",
          db(r.true_peak),
          ctx.where(beat, r.true_peak_at),
          db(ceiling),
          why
        ),
        fix = string.format(
          "lower the limiter's ceiling (or the master) by at least %.1f dB; check a true-peak meter on the render",
          r.true_peak - ceiling
        ),
        beat = beat,
        seconds = r.true_peak_at,
        part = 0,
        -- How far a fader should come down to fix it (the diagnostic's fix).
        lower = math.ceil((r.true_peak - ceiling) * 10) / 10,
      })
    elseif not ceiling and r.true_peak > 0 and r.clip_runs == 0 then
      add({
        severity = "warn",
        message = string.format(
          "inter-sample peak %s dBTP at %s although no sample is over full scale",
          db(r.true_peak),
          ctx.where(beat, r.true_peak_at)
        ),
        fix = "a converter or lossy encoder will clip it; leave about 1 dB of headroom (a true-peak limiter, or the master down)",
        beat = beat,
        seconds = r.true_peak_at,
        part = 0,
      })
    end
  end,
}

rules.loudness = {
  desc = "Integrated loudness against the target",
  -- Within this many LU of a normalising service's level nothing is said.
  slack = 0.5,
  check = function(ctx, add, rule)
    local r, t = ctx.result, ctx.target
    if not t.integrated or ctx.kind == "part" or not r.integrated then return end
    local diff = r.integrated - t.integrated
    local what = ctx.whole and "the song" or ("this " .. ctx.range.label)
    local beat = ctx.range.start
    if t.kind == "deliver" then
      if math.abs(diff) <= (t.tolerance or 0) then return end
      add({
        severity = ctx.whole and "error" or "info",
        message = string.format(
          "integrated loudness %s LUFS is %s LU %s the %s LUFS of %s",
          lu(r.integrated),
          lu(math.abs(diff)),
          diff > 0 and "over" or "under",
          lu(t.integrated),
          t.name
        ),
        fix = string.format(
          "%s the master by %.1f dB%s",
          diff > 0 and "lower" or "raise",
          math.abs(diff),
          diff < 0 and string.format(" (true peak would then be %s dBTP)", db(r.true_peak - diff)) or ""
        ),
        beat = beat,
        part = 0,
        lower = diff > 0 and math.floor(diff * 10 + 0.5) / 10 or nil,
      })
    elseif t.kind == "normalize" then
      if diff > rule.slack then
        add({
          severity = "info",
          message = string.format(
            "integrated loudness %s LUFS: %s turns %s down %.1f dB to %s LUFS",
            lu(r.integrated),
            t.name,
            what,
            diff,
            lu(t.integrated)
          ),
          fix = "the extra loudness is not heard there; if it came from limiting, less of it keeps more dynamics at the same playback level",
          beat = beat,
          part = 0,
        })
      elseif diff < -rule.slack then
        -- Quiet parts are raised only as far as the true-peak ceiling allows.
        local room = (t.true_peak or 0) - r.true_peak
        local short = -diff - math.max(0, room)
        if short > rule.slack then
          add({
            severity = "info",
            message = string.format(
              "integrated loudness %s LUFS with true peak %s dBTP: %s can raise it only %.1f dB, so it plays %.1f dB quieter than other parts",
              lu(r.integrated),
              db(r.true_peak),
              t.name,
              math.max(0, room),
              short
            ),
            fix = string.format(
              "if it should match, raise the level by about %.1f dB into a limiter with a %s dBTP ceiling",
              short,
              db(t.true_peak or -1)
            ),
            beat = beat,
            part = 0,
          })
        end
      end
    end
  end,
}

rules.part_over = {
  desc = "A part peaks over full scale before the master",
  check = function(ctx, add)
    local master_clips = ctx.result.clip_runs > 0
    for _, t in ipairs(ctx.result.parts or {}) do
      if t.id ~= 0 and t.over_at then
        local beat = ctx.beat(t.over_at)
        add({
          severity = master_clips and "warn" or "info",
          message = string.format(
            "%s peaks at %s dBFS after its fader, first over full scale at %s",
            ctx.part_name(t.id),
            db(t.peak),
            ctx.where(beat, t.over_at)
          ),
          fix = string.format(
            "lower its fader or clip gain by %.1f dB%s",
            t.peak + 0.1,
            master_clips and " (the master clips too)"
              or "; the mix is floating point, so this only clips in a device that clips, or when it reaches the master"
          ),
          beat = beat,
          seconds = t.over_at,
          part = t.id,
          lower = math.ceil((t.peak + 0.1) * 10) / 10,
        })
      end
    end
  end,
}

rules.phase = {
  desc = "A passage with strongly negative stereo correlation",
  -- Correlation under `floor` for at least `seconds`, while louder than `audible` LUFS.
  floor = -0.2,
  seconds = 2,
  audible = -50,
  check = function(ctx, add, rule)
    local s = ctx.result.series
    local need = math.floor(rule.seconds / s.hop + 0.5)
    local first, low = nil, 1
    local function close(last)
      if first and last - first + 1 >= need then
        -- Window i (from 0) ends at (i + 1) * hop. The passage starts at the
        -- first 100 ms of the first window that is out of phase on its own.
        local start_hop = first
        for h = math.max(0, first - 3), first do
          if (s.correlation_hop[h + 1] or 1) < rule.floor then
            start_hop = h
            break
          end
        end
        local from = start_hop * s.hop
        local to = (last + 1) * s.hop
        local beat = ctx.beat(from)
        add({
          severity = "warn",
          message = string.format(
            "stereo correlation down to %.2f from %s to %s (%.1f s): this passage partly cancels in mono",
            low,
            ctx.where(beat, from),
            ctx.where(ctx.beat(to), to),
            to - from
          ),
          fix = "look for a part with one side's polarity flipped, a widener, or a doubled sound a few ms apart",
          beat = beat,
          seconds = from,
          part = ctx.range.part or 0,
        })
      end
      first, low = nil, 1
    end
    for i = 1, #s.correlation do
      local c = s.correlation[i]
      if c < rule.floor and s.momentary[i] > rule.audible then
        first = first or i - 1
        low = math.min(low, c)
      else
        close(i - 2)
      end
    end
    close(#s.correlation - 1)
  end,
}

rules.mono = {
  desc = "The mix loses much level when summed to mono",
  -- dB. Unrelated sides lose 3.0 dB, so less than about 4 is ordinary width.
  limit = 4,
  check = function(ctx, add, rule)
    local r = ctx.result
    if not r.integrated then return end
    if not r.mono_integrated or r.mono_loss >= 60 then
      add({
        severity = "error",
        message = string.format("the %s cancels completely in mono (correlation %.2f)", ctx.range.label, r.correlation),
        fix = "one side is the other with its polarity flipped: find the part and undo the flip",
        beat = ctx.range.start,
        part = ctx.range.part or 0,
      })
    elseif r.mono_loss > rule.limit then
      add({
        severity = "warn",
        message = string.format(
          "the %s is %.1f dB quieter summed to mono (correlation %.2f, width %.2f)",
          ctx.range.label,
          r.mono_loss,
          r.correlation,
          r.width
        ),
        fix = "check wideners and polarity, and keep the low end centred",
        beat = ctx.range.start,
        part = ctx.range.part or 0,
      })
    end
  end,
}

rules.dc = {
  desc = "DC offset, over the whole render or in a passage",
  -- Linear; 0.01 is 1 % of full scale, -40 dBFS.
  limit = 0.01,
  -- A passage is this many whole seconds whose means are all over the limit
  -- on the same side of zero. Medians and whole seconds keep low notes and
  -- single drum hits from reading as DC.
  seconds = 2,
  check = function(ctx, add, rule)
    local r = ctx.result
    local function report(v, side, from, to)
      local beat = ctx.beat(from)
      local span = to and string.format(" from %s for %d s", ctx.where(beat, from), to - from) or ""
      add({
        severity = "warn",
        message = string.format(
          "DC offset of %.2f %% (%.0f dBFS) on the %s side%s",
          v * 100,
          20 * math.log10(math.abs(v)),
          side,
          span
        ),
        fix = "it wastes headroom and clicks at edits; high-pass the offending source (a DC filter, or EQ at 20 Hz)",
        beat = beat or (ctx.kind ~= "file" and ctx.range.start or nil),
        seconds = from,
        part = ctx.range.part or 0,
      })
    end
    for ch, side in ipairs({ "left", "right" }) do
      if math.abs(r.dc[ch]) >= rule.limit then
        report(r.dc[ch], side, 0)
      else
        local means = ch == 1 and r.series.dc_left or r.series.dc_right
        local first, sum
        local function close(stop)
          if first and stop - first >= rule.seconds then report(sum / (stop - first), side, first, stop) end
          first, sum = nil, nil
        end
        for i, m in ipairs(means) do
          local sec = i - 1
          local over = math.abs(m) >= rule.limit
          if first and (not over or (m > 0) ~= (sum > 0)) then close(sec) end
          if over then
            if first then
              sum = sum + m
            else
              first, sum = sec, m
            end
          end
        end
        close(#means)
      end
    end
  end,
}

rules.silence = {
  desc = "Long silence at the start or end of the render",
  start = 1, -- seconds
  ending = 2, -- seconds, not counting the tail added for releases
  check = function(ctx, add, rule)
    local r = ctx.result
    if not r.sound_start or not ctx.whole then return end
    if r.sound_start > rule.start then
      local beat = ctx.beat(r.sound_start)
      add({
        severity = "info",
        message = string.format(
          "the render starts with %.1f s of silence; sound begins at %s",
          r.sound_start,
          ctx.where(beat, r.sound_start)
        ),
        fix = ctx.kind == "file" and "trim the start"
          or "start the export where the sound starts, or move the material earlier",
        beat = ctx.beat(0),
        seconds = 0,
        part = 0,
      })
    end
    local content = r.seconds - (r.tail or 0)
    if content - r.sound_end > rule.ending then
      local beat = ctx.beat(r.sound_end)
      add({
        severity = "info",
        message = string.format(
          "%.1f s of silence before the end, from %s",
          content - r.sound_end,
          ctx.where(beat, r.sound_end)
        ),
        fix = ctx.kind == "file" and "trim the end" or "shorten the last clip, or end the export earlier",
        beat = beat,
        seconds = r.sound_end,
        part = 0,
      })
    end
  end,
}

rules.infrasonic = {
  desc = "Much energy below 22 Hz",
  -- dB share of the energy; -20 is 1 %.
  limit = -20,
  check = function(ctx, add, rule)
    for _, band in ipairs(ctx.result.bands or {}) do
      if band.name == "sub" and band.share > rule.limit then
        add({
          severity = "info",
          message = string.format(
            "%.1f %% of the energy is below %.0f Hz, under what speakers play",
            10 ^ (band.share / 10) * 100,
            band.high
          ),
          fix = "it costs headroom and moves woofers; high-pass the bass, kick and pads around 25-30 Hz",
          beat = ctx.range.start,
          part = ctx.range.part or 0,
        })
      end
    end
  end,
}

-- The project: things left in a state that looks forgotten --------------------

local function overlaps(clip, range)
  if not range.start then return true end
  return clip.start < range["end"] and clip.start + clip.length > range.start
end

rules.forgotten = {
  desc = "Muted parts and clips, bypassed devices, solos and switched-off automation",
  check = function(ctx, add)
    if ctx.kind == "file" then return end
    local range = ctx.range
    for _, id in ipairs(api.part_list()) do
      local t = api.part_get(id)
      local clips, muted = 0, {}
      for _, c in ipairs(api.clip_list(id)) do
        if overlaps(c, range) then
          clips = clips + 1
          if c.muted then muted[#muted + 1] = c end
        end
      end
      if t.solo and ctx.kind == "mix" then
        add({
          severity = "warn",
          message = t.name .. " is soloed, so the measurement heard only soloed parts",
          fix = "unsolo it to measure the whole mix",
          beat = range.start,
          part = id,
        })
      end
      if t.mute and clips > 0 then
        add({
          severity = "hint",
          message = string.format("%s is muted and has %d clip%s here", t.name, clips, clips == 1 and "" or "s"),
          fix = "unmute it, or remove it if it is not wanted",
          beat = range.start,
          part = id,
        })
      elseif #muted > 0 then
        add({
          severity = "hint",
          message = string.format(
            "%s has %d muted clip%s, the first at %s",
            t.name,
            #muted,
            #muted == 1 and "" or "s",
            ctx.where(muted[1].start)
          ),
          fix = "unmute them (`gc`), or delete them",
          beat = muted[1].start,
          part = id,
        })
      end
      for _, dev_id in ipairs(t.devices or {}) do
        local ok, dev = pcall(api.device_get, dev_id)
        if ok and dev.bypass then
          add({
            severity = "hint",
            message = string.format("the %s on %s is bypassed", dev.name or dev.kind, t.name),
            fix = "switch it back on, or remove it",
            beat = range.start,
            part = id,
          })
        end
      end
      for _, lane in ipairs(api.lane_list(id)) do
        if not lane.enabled and (lane.point_count or 0) > 0 then
          add({
            severity = "hint",
            message = string.format(
              "%s automation on %s is switched off (%d points)",
              lane.target == "param" and (lane.param or "parameter") or lane.target,
              t.name,
              lane.point_count
            ),
            fix = "turn it back on (`<leader>at`) or clear it",
            beat = range.start,
            part = id,
          })
        end
      end
    end
  end,
}

rules.no_sound = {
  desc = "A part with clips that made no sound",
  -- dBFS; quieter than this counts as no sound.
  floor = -100,
  check = function(ctx, add, rule)
    if ctx.kind ~= "mix" then return end
    local any_solo = false
    for _, id in ipairs(api.part_list()) do
      any_solo = any_solo or api.part_get(id, "solo")
    end
    if any_solo then return end
    for _, peak in ipairs(ctx.result.parts or {}) do
      if peak.id ~= 0 and peak.peak <= rule.floor then
        local ok, t = pcall(api.part_get, peak.id)
        local playing = 0
        for _, c in ipairs(ok and api.clip_list(peak.id) or {}) do
          if not c.muted and overlaps(c, ctx.range) then playing = playing + 1 end
        end
        if ok and not t.mute and playing > 0 then
          add({
            severity = "hint",
            message = string.format(
              "%s has %d clip%s here but made no sound",
              t.name,
              playing,
              playing == 1 and "" or "s"
            ),
            fix = "it may have no instrument, a bypassed one, or its fader all the way down",
            beat = ctx.range.start,
            part = peak.id,
          })
        end
      end
    end
  end,
}

return rules
