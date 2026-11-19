# paw-ara: the host side of ARA as an attachment for paw
# (lib/paw-ara.so), built from extensions/ara/native/bridge.cpp against
# the ARA SDK's C interface and paw's attachment header.
{ lib, stdenv, callPackage, nlohmann_json }:

let
  sdk = callPackage ./sdk.nix { };
in
stdenv.mkDerivation {
  pname = "paw-ara";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../../..;
    fileset = lib.fileset.unions [
      ../native/bridge.cpp
      ../../../crates/paw-plugins/include/paw_attach.h
    ];
  };
  buildInputs = [ nlohmann_json ];
  buildPhase = ''
    runHook preBuild
    $CXX -std=c++17 -O2 -fPIC -shared -fvisibility=hidden -Wall -Wno-unused-parameter \
      -I${sdk} -I${sdk.clap}/include -Icrates/paw-plugins/include \
      extensions/ara/native/bridge.cpp -o paw-ara.so
    runHook postBuild
  '';
  installPhase = ''
    mkdir -p $out/lib
    cp paw-ara.so $out/lib/
  '';
  passthru = { inherit sdk; };
  meta = {
    description = "The host side of ARA 2 for paw, as an attachment";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
  };
}
