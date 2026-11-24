#!/bin/sh
# The sampler's instrument picker auditioning: a sampler part added to the
# demo song, the library listed, each instrument loaded and played as the
# selection rests on it, one kept, and :sampler.info.
#
# Needs the plugin: `nix build .#paw-sampler -o target/paw-sampler` (or
# SAMPLER pointing at such a build). The library is made from the plugin's
# own test sounds (sines), under names that read as a library would, in a
# directory of its own in /tmp, so that the path the picker shows is short.
. "$MAKE/rig.sh"
SAMPLER=${SAMPLER:-$ROOT/target/paw-sampler}
if [ ! -x "$SAMPLER/bin/paw-sampler" ]; then
  echo "tui-sampler: skipped: needs the plugin (nix build .#paw-sampler -o target/paw-sampler)"
  exit 0
fi
TOP=$(mktemp -d)
LIB=$TOP/instruments
"$SAMPLER/bin/paw-sampler" fixtures "$LIB/fx" >/dev/null || exit 1
mkdir -p "$LIB/Strings" "$LIB/Keys" "$LIB/Pads" "$LIB/Plucks"
cp "$LIB/fx/ks.sfz" "$LIB/Strings/Violins KS.sfz"
cp "$LIB/fx/ks.dspreset" "$LIB/Strings/Cellos.dspreset"
cp "$LIB/fx/vel.sfz" "$LIB/Keys/Soft Piano.sfz"
cp "$LIB/fx/loop.sfz" "$LIB/Pads/Glass Pad.sfz"
cp "$LIB/fx/rr.sfz" "$LIB/Plucks/Harp RR.sfz"
cp "$LIB/fx/release.sfz" "$LIB/Plucks/Nylon Guitar.sfz"
# The samples are next to the copies, as the instruments name them.
for d in Strings Keys Pads Plucks; do cp "$LIB"/fx/*.wav "$LIB/$d/"; done
rm -rf "$LIB/fx"
PLUGINS=1
CLAP_PATH=$SAMPLER/lib/clap LV2_PATH=$D/none VST3_PATH=$D/none
export CLAP_PATH LV2_PATH VST3_PATH
SETUP="$TUI_DEMO paw.ext.load('extensions/sampler')
paw.opt.sampler_plugin_dir = '$SAMPLER/lib/clap' paw.opt.sampler_libraries = '$LIB'"
rig_start
term_start
key G k; pause 0.4
rec_start tui-sampler
cap ":part.add sampler adds a sampler part and opens its instrument picker"
pause 0.5; key colon; TYPE_DELAY=90 typ "part.add sampler"; key Return; pause 1.6
cap "Each instrument is loaded and plays a phrase as the selection rests on it"
keys 1.6 ctrl+n ctrl+n ctrl+n
cap "Typing narrows the list; Enter keeps the instrument, as one undo step"
TYPE_DELAY=180 typ "viol"; pause 1.8; key Return; pause 1.0
cap ":sampler.info says what it plays: its range and articulations"
key colon; TYPE_DELAY=90 typ "sampler.info"; key Return; pause 2.0
rec_stop
rm -rf "$TOP"
