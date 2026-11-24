#!/bin/sh
# Finding your way: ? lists the keys, the leader alone lists its keys,
# K describes what is under the cursor, and :help opens the manual inside.
. "$MAKE/rig.sh"
SETUP=$TUI_DEMO
rig_start
term_start
key j w; pause 0.4
rec_start tui-help
cap "? lists every key of the view you are in"
pause 0.5; key question; pause 2.0; key Escape; pause 0.3
cap "Space alone waits and lists what can follow it"
key space; pause 1.8; key Escape; pause 0.3
cap "K says what is under the cursor"
key K; pause 1.8; key Escape; pause 0.3
cap ":help opens the manual where a topic is described"
key colon; TYPE_DELAY=100 typ "help motions"; key Return; pause 2.4
# The loop: close the help window, back to the start screen.
key ctrl+w c; pause 0.8
rec_stop
