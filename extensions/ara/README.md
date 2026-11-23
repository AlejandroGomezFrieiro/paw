# ara

ARA plugins on audio parts. An ARA plugin reads a whole audio clip, and not
only the block that plays now. For example, Melodyne edits the notes of a
vocal this way, and an audio-to-MIDI plugin hears all of a take before it
writes the notes. ARA stands for Audio Random Access (ARA 2), and Celemony
made it.

With this extension, an ARA plugin that is first on a part gets the audio
clips of the part and the tempo of the song. The plugin plays the clips, and
the edits that you make in the plugin stay in the project.

```lua
paw.ext.load("extensions/ara")   -- or `paw.withExtensions (exts: [ exts.ara ])`
```

## Try it

1. Load the extension, and open a song with an audio clip on a part.
2. Put the cursor on that part and press `\aa`. Choose the ARA plugin.
   The message names the plugin and the number of clips that it has.
3. Play the song. The plugin plays the clips of the part.
4. Press `\an`. When the plugin finishes its analysis, a new part
   `<part> notes` holds a MIDI clip of the notes that the plugin heard.
   Press `u` to remove it.
5. Save the project with `:w`. The plugin's edits go into a file beside
   the state of the device.

## How to

### How to edit the clips in the plugin

Press `\ae`, or type `:ara.edit`, to open the window of the plugin. Edits in
the plugin change the sound of the clips, and paw keeps them when it saves
the project.

### How to change the clips

Move, trim or delete the clips as usual. The plugin gets the clips again
after each edit, and `u` gives it the clips as they were before. A muted clip
does not play.

## Reference

### Keys

The keys work in the arrange view.

| Keys | Effect |
| --- | --- |
| `\aa` | `:ara.add`: put an ARA plugin first on the part of the cursor. A list of the ARA plugins opens. |
| `\an` | `:ara.notes`: a MIDI clip of the notes that the plugin heard, on a new part under this part. One undo step. |
| `\ae` | `:ara.edit`: open the window of the ARA plugin of the part. |
| `\as` | `:ara.status`: say which plugin the part has, how many clips it has, and if it took its edits back from the project. |

`\` is the local leader (`paw.opt.localleader`).

### Commands

| Command | Effect |
| --- | --- |
| `:ara.add [plugin]` | Put an ARA plugin first on the part of the cursor. Without a name, you choose from the ARA plugins that paw knows. paw refuses a plugin that is not an ARA plugin, and leaves no undo step. |
| `:ara.notes` | Make a MIDI clip of the notes that the ARA plugin heard in the clips. paw waits for the plugin to finish its analysis. |
| `:ara.edit` | Open the window of the ARA plugin. |
| `:ara.status` | Say what the ARA plugin of the part has. |

### Options

| Option | Default | Effect |
| --- | --- | --- |
| `ara_bridge` | `""` | Where `paw-ara.so` is. When empty, paw looks in `lib/` in the extension, and then in `$PAW_ARA_BRIDGE`. |
| `ara_unpitched_key` | `60` | The key of a note that the plugin heard without a pitch (a drum hit). |

### What the plugin gets

- One ARA document for each plugin on a part.
- An audio source for each sound file of the part's audio clips, and an
  audio modification and a playback region for each clip that is not
  muted. A region starts where the clip starts, in seconds.
- The tempo and the time signatures of the song, as a musical context.
- The plugin has all three roles. It plays the clips, it renders for its
  editor, and its window shows the clips.
- The sound of the clips comes from their files. The plugin does not play
  the gain, the fades or the edit list of a clip.

### What paw keeps

- The plugin's ARA archive is the file `<n>-<kind>.ara` beside the
  `.state` of the device in the part folder. paw writes it when it saves
  the project, and gives it to the plugin when it makes the plugin again.
- If the plugin cannot read an archive (for example, one from a different
  plugin), paw shows a message and does not give the archive to the plugin.

### What paw does not do

- ARA plugins as VST3, and ARA 1. Only CLAP plugins with the ARA
  extension work.
- Windows plugins through yabridge, because yabridge does not bridge ARA.
- Content that the plugin gives other than notes (tempo, chords, key). paw
  does not read it.
- An edit in the plugin's window is not an undo step of paw.

### Health

`:checkhealth ara` tells you if paw found and loaded `paw-ara.so`, and it
lists the ARA plugins that paw knows. paw knows a plugin as an ARA plugin from
the features of its plugin file, and after an update of paw, `:plugins.rescan`
reads the files again.
