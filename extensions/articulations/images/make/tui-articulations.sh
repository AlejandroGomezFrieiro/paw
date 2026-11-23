#!/bin/sh
# The melody under the example violin map: every note tagged sustain, one
# made staccato from the \a popover (each articulation heard as the
# highlight rests on it), three made pizzicato in visual mode, and K.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.ext.load('extensions/articulations')
require('articulations').bind(paw.parts()[4].id, 'extensions/articulations/articulations/examples/violin-section.art.toml')"
rig_start
term_start
key j w Return; pause 1.0
rec_start tui-articulations
cap "A map binds the lead to a violin section: :%art sus tags every note"
pause 0.5; key colon; TYPE_DELAY=110 typ "%art sus"; key Return; pause 1.2
cap "\\a lists the articulations, each heard on the note as the highlight rests"
key backslash a; pause 1.0; keys 0.8 Down Down; pause 0.4; key Return; pause 1.0
cap "In visual mode \\a tags the selection: three notes pizzicato"
key w v w w; pause 0.4; key backslash a; pause 0.6; TYPE_DELAY=200 typ "pz"; pause 0.5; key Return; pause 1.0
cap "K says what a note plays and how the instrument is told"
key K; pause 2.2; key Escape; pause 1.2
rec_stop
