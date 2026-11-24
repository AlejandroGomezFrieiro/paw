#!/bin/sh
# A vocal part for the demo song's melody: the part kind added, its
# singer chosen, the melody pasted in, lyrics typed in romaji and made kana
# for the Japanese voicebank, and the phonemes the engine made of them.
. "$MAKE/rig.sh"
. "$(dirname "$0")/engine.sh"
SETUP="$TUI_DEMO paw.ext.load('extensions/utau')"
rig_start
term_start
key j; pause 0.4
rec_start tui-utau
cap ":part.add vocal adds a vocal part, \\Vs its singer, :utau.phonemizer how words are sung"
pause 0.5; key colon; TYPE_DELAY=70 typ "part.add vocal"; key Return; pause 0.8
key backslash V s; pause 0.5; TYPE_DELAY=100 typ "kitane"; pause 0.3; key Return; pause 0.6
key colon; TYPE_DELAY=50 typ "utau.phonemizer japanesevcv"; key Return; pause 0.6
cap "The melody pasted onto it, and Enter opens the vocal editor"
keys 0.15 k w; TYPE_DELAY=120 typ "yic"; keys 0.15 j P; pause 0.4; key Return; pause 1.0
cap ":utau.lyrics gives the notes words; a batch edit makes them kana"
key colon; TYPE_DELAY=40 typ "utau.lyrics sa ku ra sa ku ra ya yo i no so ra"; key Return; pause 0.8
key colon; TYPE_DELAY=40 typ "utau.batch romaji_to_hiragana"; key Return; pause 2.6
rec_stop
rm -rf "$XDG_RUNTIME_DIR"
