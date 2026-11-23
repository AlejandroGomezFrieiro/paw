#!/bin/sh
# :Pdiff on the demo song saved and then edited: the melody moved, a part
# renamed and turned down, notes changed; the changes as a folded text, and
# Enter going to one.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.ext.load('extensions/projdiff') paw.commands.exec('w $D/song.json')"
rig_start
term_start
key j w; pause 0.4
TYPE_DELAY=60 typ "2>ic"; pause 0.3
key colon; TYPE_DELAY=40 typ "%s/e5/g5/g"; key Return; pause 0.3
key colon; TYPE_DELAY=40 typ "part.rename Melody"; key Return; pause 0.3
ctl "paw.parts()[2].volume = -8" >/dev/null; pause 0.5
rec_start tui-projdiff
cap ":Pdiff compares the project with its file as saved, by what is in it"
pause 0.5; key colon; TYPE_DELAY=110 typ "Pdiff"; key Return; pause 2.0
cap "]c goes from change to change; za folds one away and opens it, as in Vim"
keys 0.7 bracketright c bracketright c; key z a; pause 1.0; key z a; pause 0.6
keys 0.7 bracketright c bracketright c; pause 0.6
cap "Enter closes it and puts the cursor on the change"
key Return; pause 2.0
rec_stop
