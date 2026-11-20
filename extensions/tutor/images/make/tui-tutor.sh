#!/bin/sh
# The course inside the program: :tutor opens the first lesson in a
# practice project, and its panel follows what you do.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.ext.load('extensions/tutor')"
rig_start
term_start
rec_start tui-tutor
cap ":tutor! opens the course where you left off: lesson 1, in a practice project"
pause 0.5; key colon; TYPE_DELAY=110 typ "tutor!"; key Return; pause 2.6
cap "The panel says what to do with the exact keys, and notices when it is done"
keys 0.15 space space; pause 1.4; keys 0.15 space space; pause 1.4; key g s; pause 1.0
rec_stop
