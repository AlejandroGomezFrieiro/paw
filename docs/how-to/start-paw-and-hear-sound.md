# How to start paw the first time and hear sound

<!-- tags: first-start test-tone -->

You can start paw, check the sound system, and hear a test tone. The steps
assume that paw is installed, and that your speakers or headphones are
plugged in. To install paw, see
[How to install paw with Nix](install-paw.md).

## Check the computer before you start

1. In a shell, type `paw doctor`. paw opens the audio device, runs the
   checks that need no person, and prints a report.
2. Read the table of checks at the top of the report, where each check is
   `ok`, `warn` or `fail`, with a sentence.
3. If "The sound system" warns about a Bluetooth output or a large block,
   correct that first, as
   [How to choose the audio devices](choose-audio-devices.md) shows.

## Start paw

1. Type `paw` in a terminal, and the arrange view opens with an empty
   project.
2. Look at the right end of the status line, where the engine indicator
   names the sound system and the CPU load.
3. Type `:checkhealth audio` and press `Enter`. A window shows each result
   as OK, WARN or ERROR, with advice under it.
4. Press `q` to close the window.

If the check says "the null audio backend: nothing is heard", paw started
without a sound device. Start paw again without `--audio null`.

## Hear a test tone

**WARNING:** Turn the volume down before you play the tone, because a loud
tone can damage your ears.

1. Type `:ext.load doctor`, and the doctor extension loads for this
   session.
2. Type `:doctor output`. A soft tone plays one second on the left, one
   second on the right, and then on both sides.
3. Answer the question with the key that the page shows under it. For
   example, press `y` if you heard all of the tone.
4. Press `q` to close the page.

If you heard nothing, type `:audio`, select a different output and press
`Enter`. Then type `:doctor output` again.

In the graphical window, the doctor page has a button for each answer.

## Hear an instrument

<!-- paw-live: {"empty": true} -->

1. Press `o`, and paw adds a track.
2. Press `a`, type `synth` and press `Enter`. The built-in synth is now on
   the track.
3. Press `i` and `Enter`, then `4l`, and then `Esc`. paw writes a note of one beat into a new clip.
4. Press `gs` to move the playhead to the start, and press
   `<Space><Space>`. The note plays, and the meter of the track moves.

## See also

- [How to add a track with a virtual instrument](add-an-instrument-track.md)
- [How to lower the latency](lower-the-latency.md)
- [The doctor](../../extensions/doctor/README.md): every check, and the report.
- [Audio devices](../reference/audio-devices.md)
