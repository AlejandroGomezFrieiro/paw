# How to deal with a plugin that crashes or hangs

You can recover when a plugin stops, and you can open a project that does
not open because of a plugin. paw runs each plugin in a process of its
own, so a plugin that crashes stops only itself and not paw. The rules are
in [Plugins](../reference/plugins.md#processes).

## A plugin stopped while you work

1. Read the message. It names the plugin, the part and the reason, for
   example `stopped working: it was killed`. The part plays on without
   the plugin, so an effect lets the sound through and an instrument is
   silent.
2. Put the cursor on the part and press `<Space>dd` to show the device panel.
   Press `w` until the cursor is on the name of the plugin.
3. Press `gR` to start the plugin again, and it gets the settings that the
   project has for it.

If the plugin stops again, press `o` on its name to set it offline. paw
then does not start the plugin, but it keeps its settings in the project.
Press `o` again when you want to try it later.

If a plugin does not answer for two seconds, it hangs, and paw stops it.
The plugin then shows as stopped, and you can use the same steps.

## A project does not open because of a plugin

1. Open the project with its plugins offline:
   `:edit /home/ana/songs/demo offline`.
2. Set the plugins online one at a time with `o` on each plugin in the
   device panel. When paw crashes or a plugin stops, you know which
   plugin it is.
3. Keep that plugin offline, and save the project.

[How to open a project without its plugins](open-a-project-without-its-plugins.md)
gives more ways.
If paw itself stopped, see [How to recover lost work](recover-lost-work.md).

## Report the problem

- Type `:log!` after paw starts again, or `:log` if paw still runs. The
  log has what each plugin printed, with the name of the plugin, and
  the events before a crash. See
  [How to find out what went wrong](find-out-what-went-wrong.md).
- In a shell, type `paw doctor --only plugins`. It counts the plugins of
  each format, and it names the files that the scan could not use.

A Windows plugin that runs through yabridge can also have a black or a
small editor. The fix is in
[How to fix a plugin editor that does not work](fix-a-plugin-editor.md).
