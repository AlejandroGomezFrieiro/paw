# plugstate

Many plugins keep a part of their sound outside their parameters, for example the model of an amp simulator, the impulse response of a cabinet or a
room, and the instrument file of a sampler. The extension gives you access to that
part without the window of the plugin.

You choose a model or a file with
keys or commands, and you can step through a folder of them or find them by
words. You can also keep named snapshots of the whole state of a device and switch
between them. Each change is one undo step, and the project keeps all of
the changes.

```
extensions/plugstate/
  init.lua, lua/plugstate/   the adapters, the library, snapshots, commands, the
                             readers of the state of each framework
  tests.lua                  tests with real plugins (Neural Amp Modeler, LSP, sfizz,
                             TONE3000, Soundshed Guitar, Surge XT, Musio)
  tests_frameworks.lua       tests of the readers, with states in tests_states/
```

## Try it

1. Add Neural Amp Modeler to a guitar track: `:device.add neural amp`.
2. Put some `.nam` models in `~/.local/share/paw/models`.
3. Open the device panel and put its row on the amp. Press `]m`, and paw loads
   the first model of the folder and says its name and what the model
   file says about itself.
4. Press `]m` again, and the next model plays. Press `u`, and paw loads the
   model before again.
5. Press `\s`, and paw keeps the state as snapshot A. Load another model and
   press `\s` again for snapshot B. Now `[v` and `]v` switch between A and B.

## How to

### How to load a model or a file by name

Type `:plugstate.load` with a file, or with words that find it, as in
`:plugstate.load ~/nam/deluxe.nam` or `:plugstate.load deluxe clean`. When
the words find more than one file, a picker opens with them. When the
selection stays on a file, paw loads it for a trial, and you hear it with
what the track plays. Enter keeps the file, and Escape puts back what was there.

### How to add a folder of models or impulse responses

Add the folder to `paw.opt.plugstate_folders`, and separate folders with `:`.
paw also looks in `~/.local/share/paw/models` and in the folder of the
file that the plugin holds now.

### How to change the preset of an amp plugin

For TONE3000 and Soundshed Guitar, the first slot is the preset. `]m`
and `[m` step through the presets, and `:plugstate.load bogner` finds one
by its name. paw finds the factory presets that come with the plugin, and you can put
your own presets (`.t3kpreset`, `.soundshed.presets` packs and `.json`
presets) in a folder of `paw.opt.plugstate_folders`. For a guide, see
[How to switch amp models and presets from paw](../../docs/how-to/switch-amp-models-and-presets.md).

### How to find a model in TONE3000's library

TONE3000 (www.tone3000.com) is a library of amp models and impulse
responses that its users share, and plugstate finds them and loads them into
TONE3000, Neural Amp Modeler and the impulse response plugins of LSP.

1. Sign in to your TONE3000 account with `:plugstate.tone3000_login`. See
   [How to sign in to TONE3000 from paw](../../docs/how-to/sign-in-to-tone3000.md).
2. In the device panel, put the row on the plugin and press `\t`. Type
   words, for example `plexi crunch`, and press Enter, or type
   `:plugstate.search plexi crunch`.
3. A list of tones opens, 25 at a time, and the pane at the side shows the
   author, the license and the description. `Alt-n` and `Alt-p` show the
   next page and the page before.
4. Press Enter on a tone. If the tone has more than one model, a second
   list opens, and you press Enter on a model.

paw downloads the model once and loads it as one undo step. To find
only one kind of tone, add `gear=`, `type=` or `by=`, as in
`:plugstate.search gear=pedal by=someone fuzz`.

### How to set a plugin that holds more than one file

Give the file a name with `slot=`, as in `:plugstate.load slot=ifn1 hall.wav`.
`:plugstate.info` lists the names. A slot can also hold a value, for
example the scene of a Soundshed preset, as in `:plugstate.load slot=scene solo`.

### How to change the model or the preset at a point in the song

Put the cursor where the sound changes, and type `:plugstate.at` with a
file or words that find it, as in `:plugstate.at bogner` or `:plugstate.at
slot=block2 ~/nam/x.nam`. `:plugstate.at snapshot=B` sets a snapshot.
The state lane of the device (see
[Automation](../../docs/reference/automation.md#state-lanes)) applies the change
from the cursor on. A model of Neural Amp Modeler changes on the frame
of the point, and a preset of TONE3000 or Soundshed Guitar changes on the
frame in a rendered file.

### How to switch sounds while you play

Keep each sound as a snapshot (`:plugstate.snapshot crunch`), then use
`]v` and `[v` or `:plugstate.recall crunch`. A snapshot holds the whole
state of the plugin and its parameters, including the parts that no parameter
shows.

### How to teach plugstate another plugin

Add an adapter from your configuration or extension:

```lua
local plugstate = require("paw.plugstate")
plugstate.adapter({
  name = "my-amp",
  desc = "My Amp: its model",
  matches = function(d) return d.plugin and d.plugin.id == "com.example.amp" end,
  slots = function(id, d)
    return { { key = "model", label = "Model", what = "model", kind = "file", types = { "nam" }, value = nil } }
  end,
  -- What `paw.api.device_load` takes: a call to the plugin, or a new state.
  load = function(id, d, slot, path)
    return { call = { method = "preset.load", data = "file:" .. path } }
  end,
})
```

An LV2 plugin that lists its files as properties needs no adapter, because the
`lv2` adapter finds them. See [Adapters](#adapters).

### How to find where a plugin keeps a setting

paw reads the saved state of a plugin as a tree, and it knows the forms of
JUCE, DPF, iPlug2, LSP, Dplug, nih-plug and LV2. For another plugin, it
shows the bytes.

1. Put the row of the device panel on the plugin.
2. Type `:plugstate.mark`, and paw keeps the state of the plugin.
3. Change one setting in the window of the plugin.
4. Type `:plugstate.changes`, and paw lists the paths that changed, for
   example `set /patch/parameters/a_octave@value: "0" → "1"`.
5. To keep the change as a preset, type `:plugstate.preset_write ~/octave`.
   You can load the preset into each format of the plugin with `:plugstate.load`.

`:plugstate.tree` shows the whole tree, and `:plugstate.path <path> <value>`
sets one value. For a guide, see
[How to find and change a setting inside a plugin](../../docs/how-to/find-and-change-a-setting-inside-a-plugin.md).
For the forms of each framework, see
[The saved state of plugins](../../docs/reference/plugin-state.md). To give
names to the paths of a JUCE plugin, add a description, as
[The state of JUCE plugins](../../docs/reference/juce-plugin-state.md) explains.

## Reference

### Keys

The keys below work in the device panel, and they act on the device of the row.

| Key | Effect |
| --- | --- |
| `]m` `[m` | loads the next or the previous file of the folder (a count skips more) |
| `\m` | opens the picker of the files that the plugin takes |
| `\s` | keeps the state of the device as a snapshot (A, B, C and so on) |
| `\v` | opens the picker of the snapshots |
| `\t` | asks for words, and then searches TONE3000's library (`:plugstate.search_prompt`) |
| `]v` `[v` | brings back the next or the previous snapshot |

### Commands

| Command | Effect |
| --- | --- |
| `:plugstate.at [slot=<key>] <file or words>`, `:plugstate.at snapshot=<name>` | gives the file or the snapshot from the cursor on, on the device's state lane |
| `:plugstate.load [slot=<key>] [file or words]` | loads a file into the plugin. With words, it loads the one file that they find, and otherwise it opens the picker |
| `:plugstate.next`, `:plugstate.prev` | loads the next or the previous file of the folder |
| `:plugstate.files [words]` | lists the files that the plugin takes, in the library folders |
| `:plugstate.info` | tells which files the plugin holds, what the files say of themselves, the framework of its saved state, and the snapshots |
| `:plugstate.snapshot [name]` | keeps the whole state of the device and its parameters under a name |
| `:plugstate.recall [name]` | brings back a snapshot, and with no name it opens the picker |
| `:plugstate.recall_next`, `:plugstate.recall_prev` | brings back the next or the previous snapshot |
| `:plugstate.forget <name>` | removes a snapshot |
| `:plugstate.adapters` | lists the kinds of plugin that plugstate knows |
| `:plugstate.tree [path]` | shows the saved state of a plugin as a tree, or the part at the path, and the first line names the framework. A count sets the depth |
| `:plugstate.mark` | keeps the saved state of a plugin, for `:plugstate.changes` |
| `:plugstate.changes` | lists the paths of the state that changed after `:plugstate.mark` |
| `:plugstate.path <path> [value]` | shows a value of the saved state of a plugin, or sets it as one undo step. A number stays a number, except in a JUCE state |
| `:plugstate.preset_write <file>` | writes the changes after `:plugstate.mark` as a `.jucepreset` file, with the name of the framework |
| `:plugstate.search [gear=<gear>] [type=nam\|ir] [by=<user>] [sort=<order>] [arch=<n>] [slot=<key>] [words]` | searches TONE3000's library and opens a picker of the tones. Enter on a tone shows its models, and Enter on a model loads it |
| `:plugstate.search_more` | shows the next page of the last search (a count skips more) |
| `:plugstate.search_prompt` | asks for words, then does `:plugstate.search` |
| `:plugstate.tone3000_login` | signs in to TONE3000 by showing a code to enter at `https://www.tone3000.com/activate`, and then keeps the tokens |
| `:plugstate.tone3000_logout` | forgets the tokens of the sign-in, and stops a sign-in that waits for its code |
| `:plugstate.tone3000_status` | tells you if paw is signed in, where the token comes from and when it expires, and it does not use the network |

- The commands act on the device of the row of the device panel when
  plugstate knows it, and otherwise they act on the first device of the cursor
  track that plugstate knows.
- A load and a recall are each one undo step. The parameters of the device
  stay as they are on a load, but a recall sets the parameters of the snapshot.
- The project keeps the snapshots in `meta.plugstate` of the device, so a
  project with snapshots opens and plays without the extension.
- `:checkhealth plugstate` lists the adapters and the folders.

### Options

| Option | Default | Effect |
| --- | --- | --- |
| `plugstate_folders` | `""` | the folders of models and impulse responses, separated by `:` |
| `plugstate_tone3000_token_file` | `""` | a file that holds a TONE3000 access token on its first line, which paw uses only if its mode is 600 or 400 |
| `plugstate_tone3000_plugin_session` | `false` | when `true`, paw also uses the session of the TONE3000 plugin (see [TONE3000 tokens](#tone3000-tokens)) |
| `plugstate_tone3000_api` | `""` | another address of the API. When empty, paw uses `https://www.tone3000.com/api/v1` |
| `plugstate_tone3000_client_id` | `""` | the publishable key of your TONE3000 app, for `:plugstate.tone3000_login`. When empty, paw uses the environment variable `TONE3000_CLIENT_ID` |
| `plugstate_tone3000_store` | `"auto"` | where the sign-in keeps its tokens: `auto` (the keyring, else the file), `keyring` or `file` |
| `plugstate_tone3000_session_file` | `""` | the file of the sign-in. When empty, paw uses `$XDG_STATE_HOME/paw/tone3000-session.json` |

### The search of TONE3000

- `gear=` is `amp`, `amp-cab`, `pedal`, `outboard`, `cab`, `space` or
  `experimental`, `type=` is `nam` (models) or `ir` (impulse responses),
  `by=` is the user name of the author, and `sort=` is `best-match`,
  `newest`, `oldest`, `trending` or `downloads-all-time`. Without words,
  TONE3000 gives the tones that are popular now.
- paw asks only for the kinds of file that the device takes. For the
  TONE3000 plugin, paw asks for the models of the second architecture
  (A2), as the window of the plugin does. `arch=1` asks for the others.
- A model goes into the slot named by `slot=`. Without `slot=`, a `.nam` model goes
  into the first slot of a model, and a `.wav` impulse response goes into the
  first slot of an impulse response.
- paw keeps each file that it downloads in
  `$XDG_CACHE_HOME/paw/tone3000/<model id>/<model name>.<nam or wav>`, and it
  does not download the file again. You can delete the folder at any time.
- The project keeps the file as the adapter does (TONE3000 keeps its bytes,
  Neural Amp Modeler keeps its path), and keeps the tone in
  `meta.plugstate.tone3000.<slot>` of the device: `tone_id`, `tone`,
  `model_id`, `model`, `author`, `license` and `url`, so the project opens
  and plays without the network.
- Each request is a `curl` process with a time limit of 20 s for a search
  and 120 s for a download, and a key never waits for the network. paw tells you when
  you are not signed in, when TONE3000 limits the rate of requests, and
  when the computer is offline.
- `:checkhealth plugstate.tone3000` tells you if curl is there, where the
  token comes from, and the folder of the downloads.

### TONE3000 tokens

TONE3000 needs a token of your account to download a model. paw looks for
the token in this order, and uses the first one that it finds:

1. The environment variable `TONE3000_TOKEN`.
2. The file that `paw.opt.plugstate_tone3000_token_file` names. Only you
   can read the file, so run `chmod 600 <file>`.
3. The keyring, through `secret-tool`. Keep the token there with
   `secret-tool store --label="TONE3000 for paw" application paw service tone3000`.
4. The sign-in of `:plugstate.tone3000_login`. paw gets a new access
   token with the refresh token when the access token expires, or when
   TONE3000 refuses it (`401`), and if the refresh token expired too, paw
   tells you to sign in again.
5. The session of the TONE3000 plugin, from the `t3k_tokens` value in
   `~/.config/TONE3000/ui-preferences.settings`, and only when
   `paw.opt.plugstate_tone3000_plugin_session` is `true`. paw only reads this
   file and does not renew the session, so when the session expires, open the window of the plugin once.

paw sends the token to curl on its standard input, so the token never appears on a
command line, in a log, in a project or in a message.

The sign-in uses the device flow of `OAuth` (RFC 8628), as the API
reference of TONE3000 describes it. First, paw asks for a code at
`/api/v1/oauth/device_authorization`. Second, it asks `/api/v1/oauth/token`
at the interval that TONE3000 gives (5 s, and 5 s more after
`slow_down`). Third, it stops when you enter the code, or when the code expires
(10 minutes).

paw keeps the tokens of the sign-in in the keyring entry `application paw service tone3000-session`,
through `secret-tool store` with the tokens on its standard input. If
there is no keyring, paw keeps the tokens in the file of
`plugstate_tone3000_session_file`, of mode 600. paw also sends the form of a request of
the sign-in to curl on its standard input.

### The terms of TONE3000

The API of TONE3000 has terms of use (https://www.tone3000.com/api/terms), and
paw follows them in these ways:

- paw downloads a model only when you choose it, it does not download
  the library, and it does not write the results of a search to a file.
- paw shows the author and the license of each tone and keeps them in
  the project.
- The pane of the picker says "Powered by TONE3000" and gives the address
  of the tone.
- paw asks for one page when you ask for it, because TONE3000 permits 100 requests
  in a minute, and fewer for the search.

Do not share the models that you download in a way that their license
does not permit.

### Adapters

| Adapter | Plugins | How it sets the file |
| --- | --- | --- |
| `nam` | Neural Amp Modeler (LV2) | its `model` property. `:plugstate.info` shows the name, the kind of network, the gear and the loudness that the `.nam` file gives |
| `lsp-ir` | LSP Impulse Responses and LSP Impulse Reverb (LV2) | their impulse response properties (`ifn0`, `ifn1` and so on). The picker shows audio files |
| `sfizz` | sfizz (VST3) | sfizz has no properties as a VST3 plugin. The adapter writes the SFZ file into the saved state of the plugin, and paw loads that state |
| `lv2` | each other LV2 plugin with properties (`patch:writable`) | the property, with a message to the plugin as from its own window |
| `tone3000` | TONE3000 (CLAP, VST3, LV2) | it writes the state of the plugin. Slots are `preset` (a `.t3kpreset` file, with its chain and the values of its parameters), and `block1` to `block5` and `right1` to `right5` (the blocks of the two rows of the chain). A `.nam` or `.wav` file goes into a block with its bytes, as a file that you drop on the block in the window, and the name of a model that the block holds switches to that model |
| `juce` | each JUCE plugin with a description that has slots: Surge XT (CLAP, VST3, LV2) and Musio (VST3) | it writes the state of the plugin. Slots: `preset` (a `.jucepreset` file: its edits apply to the state of the device, in its format), and the values of the description (Surge XT: `name`, `octave`. Musio: `reverb`, `room`, `reverb_amount`) |
| `state` | each other plugin whose saved state opens (asked after the other adapters) | it writes the state of the plugin. Slot: `preset` (a `.jucepreset` file: its edits apply to the state of the device) |
| `soundshed` | Soundshed Guitar (VST3, LV2) | it writes the JSON state of the plugin. Slots: `preset` (a preset of a `.soundshed.presets` pack, or a `.json` preset), `scene` (the title or the number of a scene), and the blocks of the scene that take a file (`amp1`, `fx1`, `cab1` and other), set by the path of the file |

### The Lua module

`require("paw.plugstate")` gives these functions:

| Function | Result |
| --- | --- |
| `adapter(def)` | adds an adapter. paw asks an adapter added later first, and it asks an adapter with `fallback = true` after all the others |
| `adapter_of(id)` | the adapter for a device, and the device |
| `slots(id)` | the files and values of a device: `{ key, label, what, kind, types, value }`. A slot can also give `folders` (more folders to look in) or `list(roots)` (its own choices, as `{ path, name, folder }`) |
| `set(id, key, value)` | sets a slot (nil for the first) as one undo step, and returns `true`, or nil and the reason |
| `files(slot, roots)` | the files that a slot takes in the library folders: `{ path, name, folder }` |
| `search(slot, words)` | the files whose name or folder has each word |
| `neighbour(slot, n)` | the file `n` places after the current one in its folder |
| `snapshot(id, name)`, `recall(id, name)`, `step(id, n)`, `forget(id, name)` | the snapshots |
| `snapshots(id)`, `current(id)` | the snapshots of a device, and the name of the last one recalled or kept |
| `lane_state(id, key, value)`, `lane_snapshot(id, name)` | a slot set to a value, or a snapshot, as a state lane takes it. Nothing changes in the device |
| `lane_point(id, beat, state)` | gives the state from `beat` on, on the device's state lane (made if it has none), as one undo step |
| `share_dirs(sub)` | the folders `share/<sub>` of the packages in the plugin folders (`CLAP_PATH`, `VST3_PATH`, `LV2_PATH`, the Nix profiles), for factory presets |

The JUCE layer is in `require("plugstate.jucestate")`. See
[The state of JUCE plugins](../../docs/reference/juce-plugin-state.md).
The readers of each framework are in `require("plugstate.frameworks")`.
See [The saved state of plugins](../../docs/reference/plugin-state.md).

An adapter can also give `name_of(path)`, which returns the name of a choice for the
messages.

The extension sends the events `plugstate.loaded` (`device`, `slot`,
`value`) and `plugstate.recalled` (`device`, `name`).

### What the core gives

- `paw.api.device_call(id, "properties")` lists the properties of an LV2
  plugin as JSON: `uri`, `key`, `label`, `type` (`path`, `string`,
  `number`, `integer`, `boolean` or `other`), `writable`, `readable`,
  `file_types` and the `value` that the plugin told last.
- `paw.api.device_call(id, "property.set", '{"property": "model", "value": "/abs/path.nam"}')`
  sets one. The property is its URI, its key or its label. A path must be
  absolute, and the file must be there.
- `paw.api.device_load(id, { call = { method =, data = } })` makes a call
  that changes the state of the plugin one undo step, and the project
  keeps the state after the call.

### Limits

- A snapshot holds the whole state, and paw does not blend two snapshots,
  because the state of a plugin is not a set of numbers.
- A parameter lane does not change a model, but the state lane of the device
  does (see `:plugstate.at`).
- A plugin keeps the path of a file, so when the file moves, the plugin does
  not find it.
- The `sfizz` adapter reads the state of sfizz 1.2, and another version of
  sfizz can write its state in another way.
- The `tone3000` adapter reads the state of TONE3000 0.0.12, and the
  `soundshed` adapter the state of Soundshed Guitar 1.7.1.
- A program change in a clip does not change the preset of TONE3000 or
  Soundshed Guitar in paw, and the scene parameters of Soundshed Guitar do not
  change its scene. The state lane changes the scene through the saved
  state, exactly on the point in a rendered file and some milliseconds
  after the point as the song plays.
- Soundshed Guitar keeps the path of a file, so paw copies the files of a
  preset of a pack to `~/.local/share/paw/plugstate/<pack>`.
- `:plugstate.tree`, `:plugstate.mark`, `:plugstate.changes`,
  `:plugstate.path` and `:plugstate.preset_write` act on the device of the
  row of the device panel, else on the first plugin of the cursor track.
  `:plugstate.mark` keeps its state in memory and not in the project.
- Surge XT as a VST3 plugin does not take a state from paw, but its presets
  load in CLAP and LV2.
- The search of TONE3000 needs curl, and paw signs in to TONE3000 only with a token that you give or with `:plugstate.tone3000_login` (see [TONE3000 tokens](#tone3000-tokens)).
  paw loads models (`nam`) and impulse responses (`ir`) and not the other
  formats of TONE3000 (`aida-x`, `proteus`, `aa-snapshot`).
- TONE3000 and Soundshed Guitar keep their own files in `~/.config`
  (`TONE3000`, `Soundshed Guitar`), even when `XDG_CONFIG_HOME` names
  another folder.
