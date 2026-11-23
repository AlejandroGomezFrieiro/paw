#!/bin/sh
# The quartet's score edited in the terminal: the cursor's staff is the
# part the keys write, marked at its start, the others dimmed; ]] goes to
# the next instrument, notes are entered there by name, and a block over
# three staves takes their bars.
. "$MAKE/rig.sh"
SETUP="dofile('extensions/notation/fixtures/quartet.lua') require('notation').space = 9 paw.opt.score_dim = true"
rig_start
term_start
key ctrl+w o; pause 1.2
rec_start tui-score
cap "The full score: the cursor's staff is the part the keys write"
pause 1.2
cap "]] goes to the next instrument; Ctrl-j Ctrl-k a staff down, up"
key bracketleft bracketleft; pause 0.8; key bracketleft bracketleft; pause 0.8; key bracketright bracketright; pause 0.8; key bracketright bracketright
pause 0.6
still tui-score-active.png
cap "Ctrl-v and Ctrl-k: a block of bars over the staves"
keys 0.3 4 W; key ctrl+v; keys 0.4 ctrl+k ctrl+k W
pause 1.2
still tui-score-block.png
cap "gU: a step up, on each staff's clip, one undo step"
key g U; pause 1.4
key Escape; pause 0.3
rec_stop
