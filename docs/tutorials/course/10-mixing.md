<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 10: The mix: faders, pan, buses, sends, automation

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 10`.*

In this lesson, we mix a short song. We change the level and the pan of the bass, and we send the keys through a bus. Then we give the melody an echo and make the chords fade in.

To mix, you set the level of each track with its fader, in dB, and its position from left to right with the pan. You mute some tracks, or solo a track to hear it alone. You also set where the sound of each track goes, which is either the master or a bus that groups tracks under one fader. A send can also take a part of the sound to an effect track.

Automation changes a fader, or a parameter, over time. The mixer shows one strip for each track, and you can make the same changes from the arrange view.

## The idea

In the mixer, the tracks go across. `h` and `l` select a strip, and `j` and `k` select a row of the strip. The rows are devices, sends, fader, pan, mute, solo and arm. `+` and `-` change the row under the cursor, by 1 dB on the fader. `]` and `[` pan, and `M`, `s` and `r` mute, solo and arm. In the arrange view, the same keys are `+` `-`, `]` `[` and `M` `s` `r`.

You set the routing with commands. `:track.output Bus` sends the track into the track with the name Bus, and `:track.output master` sends it to the master again. With no name, `:track.output` shows the tracks that you can select.

`A` adds a volume automation point at the cursor. `<Space>at` disables and enables the automation, and `<Space>ax` clears it.

## If you know Vim

In the mixer, the tracks are columns instead of rows, so `h` and `l` move between tracks. `j` and `k` only move, as in every view. `6<C-x>` decreases the row by six, as `<C-x>` decreases a number in Vim, and `<C-w>c` closes the mixer.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. Press `<Space>mm` to open the mixer at the bottom, with one strip for each track. Each strip has a fader and a meter.
   - ✓ The mixer gets the keys, and the master is on the right.
2. In the mixer, `h` and `l` select a strip, and the cursor starts on its fader. `-` and `+` change the row under the cursor by 1 dB. Press `l` to go to Bass, then press `-` three times.
   - ✓ Bass is at -7 dB, which is 3 dB lower than before. `3-` or `3<C-x>` does the same in one step.
3. `]` and `[` pan the strip to the right and to the left, at each row of the strip. Press `]` three times.
   - ✓ Bass is a little to the right.
4. `s` solos a track, so you hear only the soloed tracks. Press `<Space><Space>` to play and `s` to hear Bass alone. Press `s` again to hear all tracks, and `<Space><Space>` to stop.
   - ✓ With solo, you can listen to one track closely, and solo does not change the mix.
5. `M` mutes a track. Press `l` to go to Keys, and `M` to mute it.
   - ✓ Keys is muted, and its `M` is lit.
6. Press `M` again to unmute Keys, and press `<C-w>c` to close the mixer.
   - ✓ The arrange view gets the keys again, and the cursor is still on Keys. In the arrange view too, `+` and `-` change the fader, and `]` and `[` change the pan.
7. A bus is a track that other tracks play into. Type `:track.add Bus` and press `<CR>` to add one.
   - ✓ A track with the name Bus shows below Keys, and the cursor is on it.
8. Now send Keys into the bus. Type `/Keys` and `<CR>` to find the track, and then type `:track.output Bus` and `<CR>`.
   - ✓ Keys now plays through Bus. The fader of Bus changes the level of the chords and of each other track that you send there.
9. A send copies a part of a track to a different track, which here is Echo, a track with a delay. Type `/Lead` and `<CR>` to find the track, and then type `:send Echo -6` and `<CR>`.
   - *Hint:* `<Space>ts` does the same, but it asks for the track and sends at the default level.
   - ✓ Lead sends to Echo at -6 dB, so the melody now has an echo. The fader of Echo sets the level of the echo.
10. Now we add automation. `A` adds a volume point at the cursor and asks for its value. Type `/Keys` and `<CR>` to return to Keys, and then press `0` and `A`. Press `<C-u>` to clear the value, type `-30` and press `<CR>`.
    - *Hint:* The cursor must be on Keys. Type `/Keys` and `<CR>`.
    - ✓ A point of -30 dB is at the start, and an `A` shows in the track header.
11. Press `2W` to move two bars. Then press `A` and `<C-u>`, type `-10` and press `<CR>`, so that the chords fade in over two bars.
    - ✓ The lane of the track shows the line between the points.
12. Listen from the start. Press `gs` and `<Space><Space>`, and `<Space><Space>` to stop.
    - ✓ The chords fade in through a bus, the melody has an echo, and the bass is on the right.

## What we did

We used the faders, pan, solo and mute of the mixer. We made a bus with `:track.output`, and we added a send and volume automation with `A`.

- Previous: [Devices, parameters and plugins](09-devices.md)
- Next: [Loops, marks and jumps](11-loops.md)
- [All lessons](README.md)
