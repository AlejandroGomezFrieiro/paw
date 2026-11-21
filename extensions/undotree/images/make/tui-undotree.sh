#!/bin/sh
# The undo tree: an edit undone and another made in its place, and the tree
# window going back to the first branch.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.ext.load('extensions/undotree')"
rig_start
term_start
key j w; pause 0.4
rec_start tui-undotree
cap "3>ic moves the melody; u undoes; 2>ic moves it otherwise: a new branch"
pause 0.5; TYPE_DELAY=150 typ "3>ic"; pause 0.6; key u; pause 0.5
TYPE_DELAY=150 typ "2>ic"; pause 0.8
cap "Space pu opens the undo tree: neither change is lost"
key space p u; pause 1.6
cap "j k pick a state; Enter goes to it, the other branch; q closes the tree"
key j; pause 0.6; key Return; pause 1.2; key q; pause 1.6
rec_stop
