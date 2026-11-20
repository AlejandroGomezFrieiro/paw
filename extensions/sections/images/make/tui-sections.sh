#!/bin/sh
# Song sections: the demo song named Intro and Verse, gone between, and the
# verse repeated after itself, every track at once.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.ext.load('extensions/sections')"
rig_start
term_start
rec_start tui-sections
cap ",Sa names a section at the cursor: Intro here, Verse at bar 5"
pause 0.5; key comma S a; pause 0.4; TYPE_DELAY=110 typ "Intro"; key Return; pause 0.6
keys 0.15 4 W; key comma S a; pause 0.4; TYPE_DELAY=110 typ "Verse"; key Return; pause 0.8
cap "[[ ]] go between sections; they are motions and text objects too"
keys 0.6 bracketleft bracketleft bracketright bracketright; pause 0.4
cap ",S& repeats the section after itself, on every track, pushing the rest along"
key comma S ampersand; pause 1.8
cap "u undoes it as one step"
key u; pause 1.2
rec_stop
