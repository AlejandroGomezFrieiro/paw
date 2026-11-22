# How to use your own plugins

<!-- tags: use-plugins yabridge -->

You can make your CLAP, VST3 and LV2 plugins available in paw, and you can
use Windows plugins through yabridge. The rules are in
[Plugins](../reference/plugins.md).

## Put the plugins where paw looks

paw looks for plugins in the following directories:

| Format | Directories |
| --- | --- |
| CLAP | `~/.clap`, `/usr/local/lib/clap`, `/usr/lib/clap`, the Nix profiles |
| VST3 | `~/.vst3`, `/usr/local/lib/vst3`, `/usr/lib/vst3`, the Nix profiles |
| LV2 | `~/.lv2`, `/usr/local/lib/lv2`, `/usr/lib/lv2`, the Nix profiles |

1. Install the plugin into one of the directories. An installer for Linux
   usually does that for you.
2. If your plugins are in a different directory, set the variable of the
   format before you start paw, for example
   `CLAP_PATH=/opt/plugins/clap paw`. paw then looks only in the
   directories of the variable, so give all of them, with `:` between.
3. Start paw, and paw reads the new plugin files at the start.

## Read the plugins again

If you install a plugin while paw runs, type `:plugins.rescan`. To read
only some files again, give a part of the name: `:plugins.rescan surge`.

paw does not read a file again if it crashed the scan before, and a
message at the start names the file. `:plugins.rescan` reads that file
again too.

## Add a plugin to a track

1. Select the track and press `a`, and the list of devices opens.
2. Type a part of the name of the plugin, for example `surge`, and press
   `Enter`. The editor of the plugin opens.

You can also type `:device.add surge`. To show the editor again later,
press `ge` on the track.

## Use Windows plugins through yabridge

1. Install the plugin in Wine with its Windows installer.
2. Tell yabridge where the plugin is, and then let yabridge make the
   bridges:

   ```sh
   yabridgectl add "$HOME/.wine/drive_c/Program Files/Common Files/VST3"
   yabridgectl sync
   ```

3. In paw, type `:plugins.rescan`. The plugin is now in the list of
   devices, as a VST3 or CLAP plugin.

The editor of a Windows plugin can be black, or not take the pointer. If
it is, see [How to fix a plugin editor](fix-a-plugin-editor.md).

To check that a plugin loads and makes sound, use the doctor:

1. Type `:ext.load doctor`.
2. Type `:lua paw.opt.doctor_plugins = { "surge" }`, with a part of the
   name of the plugin.
3. Type `:doctor plugins`. The doctor plays notes into the plugin and
   tells you if sound came out.

## See also

- [Plugins](../reference/plugins.md): formats, scan, editors, presets, crashes.
- [About the plugin sandbox](../explanation/about-the-plugin-sandbox.md): why each plugin runs in a process of its own.
