#!/bin/sh
# The stills that are not taken on the way through a scene: the window
# playing the song, and its panes.
. "$MAKE/rig.sh"
rig_start $GUI_SIZE
gui_start
glide 181 21; xdotool click 1; pause 0.4
glide 700 700
pause 9.6
still gui.png
glide 149 21; xdotool click 1; pause 0.5
# The panes: the melody in the piano roll, the parts as text beside it.
glide 700 390; xdotool click --repeat 2 --delay 60 1; pause 1.2
glide 600 550; xdotool keydown ctrl; xdotool click 5; xdotool keyup ctrl; pause 0.4
typ ":vs paw://parts"; key Return; pause 1.2
glide 700 790 6; pause 0.4
still gui-panes.png
