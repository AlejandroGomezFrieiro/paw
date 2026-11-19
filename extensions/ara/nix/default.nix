# extensions/ara as a package: its Lua, with the attachment it loads
# (lib/paw-ara.so) beside it, where the extension looks for it first.
# What `paw.withExtensions (exts: [ exts.ara ])` puts in the program.
# The SDK's test plug-in, which the tests host, is `passthru.testPlugin`.
{ lib, runCommand, callPackage }:

let
  bridge = callPackage ./bridge.nix { };
  testPlugin = callPackage ./test-plugin.nix { };
  # The extension as the program loads it: the bridge's source and the
  # packaging stay behind.
  lua = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.difference ../. (lib.fileset.unions [ ../native ../nix ]);
  };
in
runCommand "paw-extension-ara" {
  passthru = {
    extensionName = "ara";
    inherit bridge testPlugin;
  };
  meta = {
    description = "ARA plugins in paw: plugins that read whole clips";
    license = with lib.licenses; [ mit asl20 ];
  };
} ''
  dir=$out/share/paw/extensions/ara
  mkdir -p $out/share/paw/extensions
  cp -r ${lua} $dir
  chmod -R u+w $dir
  mkdir -p $dir/lib
  ln -s ${bridge}/lib/paw-ara.so $dir/lib/paw-ara.so
''
