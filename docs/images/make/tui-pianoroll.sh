#!/bin/sh
# The piano roll: the melody's open last bar drawn with the cursor, more
# notes drawn one after the other, then selected and taken up a semitone.
# The scene makes 4 changes (two draws, Ctrl-a, Ctrl-x): the end undoes them.
. "$MAKE/rig.sh"
SETUP=$TUI_DEMO
rig_start
term_start
key j w; pause 0.4
rec_start tui-pianoroll
cap "Enter opens the clip under the cursor in the piano roll"
pause 0.6; key Return; pause 1.0
keys 0.25 W W W
cap "i draws a note with the cursor: 8l makes it eight steps long"
key i; pause 0.3; keys 0.2 8 l; pause 0.5; key Escape; pause 0.9
cap "Enter keeps a note and draws the next; K takes a note up an octave"
key i; pause 0.3; keys 0.3 4 l Return 4 l K Return 2 l; pause 0.5; key Escape; pause 1.0
cap "vib selects the bar; Ctrl-a takes it up a semitone; gv Ctrl-x back down"
keys 0.25 b v i b; pause 0.4; key ctrl+a; pause 1.0
keys 0.25 g v; key ctrl+x; pause 1.4
# The loop: close the piano roll, undo the 4 changes, put the cursor and the playhead back.
key ctrl+w c; pause 0.4; TYPE_DELAY=150 typ "4"; key u; pause 0.5; keys 0.2 0 w g s; pause 0.8
rec_stop
