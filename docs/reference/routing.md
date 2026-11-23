# Routing: groups, VCAs, sends and side-chains

<!-- tags: mixing routing groups vca sends side-chain outputs -->

A track plays into the master or into a different track, it can send
its sound to other tracks, and it can key a device on a different track. An
instrument with several outputs can have a track for each output. For why groups
and VCAs are ordinary tracks, see
[About groups and VCAs](../explanation/about-groups-and-vcas.md).

## Groups

A group is a track that other tracks belong to. The members play into the
group, so its fader, mute and devices act on all of them, and the members show
below the group, indented one step, in its color.

| Keys, command | Effect |
| --- | --- |
| `:track.group Strings`, `<Space>tg` | Make a group of the selected tracks. |
| `:track.into Strings` | Put a track into a group. |
| `:track.ungroup`, `<Space>tG` | Take a track out of its group, or remove a group. |
| `za` | Fold the members of a group into it, or open them, in this window ([Folds](narrowing.md#folds)). On the return row of a subproject, show its tracks under the row, or hide them (see [Subprojects](subprojects.md)). |
| `zM`, `zR` | Fold each group and fold of the window, open them all. |
| `:group.link`, `<Space>tl` | Link the faders of the members of a group. |

- A group can hold groups.
- A group is an ordinary track with a mark in its `meta`, and paw saves, copies and
  undoes it as any other track.
- `paw.groups.make({ violins, violas, cellos }, "Strings")` makes a group.
- `paw.groups.rows()` is the list of the tracks that show, which is all the tracks
  except the folded tracks.
- A fold is part of the window, not of the project. Each window keeps its own
  folds, and a fold is not an undo step.
- For work on one group alone, see [Scopes](narrowing.md).

### Linked faders

`:group.link` on a group, routed or not, links the faders of its members.
When one fader moves, the others move by the same number of dB, so their
balance stays. When a fader reaches its end it stops, and the others continue.

- The fader of the group itself does not move.
- The arrange view shows `≡` after the name of a group with linked faders,
  as in `Drums ≡`.
- The link is an option of the group, kept in its `meta`
  (`paw.groups.link(group, true)`).
- One undo step undoes the full move.

## VCAs

A VCA is a fader, a mute and a solo that control other tracks without
carrying their sound. Nothing is routed, so the tracks play where
they played.

| Keys, command | Effect |
| --- | --- |
| `:vca.make Drums`, `<Space>tv` | Make a VCA over the selected tracks (or the track at the cursor). |
| `:vca.assign Drums`, `<Space>ta` | Put the selected tracks under a VCA. With no name: a list. |
| `:vca.release`, `<Space>tr` | Take the selected tracks out of a VCA, or out of all VCAs. |
| `:vca.dissolve`, `<Space>tx` | Remove a VCA. |

- A move of the VCA fader moves each member by that number of dB. The own
  fader of the member does not change.
- The mute of the VCA mutes the members, and its solo solos them, while the own mute
  and solo of the members do not change.
- A track can be under several VCAs. Their gains add in dB.
- The VCA fader has automation, as the fader of a track has (`<Space>al` shows
  a lane, see [Automation](automation.md)). Its lanes add to the lanes of each member, in dB, so the level of
  a member is its fader, plus its lane, plus the fader or lane of each VCA.
- A VCA is an ordinary track with a mark in its `meta`, and each member names
  its VCAs in its own `meta`. paw saves, copies and undoes it as any other
  track, and it has no devices and plays nothing.
- `paw.groups.rows()`, the arrange view and the graphical window put the
  VCAs after the other tracks.
- In the terminal mixer, VCAs have strips after the tracks, with the names
  of their tracks, and the strip of a track names its VCAs. The graphical
  window does the same, and the menus of a track header and of a mixer
  strip make, assign and release VCAs.

```lua
local drums = paw.vca.make({ kick, snare, hats }, "Drums")
drums.volume = -3                 -- every member 3 dB quieter
drums:automate("volume"):set_points({ { 0, 0 }, { 16, -12 } })
paw.vca.assign(room, drums)       -- also `unassign`, `members`, `of`, `dissolve`
```

| Function | Effect |
| --- | --- |
| `paw.vca.make(tracks, name)` | Make a VCA over the tracks. Returns the VCA. |
| `paw.vca.assign(track, vca)`, `paw.vca.unassign(track, vca)` | Put a track under a VCA, or take it out. |
| `paw.vca.members(vca)` | The members of a VCA. |
| `paw.vca.of(track)` | The VCAs of a track. |
| `paw.vca.dissolve(vca)` | Remove a VCA. |

The sync adds the VCAs into each member. A fixed fader goes into the gain
of the member. Lanes go into one lane for the member, which is the sum of the
lines in dB, with a point where any of them has a point. The audio
thread plays that lane sample by sample, so a render sounds the same as
playback on any number of threads.

## Outputs and sends

| Keys, command | Effect |
| --- | --- |
| `:track.output Drum bus`, `<Space>to` | Play the track into a different track. `<Space>to`: a list. |
| `:send Reverb -9`, `<Space>ts` | Send the sound of the track to a different track, at -9 dB. `<Space>ts`: a list. |
| `:send Reverb pre=1` | A send before the fader. |
| `:send.remove Reverb` | Remove the send. |

- A send with no level is at `paw.opt.send_level` (-12 dB).
- `:send Reverb -6` on a track that already sends to Reverb sets the level
  of that send, and without a level the send does not change and paw says so.
- With a selection of tracks (`V` in the arrange view or in the mixer),
  `:send` acts on each track of the selection.
- The list of `<Space>ts` shows first the tracks with no instrument (the
  returns).
- In Lua: `track:send(reverb, -6, { pre = true })`.
- A send before the fader takes the sound after the devices of the track,
  and before its fader and pan, so the send keeps its level when the fader
  moves. A mute of the track also silences the send.

## Side-chains

A device can listen to a different track, for example a compressor on
the bass that ducks under the kick, or a gate on a pad that opens on the
hi-hat.

| Way | Effect |
| --- | --- |
| `comp:set_sidechain(kick)`, `comp.sidechain = kick.id` | Key the device with the kick, after its fader, as a send. |
| `{ pre = true }`, `comp.sidechain_pre` | Take the key after the devices of the kick, before its fader, pan and mute. So a muted "ghost" kick still keys. |
| `comp:set_sidechain(nil)` | Remove the side-chain. |
| `:device.sidechain Kick` | Key the device of the device panel with Kick. `pre=1`: before the fader. `none`: remove. With no name: a list. |
| `gS` in the device panel | Select the key from a list. |

- A track that a solo silences still keys, after its fader, as if it were
  heard, but a mute of the track removes a key taken after the fader.
- The built-in `compressor` and `gate` key their detector from it
  (`listen` plays it).
- CLAP, VST3 and LV2 plugins get it on their first side-chain input:
  - a CLAP audio port that is not the main port
  - a VST3 auxiliary bus
  - an LV2 port marked `isSideChain`, or in a group that is the side-chain
    of a different group. `device.ports.sidechain` tells if a device has one.
  Other devices ignore it.
- Lua devices with `sidechain = true` get it in `b.key_left` and
  `b.key_right` (see [Lua devices](lua-devices.md)).
- paw processes the key track first, as a track that sends.
- paw aligns the key with the input of the device, either by delaying the key by
  the latency of the devices before it or by delaying the track of the device
  when the key is later.
- The device panel shows `key Kick` on the line of the device. In the
  graphical window, a device that can listen has a Key row on its card,
  and the row has a menu of the tracks that the device can hear.

### Loops and lifetime

- paw refuses a side-chain that makes a loop, and the message gives the
  reason. A loop happens when the key is the track of the device, the master,
  or a track that the track of the device plays into, sends to or keys,
  directly or through other tracks. paw also refuses outputs and sends that
  make a loop.
- When you remove the key track, the side-chain goes (undo brings it
  back). A copy of a track keeps it. A track restored after its key is gone
  (or where it makes a loop) loses it, with a message. Templates do not
  keep it.

## Instruments with several outputs

A drum plugin can have a pair of outputs for each drum, and Surge XT has scene outputs. In both cases `device.ports.outputs` names the pairs.

- The pairs come from the plugin: CLAP audio ports, VST3 output buses (paw
  enables all of them), LV2 output ports two at a time. A port wider than
  two channels is also taken in pairs.
- The first pair plays on the track of the device.
- A further pair plays only where it is routed, and it is silent otherwise.

| Keys, command | Effect |
| --- | --- |
| `kit:set_output(2, kick)` | Play pair 2 into the track kick. `kit.outputs` is a table of pair number to track. |
| `:device.output 2 Kick`, `O` in the device panel | The same. `none`: remove. With no arguments: a list of pairs, then of tracks. |
| `:device.spread` | Make a track for each pair that plays nowhere, named after it. Put these tracks and the track of the device in a group (`<track> outputs`, or the group of the track). |

- `paw.routes.spread(kit)` is `:device.spread` in Lua. The track of the
  device cannot be the group itself, because its pairs feed the new tracks.
- A pair leaves the device before the rest of the chain, so the fader, pan
  and mute of the track of the device do not act on it, while those of the
  track that it plays into do.
- The pair goes into that track before its devices, so paw processes that
  track after the device and aligns it with the rest, as with any other
  connection.
- paw refuses loops as for side-chains, and pairs of a device on the
  master.
- When you remove the track that a pair plays into, the route goes, and a copy
  of the track plays its pairs nowhere. Templates do not keep the routes.
- The built-in `drums` has a pair for each family of drums (Kick, Snare,
  Hats, Toms, Cymbals, Percussion). A family whose pair is routed plays
  there, and not in the pair of the kit.
- The device panel shows `outs 2/6` (routed pairs of all pairs) on the line
  of the device. In the graphical window, the card has an Outs row whose
  menu routes each pair and spreads them.
- paw does not handle main pairs wider than stereo (surround). A mono
  plugin on a stereo track plays on both sides.

For delay compensation through routes, see
[The audio engine](engine.md#delay-compensation).
