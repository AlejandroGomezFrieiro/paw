# How to fix crackles and dropouts

You can stop clicks, crackles and short gaps in the sound. They happen
when the computer cannot compute a block of sound in time. Each command is
in [The audio engine](../reference/engine.md).

## Find the cause

1. Play the part that crackles.
2. Type `:engine.status`. The message gives the CPU use and the problems
   while the song played, such as the xruns (blocks that came too late),
   the late plugin blocks, and other counts.
3. Read the counts:
   - If the late plugin blocks increase, one plugin is too slow. Go to
     [Make the song lighter](#make-the-song-lighter).
   - If the xruns increase, the block size is too small for the computer.
     Go to [Make the block size larger](#make-the-block-size-larger).

## Make the block size larger

1. Type `:audio.buffer 256`. A larger block gives the computer more time
   for each block.
2. Play the part again. If it still crackles, try `512`, and then `1024`.

A larger block also makes the delay between a key and its sound longer.
When you record, use the smallest block that does not crackle, and when
you mix, a large block is fine.

## Make the song lighter

- Freeze a heavy instrument. Put the cursor on its track and type
  `:freeze`, and paw renders the track to a file and plays the file. The
  details are in [How to freeze a heavy track](freeze-a-heavy-track.md).
- Bypass the devices that you do not need now with `gcc` on a device in
  the device panel.
- If the computer is busy with other work, use fewer threads for the
  audio: `:engine threads=2`. To use one thread for each core again, type
  `:engine threads=0`.

## Check the system

- Close the programs that use much CPU, for example a web browser that
  plays video.
- In a shell, type `paw doctor`. It checks for dropouts and prints a
  report.
