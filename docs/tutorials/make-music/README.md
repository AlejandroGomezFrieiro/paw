# Make music with paw

In these five lessons, we make one short song with paw, from an empty
project to an MP3 file. We write drums, a bass and chords, and then we play
a lead on a MIDI keyboard and record a guitar. At the end, we arrange the
song, mix it and render it. Each lesson takes 15 to 25 minutes and ends
with music that you can hear.

The lessons are written for musicians, so we expect that you know what a
DAW, a part, a plugin and a MIDI keyboard are. You do not need to know Vim
or Lua. You play paw from the keyboard, so each step gives the keys to
press. The lessons show the terminal, and the graphical window shows the
same views.

| | Lesson | What we make |
| --- | --- | --- |
| 1 | [Your first song](01-first-song.md) | Drums, a bass and chords in a loop of four bars, saved as a project. |
| 2 | [Play a synth from a MIDI keyboard](02-play-a-midi-keyboard.md) | A lead that we play live, record over the loop and quantize. |
| 3 | [Record a guitar](03-record-a-guitar.md) | A guitar through an amp chain, two takes, the best parts of each, and a fade. |
| 4 | [Arrange the song](04-arrange-the-song.md) | Verse and chorus, markers for the parts, a new tempo, and jumps to a part. |
| 5 | [Mix and render the song](05-mix-and-render.md) | Levels, pan, an equalizer, a compressor, a reverb on a send, automation, a WAV and an MP3. |

## Before you start

You need paw, a folder for your songs and, for two of the lessons, some
hardware:

- Install paw (see [How to install paw with Nix](../../how-to/install-paw.md)).
- Make a folder for your songs, and open a terminal in it. paw saves a new
  song into the folder where it starts, and after that it saves and
  renders next to the song.
- For lesson 2, connect a MIDI keyboard. For lesson 3, connect an audio
  interface with a guitar on its input 1.

Each lesson from lesson 2 on opens a practice project, which is the song as
the lesson before left it. You can do any lesson again, or start at any
lesson. `:example` opens a practice project, and `Tab` completes its name.

The practice projects are Lua files in the `examples/tutorials/make-music`
folder of paw. The package of paw sets `PAW_HOME` to the folder that holds
`examples`. If you run paw from its source folder, start it in that
folder, or set `PAW_HOME` to it.

**CAUTION:** Set the volume of your speakers or headphones low before you
start, because a new synth can be loud.

## After these lessons

[The course](../course/README.md) teaches the keys of paw in seventeen
short lessons, and you can also do it inside paw with `:tutor`. The
[how-to guides](../../README.md#how-to-guides) give the steps for one
task each. [Keys, by idea](../../reference/keys.md) is a page of keys to
keep near the keyboard.
