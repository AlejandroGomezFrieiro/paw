# ara

ARA plugins on audio tracks. An ARA plugin reads a full audio clip, not
only the block that plays now. Melodyne edits the notes of a vocal in this
way, and an audio-to-MIDI plugin hears all of a take before it writes the
notes. ARA is Celemony's Audio Random Access (ARA 2).

With this extension, an ARA plugin first on a track gets the audio clips
of the track and the tempo of the song. The plugin plays the clips, and
the edits that you make in the plugin stay in the project.

```lua
paw.ext.load("extensions/ara")   -- or `paw.withExtensions (exts: [ exts.ara ])`
```

## Try it

1. Load the extension, and open a song with an audio clip on a track.
2. Put the cursor on that track and press `\aa`. Choose the ARA plugin.
   The message tells the plugin and the number of clips that it has.
3. Play the song. The plugin plays the clips of the track.
4. Press `\an`. When the plugin finished its analysis, a new track
   `<track> notes` holds a MIDI clip of the notes that the plugin heard.
   Press `u` to remove it.
5. Save the project with `:w`. The plugin's edits are in a file beside
   the state of the device.

## How to

### How to edit the clips in the plugin

Press `\ae`, or `:ara.edit`, to open the window of the plugin. Edits in
the plugin change the sound of the clips. paw keeps them when it saves
the project.

### How to change the clips

Move, trim or delete the clips as usual. The plugin gets the clips again
after each edit, and `u` gives it the clips as they were. A muted clip
does not play.

## Reference

### Keys

In the arrange view.

| Keys | Effect |
| --- | --- |
| `\aa` | `:ara.add`: put an ARA plugin first on the track of the cursor. A list of the ARA plugins opens. |
| `\an` | `:ara.notes`: a MIDI clip of the notes that the plugin heard, on a new track under this track. One undo step. |
| `\ae` | `:ara.edit`: open the window of the ARA plugin of the track. |
| `\as` | `:ara.status`: say the plugin, the number of its clips, and if it took its edits back from the project. |

`\` is the local leader (`paw.opt.localleader`).

### Commands

| Command | Effect |
| --- | --- |
| `:ara.add [plugin]` | Put an ARA plugin first on the track of the cursor. Without a name, choose from the ARA plugins that paw knows. A plugin that is not an ARA plugin is refused, and leaves no undo step. |
| `:ara.notes` | Make a MIDI clip of the notes that the ARA plugin heard in the clips. paw waits for the analysis of the plugin. |
| `:ara.edit` | Open the window of the ARA plugin. |
| `:ara.status` | Say what the ARA plugin of the track has. |

### Options

| Option | Default | Effect |
| --- | --- | --- |
| `ara_bridge` | `""` | Where `paw-ara.so` is. Empty: `lib/` in the extension, then `$PAW_ARA_BRIDGE`. |
| `ara_unpitched_key` | `60` | The key of a note that the plugin heard without a pitch (a drum hit). |

### What the plugin gets

- One ARA document for each plugin on a track.
- An audio source for each sound file of the track's audio clips, and an
  audio modification and a playback region for each clip that is not
  muted. A region starts where the clip starts, in seconds.
- The tempo and the time signatures of the song, as a musical context.
- The plugin has all three roles: it plays the clips, it renders for its
  editor, and its window shows the clips.
- The sound of the clips comes from their files. The gain, the fades and
  the edit list of a clip are not in what the plugin plays.

### What paw keeps

- The plugin's ARA archive is the file `<n>-<kind>.ara` beside the
  `.state` of the device in the track folder. paw writes it when it saves
  the project, and gives it to the plugin when it makes the plugin again.
- An archive that the plugin cannot read (from a different plugin)
  gives a message, and paw does not give it to the plugin.

### What is not done

- ARA plugins as VST3, and ARA 1. Only CLAP plugins with the ARA
  extension work.
- Windows plugins through yabridge: yabridge does not bridge ARA.
- Content that the plugin gives other than notes (tempo, chords, key) is
  not read.
- An edit in the plugin's window is not an undo step of paw.

### Health

`:checkhealth ara` tells if paw found and loaded `paw-ara.so`, and
the ARA plugins that paw knows. paw knows a plugin as an ARA plugin from
the features of its plugin file. After an update of paw, `:plugins.rescan`
reads the files again.
