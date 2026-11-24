#!/bin/sh
# The basics, as a recorded terminal session for the first page of the
# website (tools/website/landing.md): move, select and copy, a change of
# volume, a note in the piano roll, undo, and play. The reader can pause
# it and copy the keys of each step (tools/website/paw-cast.js).
#
# CHANGES is the count of undo steps that the scene makes. The part
# numbers (4G) are for the demo song's rows.
CHANGES=3
SETUP="dofile('examples/demo-song.lua') paw.opt.zoom = 2 paw.cursor.set_part(paw.parts()[1]) paw.flush()" \
  python3 "$MAKE/cast.py" cast-basics "$WORK/cast-basics.cast" <<EOF
pause 1.5
caption Move: j and k go over the parts, w and b over the clips, gg to the first part
keys jj
pause 0.4
keys wwb
pause 0.4
keys gg
pause 1.0
caption Select and copy: vic selects the melody, y copies it, and 0P pastes it at the start
keys 4G0w
pause 0.4
keys vic
pause 0.6
keys y
pause 0.4
keys 0P
pause 1.2
caption V selects whole parts: Vk selects two, and 3- turns them down 3 dB
keys Vk
pause 0.4
keys 3-
pause 1.4
caption Enter opens the clip in the piano roll, i draws a note, and 8l makes it longer
keys 4G5|
pause 0.3
keys <CR>
pause 1.0
keys WWW
pause 0.3
keys i8l<Esc>
pause 1.2
caption Ctrl-w c closes the piano roll, and ${CHANGES}u undoes the ${CHANGES} changes
keys <C-w>c
pause 0.8
keys ${CHANGES}u
pause 1.2
keys gg0
pause 0.8
caption Space Space plays the song, and Space Space again stops it
keys <Space><Space>
pause 3.0
keys <Space><Space>
pause 1.5
EOF
