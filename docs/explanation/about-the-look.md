# About the look of paw

<!-- tags: look -->

paw keeps the content of the screen in neutral colors and uses strong color
only where your attention must go. The screen of a DAW shows much
information at once, e.g., parts, clips, notes, meters and lanes. If all of
it had strong colors, you could not see the important parts.

## Color for attention

Amber marks the focus, which means the focused panel, the playhead and the
keys to press. The color of the mode is on the mode pill and on the cursor,
so you see the mode where you already look. Red marks recording and errors
and nothing else, so a red mark is always important.

## The color of a part

Each part has a color, and paw draws everything that belongs to the part
in shades of that color. A clip has a name row and a darker body with its
notes or its waveform. The clip under the cursor shows in the full color.
The part of the cursor has a brighter header and a tinted lane. You can see which clips belong to which part without reading the names,
also in the piano roll and the mixer.

## Why paw draws in cells first

paw draws in terminal cells first, because cells work in every terminal and
also through SSH and tmux. For example, a curve drawn with sextant
characters is a connected line with no gaps. A waveform drawn in cells
shows the hits of a drum part. Where the terminal can show images, paw
adds pixels, and the same view draws the same content in both. See
[Pictures in the terminal](../reference/pictures.md).

## The same look in both frontends

The graphical window uses the same twelve part colors as the terminal,
and each color has the same meaning. A person who learns one frontend can
read the other.

## See also

- [The terminal screen](../reference/screen.md).
- [Options](../reference/options.md#screen).
