# The ARA SDK 2.3.0 (Celemony, Apache 2.0), as the parts of
# github.com/Celemony/ARA_SDK put side by side: ARA_API (the C interface),
# ARA_Library (the C++ helpers) and ARA_Examples (the test plug-in). The
# pinned commits are those of the SDK's tag releases/2.3.0. CLAP 1.1.9 is
# the version the SDK's own install script takes.
{ fetchFromGitHub, runCommand }:

let
  api = fetchFromGitHub {
    owner = "Celemony";
    repo = "ARA_API";
    rev = "65ec5c43b943a48cb5446f448a0492db6af8534b";
    hash = "sha256-oyKfVUMHB4GVqbZi8YblhgQfrfmVKQJ4LeffON793ns=";
  };
  library = fetchFromGitHub {
    owner = "Celemony";
    repo = "ARA_Library";
    rev = "d18a6a5e489816316be84a9de0eaf7307bc1abe4";
    hash = "sha256-+9Y8hnJKoEJIr/BRnZ8PhQPGjKBnwH3SlhtUZSGmP38=";
  };
  examples = fetchFromGitHub {
    owner = "Celemony";
    repo = "ARA_Examples";
    rev = "abd7c8aa5854591995e1fbf16f854c65b0998e8d";
    hash = "sha256-fDptJ6mtLk+zD19zRwvGUeVABzi++MKSTiJQNaLqZZ8=";
  };
  clap = fetchFromGitHub {
    owner = "free-audio";
    repo = "clap";
    rev = "1.1.9";
    hash = "sha256-z2P0U2NkDK1/5oDV35jn/pTXCcspuM1y2RgZyYVVO3w=";
  };
in
runCommand "ara-sdk-2.3.0" { passthru = { inherit clap; version = "2.3.0"; }; } ''
  mkdir -p $out
  ln -s ${api} $out/ARA_API
  ln -s ${library} $out/ARA_Library
  ln -s ${examples} $out/ARA_Examples
  ln -s ${clap} $out/clap
''
