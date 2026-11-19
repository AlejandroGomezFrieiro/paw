# ARATestPlugIn from the ARA SDK's examples, as a CLAP plug-in
# (lib/clap/ARATestPlugIn.clap): a pass-through ARA playback renderer with
# a fake note analysis, persistence and API validation. The tests of
# extensions/ara host it. Built by hand, not with the examples' CMake,
# which installs the plug-in into the home folder when it builds.
{ lib, stdenv, callPackage }:

let
  sdk = callPackage ./sdk.nix { };
in
stdenv.mkDerivation {
  pname = "ara-test-plugin";
  version = sdk.version;
  dontUnpack = true;
  buildPhase = ''
    runHook preBuild
    ex=${sdk}/ARA_Examples
    flags="-O2 -fPIC -fvisibility=hidden -I${sdk} -I$ex -I$ex/TestPlugIn -I${sdk.clap}/include
      -DARA_MAJOR_VERSION=2 -DARA_MINOR_VERSION=3 -DARA_PATCH_VERSION=0 -DARA_BUILD_VERSION=1
      -DNDEBUG -DARA_VALIDATE_API_CALLS=1 -DARA_ENABLE_INTERNAL_ASSERTS=1 -DARA_ENABLE_DEBUG_OUTPUT=1
      -DARA_TARGET_NAME=\"ARATestPlugInCLAP\" -DARA_TARGET_TYPE_MODULE_LIBRARY"
    objs=""
    for src in \
        ${sdk}/ARA_Library/Debug/ARADebug.c \
        $ex/ExamplesCommon/SignalProcessing/PulsedSineSignal.c; do
      o=$(basename $src).o
      $CC -std=c11 $flags -c $src -o $o
      objs="$objs $o"
    done
    for src in \
        ${sdk}/ARA_Library/Utilities/ARAChannelFormat.cpp \
        ${sdk}/ARA_Library/Utilities/ARAPitchInterpretation.cpp \
        ${sdk}/ARA_Library/Dispatch/ARAPlugInDispatch.cpp \
        ${sdk}/ARA_Library/PlugIn/ARAPlug.cpp \
        $ex/TestPlugIn/ARATestAudioSource.cpp \
        $ex/TestPlugIn/ARATestDocumentController.cpp \
        $ex/TestPlugIn/ARATestPlaybackRenderer.cpp \
        $ex/TestPlugIn/TestAnalysis.cpp \
        $ex/TestPlugIn/TestPersistency.cpp \
        $ex/TestPlugIn/CLAP/TestCLAPPlugIn.cpp; do
      o=$(basename $src).o
      $CXX -std=c++20 -Wno-unused-parameter $flags -c $src -o $o
      objs="$objs $o"
    done
    $CXX -shared -o ARATestPlugIn.clap $objs -lpthread -latomic
    runHook postBuild
  '';
  installPhase = ''
    mkdir -p $out/lib/clap
    cp ARATestPlugIn.clap $out/lib/clap/
  '';
  passthru = { inherit sdk; };
  meta = {
    description = "The ARA SDK's test plug-in, as CLAP";
    homepage = "https://github.com/Celemony/ARA_Examples";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
