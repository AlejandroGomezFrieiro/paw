#!/bin/sh
# The piano roll with the pointer: the melody's open last bar drawn,
# a note moved, velocities drawn, and played. (The clip is opened with a
# double click, before the recording starts.)
. "$MAKE/rig.sh"
rig_start $GUI_SIZE
gui_start
# The melody opened with a double click, and zoomed out a step.
glide 700 390; xdotool click --repeat 2 --delay 60 1; pause 1.0
glide 600 550; xdotool keydown ctrl; xdotool click 5; xdotool keyup ctrl; pause 0.6
rec_start gui-pianoroll
# The roll: bar 5 at x 64, 55.75 a beat, bar 8 at 733; E5 at y 515, 12 a semitone.
cap "Drag on the grid to draw a note as long as the drag"
drag 736 515 845 515
drag 848 575 900 575
drag 904 623 952 623
pause 0.3
cap "Drag a note to move it"
drag 925 623 925 611
pause 0.4
cap "Draw the velocities in the strip under the notes"
key Escape; pause 0.2
stroke 66 725 300 705 520 720 735 700 950 712
pause 0.6
cap "A click on the ruler moves the playhead; Space Space plays"
glide 512 380 10; xdotool click 1; pause 0.3
key space space; pause 3.6; key space space; pause 0.4
rec_stop
