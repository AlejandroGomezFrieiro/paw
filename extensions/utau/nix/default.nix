# extensions/utau as a package: its Lua and its device, with the engine it
# sings with in `bin/`, where the extension looks for it first. What
# `paw.withExtensions (exts: [ exts.utau ])` puts in the program.
{ lib, runCommand, callPackage, openutau }:

let
  engine = callPackage ./engine.nix { inherit openutau; };
  # The extension as the program loads it: the engine's source and the
  # packaging stay behind.
  lua = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.difference ../. (lib.fileset.unions [ ../engine ../nix ]);
  };
in
runCommand "paw-extension-utau" {
  passthru = {
    extensionName = "utau";
    inherit engine;
  };
  meta = {
    description = "Singing for paw: vocal parts sung by OpenUtau's engines";
    license = lib.licenses.mit;
  };
} ''
  dir=$out/share/paw/extensions/utau
  mkdir -p $out/share/paw/extensions
  cp -r ${lua} $dir
  chmod -R u+w $dir
  mkdir -p $dir/bin
  ln -s ${engine}/bin/paw-utau-engine $dir/bin/paw-utau-engine
''
