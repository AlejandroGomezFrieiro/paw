# How to deal with a plugin that crashes or hangs

This guide shows you what to do when a plugin stops. It also shows what to
do when a project does not open because of a plugin. paw runs each plugin in a process of
its own. So a plugin that crashes stops only itself, not paw. For each
rule, see [Plugins](../reference/plugins.md#processes).

## A plugin stopped while you work

1. Read the message. It names the plugin, the track and the reason, for
   example `stopped working: it was killed`. The track plays on without
   the plugin: an effect lets the sound through, an instrument is silent.
2. Put the cursor on the track and press `<Space>dd` to show the device panel.
   Press `w` until the cursor is on the name of the plugin.
3. Press `gR` to start the plugin again. It gets the settings that the
   project has for it.

If the plugin stops again, set it offline: press `o` on its name. paw
then does not start the plugin, and keeps its settings in the project.
Press `o` again to try it later.

If a plugin does not answer for two seconds, it hangs. paw stops it, and
it shows as stopped. Do the same steps.

## A project does not open because of a plugin

1. Open the project with its plugins offline:
   `:edit /home/ana/songs/demo offline`.
2. Set the plugins online one at a time: press `o` on each plugin in the
   device panel. When paw crashes or a plugin stops, you know which
   plugin it is.
3. Keep that plugin offline, and save the project.

For more ways, see
[How to open a project without its plugins](open-a-project-without-its-plugins.md).
If paw itself stopped, see [How to recover lost work](recover-lost-work.md).

## Report the problem

- Look in `~/.cache/paw/stderr.log`. Plugins write their errors there.
- In a shell, type `paw doctor --only plugins`. It counts the plugins of
  each format, and names the files that the scan could not use.

A Windows plugin through yabridge can also have a black or a small
editor. See [How to fix a plugin editor that does not work](fix-a-plugin-editor.md).
