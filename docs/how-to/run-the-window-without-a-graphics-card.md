# How to run the graphical window without a graphics card

You can start the graphical window without a graphics card, or when the
driver of the card does not work. The window then draws with Mesa's
llvmpipe on the processor.

1. Make sure that Mesa is installed. On NixOS, set
   `hardware.graphics.enable = true`.
2. Start the window with the software renderer:

   ```sh
   paw-gui --renderer software song
   ```

3. If you want the software renderer each time, set the variable in your
   shell profile:

   ```sh
   export PAW_GUI_RENDERER=software
   ```

If the window shows one line about OpenGL and stops, OpenGL cannot start
at all. In that case, use the terminal (`paw song`), which has the same
views.

At rest, the window uses no processor time. While the song plays, expect
about a tenth of a core, because the window draws only the parts that
change. The measured values are in [Graphics](../reference/window.md#graphics).
On the processor, the window draws 15 frames a second while the song
plays. To use less of the processor, type `:set window_fps=10` and press
`Enter`, and the playhead then moves in larger steps.

## Make the window use the graphics card again

When the window draws on the processor, it shows a warning when it
starts. To find the cause, type `:checkhealth window` and press `Enter`.
The first advice under the warning is the likely cause.

1. Remove what forces the software renderer:
   - If you set `PAW_GUI_RENDERER=software`, remove it from your shell
     profile, and start the window without `--renderer software`.
   - If `LIBGL_ALWAYS_SOFTWARE` is set, remove it.
2. If the system has no driver for the graphics card, install it. On
   NixOS, set `hardware.graphics.enable = true`.
3. If you started the window over SSH or VNC, start it on the screen of
   the computer.
4. Start the window again, and type `:checkhealth window`. It must say
   `OK the window draws on the graphics card`.
