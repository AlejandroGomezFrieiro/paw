# How to find and change a setting inside a plugin

You can see the saved state of a plugin, find where it keeps a setting,
and change that setting from paw. The steps work for plugins made with
JUCE, DPF, iPlug2, LSP, Dplug and nih-plug, and for LV2 plugins. They
assume that the plugin is on a part and that the
[plugstate](../../extensions/plugstate/README.md) extension is loaded
(`:ext.load plugstate`).

## See the state of the plugin

1. Open the device panel and put its row on the plugin.
2. Type `:plugstate.tree`, and paw shows the state as a tree. The first
   line names the framework of the plugin and the layers around its data.
3. To see one part, give its path: `:plugstate.tree /LSP/Parameters`.

`:plugstate.info` also names the framework, with the count of the
parameters that the state holds.

## Find where the plugin keeps a setting

1. Type `:plugstate.mark`, and paw keeps the state of the plugin.
2. Change one setting in the window of the plugin.
3. Type `:plugstate.changes`. paw lists the paths that changed, for
   example `set /LSP/Parameters@g_out: 1 → 0.5`.

When the list has more than one path, the other paths can be values that
changed on their own. An example is the size of the plugin's window.

## Change the setting from paw

1. Type `:plugstate.path` with the path and the new value:
   `:plugstate.path /LSP/Parameters@g_out 0.5`. paw loads the changed
   state into the plugin as one undo step.
2. To see a value, give only the path: `:plugstate.path /LSP/Parameters@g_out`.
3. To return to the value before, press `u`.

## Keep the change as a preset

1. Type `:plugstate.mark`, and change the settings in the plugin.
2. Type `:plugstate.preset_write ~/quiet`. paw writes the changes after the
   mark to `~/quiet.jucepreset`.
3. Use the preset:
   - To load the preset into the same plugin on another part, type
     `:plugstate.load ~/quiet.jucepreset`.
   - To change to the preset at a point of the song, put the cursor there
     and type `:plugstate.at ~/quiet.jucepreset`.

A preset of a JUCE, DPF or LSP plugin works in each format of the plugin.
The paths and the forms of each framework are in
[The saved state of plugins](../reference/plugin-state.md).
