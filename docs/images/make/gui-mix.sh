#!/bin/sh
# Devices added by name, the mixer while the song plays, and a parameter's
# curve drawn with the pointer.
. "$MAKE/rig.sh"
rig_start $GUI_SIZE
gui_start
rec_start gui-mix
cap "Type a device's name to add it to the part"
pause 0.4
glide 1100 106; pause 0.2; xdotool click 1; pause 0.4
typ "chorus"; pause 0.5
key Return; pause 0.8
cap "Play, and open the mixer: a strip for every part"
glide 181 21; pause 0.2; xdotool click 1; pause 0.4
glide 892 21; pause 0.2; xdotool click 1; pause 0.8
cap "Drag a fader"
drag 262 652 262 643
pause 0.6
glide 892 21; pause 0.2; xdotool click 1; pause 0.4
cap "The curve beside a parameter automates it: draw the keys' cutoff"
glide 1230 400; pause 0.3; xdotool click 1; pause 0.7
stroke 250 330 420 300 590 270 760 290 935 262
pause 1.6
glide 149 21; xdotool click 1; pause 0.5
rec_stop
