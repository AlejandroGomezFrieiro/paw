# Lesson 5: Mix and render the song

*The lesson takes about 25 minutes.*

In this lesson, we mix the song of lesson 4 and render it to files. First,
we set the levels and the pan. Second, we put an equalizer on the bass and
a compressor on the drums, and we send the chords and the lead to a
reverb. Third, we make the lead come up at the chorus. At the end, we
render the song to a WAV file and an MP3 file, and listen to the file.

## Open the practice project

1. Start paw in your folder for songs. Type
   `:example make-music/5-mix` and press Enter.

   - paw opens the arranged song of lesson 4, with its markers.

## Set the levels and the pan

1. Press `<Space>mm` (the space bar, then m two times).
   - The mixer opens at the bottom, with one strip for each part. The
     cursor is on the fader of Drums.
2. Press `V` and `$`, then `6-`. Press `<Esc>`.
   - `V` selects strips, and `$` goes to the last strip. `6-` lowers each
     selected fader by 6 dB, so the mix now has room before it clips.
3. Press `0` (the first strip) and `l` (Bass). Press `3-`.
   - The bass is 3 dB lower than the other parts.
4. Press `l` (Keys) and `j` to go to the pan row. Press `3-`.
   - The chords move to the left, and the title bar shows the pan.
5. Press `2l` (Guitar) and `3+`.
   - The guitar moves to the right.
6. Press `<C-w>c` to close the mixer.

## Add an equalizer and a compressor

1. Type `/Bass` and press Enter. Press `<Space>dd` to open the device panel.
2. Press `a`, type `eq` and press Enter.
   - The equalizer comes after the synth.
3. Press `gg` (the first device) and `w` (the next device, EQ). Press `c`.
4. Type `tighten` and press Enter.
   - The preset `Bass: tighten` takes away some of the muddy low
     frequencies, and the curve shows in the panel.
5. Press `<Space>dd` to close the device panel.
6. Type `/Drums` and press Enter. Press `<Space>dd`.
7. Press `a`, type `compressor` and press Enter.
8. Press `gg`, `w` and `c`. Type `glue` and press Enter.
   - The preset `Drum bus: glue` compresses the kit a little. While the
     song plays, the panel shows the gain reduction.
9. Press `<Space>dd` to close the device panel.

## Send the chords and the lead to a reverb

1. Press `G`. Type `:part.add Reverb` and press Enter.
   - A part with the name Reverb shows at the bottom.
2. Press `<Space>dd`. Press `a`, type `reverb` and press Enter.
3. Press `gg` and `c`. Type `on a send` and press Enter.
   - The preset `Plate on a send` gives a reverb with no dry sound.
4. Press `<Space>dd`.
5. Type `/Keys` and press Enter. Type `:send Reverb -9` and press Enter.
   - paw says `Keys ↗ Reverb at -9 dB`.
6. Type `/Lead` and press Enter. Type `:send Reverb -12` and press Enter.
7. Press `gs` and `<Space><Space>`, and listen. Press `<Space><Space>` to stop.
   - The chords and the lead now have reverb, and the fader of the Reverb
     part sets how much.

## Make the lead come up at the chorus

1. With the cursor on Lead, press `5|` to go to bar 5.
2. Press `A`.
   - `A` adds a point of volume automation and asks for its value.
3. Press `<C-u>`, type `-20` and press Enter.
4. Press `W` to go to bar 6. Press `A`, `<C-u>`, type `0` and press Enter.
   - The lane of the part shows a line from -20 dB up to 0 dB, so the
     lead comes up over the first bar of the chorus.

## Save and export

1. Type `:w my-song` and press Enter.
2. Type `:export my-song.wav` and press Enter.
   - paw puts the file in the folder `renders` of the song,
     `my-song/renders`.
   - The status line shows the progress. Then paw says
     `wrote renders/my-song.wav`, with the length and the peak level.
   - If the message ends with `(clips)`, the mix is too loud. Lower the
     faders and export again.
3. Type `:export my-song.mp3` and press Enter.
   - paw writes the MP3 file with `ffmpeg`, which the package of paw
     includes.

## Listen to the file

1. Type `:e renders` and press Enter.
   - The folder `renders` of the song shows as a list of files, with the
     length of each sound file.
2. Type `/my-song.wav` and press Enter. Press `gh`.
   - `gh` plays the file, which is your song as other people hear it.
3. Press `gh` to stop. Press `<C-^>` (Ctrl and 6) to return to the
   arrange view.

## What we made

We mixed the song with the faders, the pan and three built-in effects. We
sent two parts to a reverb and automated the volume of the lead. Then we
exported the song to a WAV file and an MP3 file, which you can share. You
now have a whole song, from the first note to the MP3 file.

- Previous: [Arrange the song](04-arrange-the-song.md)
- [All lessons](README.md)

For more, see [The mixer](../../reference/mixer-view.md),
[Routing](../../reference/routing.md) for sends,
[Automation](../../reference/automation.md) and
[How to export a song as WAV, FLAC or MP3](../../how-to/export-a-song.md).
