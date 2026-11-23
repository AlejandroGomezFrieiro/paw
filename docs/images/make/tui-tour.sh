#!/bin/sh
# The tour: the README's first picture. One pass over the core of paw, in
# chapters: move, select and act, regions, find, add a track and a device,
# the piano roll, groups and subprojects, play. Each chapter starts with a
# caption that names its keys. The last chapter undoes every change and
# puts the cursor back, so the GIF loops without a jump.
#
# CHANGES is the count of undo steps that the scene makes. If you add or
# remove an edit, change CHANGES, or the end does not match the start.
# The track numbers (4G) are for the rows at that point of the scene.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO local bar = paw.time.bar_start
paw.markers.add(bar(1), 'Verse', { length = bar(5) - bar(1) })
paw.markers.add(bar(5), 'Chorus', { length = bar(9) - bar(5) })
paw.cursor.set_track(paw.tracks()[1]) paw.flush()"
CHANGES=7
rig_start
term_start
rec_start tui-tour

cap "Move: j k over tracks, w b e over clips, G gg to the last and first track"
pause 2.0; keys 0.35 j j w w e b; key G; pause 0.5; key g g; pause 0.8
cap "]r jumps to the next region, [r back, 0 to the start of the song"
keys 0.6 bracketright r bracketleft r 0; pause 0.6

# Edits 1 and 2: a paste, two faders.
cap "Select and copy: vic selects the melody, y copies it, P pastes it"
keys 0.3 j j j w; keys 0.3 v i c; pause 0.5; key y; pause 0.5; key 0; pause 0.3; key P; pause 1.1
cap "V selects whole tracks: Vk and 3- turn two tracks down 3 dB"
keys 0.4 V k; pause 0.3; TYPE_DELAY=120 typ "3"; key minus; pause 1.4

cap "Regions: znar narrows to the region, its bars count from 1; zw widens"
keys 0.3 z n a r; pause 2.0; keys 0.3 z w; pause 1.0

cap "Find: / jumps to a clip by name"
key slash; TYPE_DELAY=110 typ "phrase"; pause 0.4; key Return; pause 1.1
cap "Space fc lists every clip and draws the one selected"
key space f c; pause 0.6; TYPE_DELAY=130 typ "fill"; pause 1.6; key Return; pause 0.6

# Edits 3 and 4: a track and its synth.
cap "Add: o adds a track, a adds a device from a picker"
key G; key o; pause 0.8; key a; pause 0.6; TYPE_DELAY=130 typ "synth"; pause 1.1; key Return; pause 1.2

# Edit 5: the note drawn. The block moved up is undone in the chapter.
cap "Piano roll: Enter opens the clip; i draws a note, 8l makes it longer"
TYPE_DELAY=150 typ "4G5|"; pause 0.3; key Return; pause 1.1
keys 0.25 W W W; key i; keys 0.25 8 l; pause 0.4; key Escape; pause 0.8
cap "Ctrl-v selects a block of notes, 3 Ctrl-a transposes it, u undoes"
keys 0.25 b ctrl+v; keys 0.25 B k k k; pause 0.4; TYPE_DELAY=120 typ "3"; key ctrl+a; pause 1.2
key u; pause 0.8
cap "Ctrl-w c closes the piano roll"
key ctrl+w c; pause 0.9

# Edits 6 and 7: the group, and the subproject.
cap "Groups: Vj Space tg makes a group, znn enters it, zw comes back"
keys 0.3 g g V j; key space t g; pause 0.6; TYPE_DELAY=110 typ "Rhythm"; key Return; pause 0.9
keys 0.3 z n n; pause 1.5; keys 0.3 z w; pause 0.8
cap "Subprojects: Ctrl-v a block, zn, and :scope.write! makes it a subproject"
TYPE_DELAY=150 typ "4G5|"; key ctrl+v; keys 0.3 j dollar; pause 0.5; keys 0.3 z n; pause 0.9
key colon; TYPE_DELAY=70 typ "scope.write! Hook"; pause 0.5; key Return; pause 1.8
cap "zw goes back to the song; za on the Hook row shows its tracks"
keys 0.3 z w; pause 0.8; TYPE_DELAY=150 typ "4G"; key z a; pause 2.0; key z a; pause 0.6

cap "Space Space plays the song"
key space space; pause 2.8; key space space; pause 0.4
cap "${CHANGES}u undoes the tour's ${CHANGES} changes, and the tour starts again"
TYPE_DELAY=150 typ "$CHANGES"; key u; pause 1.2; keys 0.2 g s g g 0; pause 1.6
rec_stop
