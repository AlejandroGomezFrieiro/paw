# How to open a project without its plugins

You can open a project when a plugin crashes, hangs, or is slow to load,
by opening it with its plugins offline. Each way and flag is in
[Plugins](../reference/plugins.md#offline-devices).

1. Open the project with its plugins offline:
   - From the shell: `paw --plugins-offline song`.
   - From paw: `:edit song offline`.
   - After a crash: `:recover`, and then select an entry with
     "(plugins offline)".

   paw opens the project, each plugin shows as offline, and the tracks
   play without the plugins.
2. To find the plugin with the problem, set the plugins online one at a
   time. In the device panel, select a device and press `o`. If a plugin
   crashes again, press `o` on it again to keep it offline.
3. To set all the other plugins online, type `:plugins.online`.
4. Save the project, and the offline flags are saved with it.

If a plugin fails while the project opens, paw records it. The next time,
paw opens the project with that plugin offline, and a message says so. To
open the project with all its plugins, type `:edit song online`.
