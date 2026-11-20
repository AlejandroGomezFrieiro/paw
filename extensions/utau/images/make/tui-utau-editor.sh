#!/bin/sh
# The vocal editor on the sung melody (scene.lua): the phonemes under the
# notes, a vibrato and a louder note, sung again, and played with the
# playhead going through the rendered phrase.
. "$MAKE/rig.sh"
. "$(dirname "$0")/engine.sh"
SETUP="UTAU_SINGER = '$SINGER' dofile('extensions/utau/images/make/scene.lua')"
rig_start
term_start
key Return; pause 4.0
rec_start tui-utau-editor
cap "The vocal editor: lyrics on the notes, the phonemes sung in the row under them"
pause 1.4
cap "~ puts a vibrato on the long note; ]c picks a curve, } raises it there"
keys 0.15 7 w; key asciitilde; pause 1.0
keys 0.3 bracketright c; keys 0.15 4 braceright; pause 1.0
cap "r sings the clip again; Space Space plays from the cursor"
key r; pause 1.6; key 0; key space space; pause 5.0; key space space; pause 0.4
rec_stop
rm -rf "$XDG_RUNTIME_DIR"
