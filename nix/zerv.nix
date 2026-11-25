{ lib, stdenvNoCC, fetchurl, makeWrapper, gitMinimal }:
let
  target = {
    x86_64-linux = {
      arch = "x86_64";
      hash = "sha256-cOwjyFFxKSgZZNwytDQFxpMddrIP/QZcNXrn9CME+0g=";
    };
    aarch64-linux = {
      arch = "aarch64";
      hash = "sha256-66/dUysogpNsXMM87b8yPMmsSBk6VzGNoSaMfuBzuDM=";
    };
  }.${stdenvNoCC.hostPlatform.system};
in stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "zerv";
  version = "0.8.42";
  src = fetchurl {
    url = "https://github.com/wislertt/zerv/releases/download/v${finalAttrs.version}/zerv-${target.arch}-unknown-linux-musl";
    inherit (target) hash;
  };
  nativeBuildInputs = [ makeWrapper ];
  dontUnpack = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/zerv"
    wrapProgram "$out/bin/zerv" --prefix PATH : "${lib.makeBinPath [ gitMinimal ]}"
    runHook postInstall
  '';
  meta = {
    description = "Derive build versions from Git tags and commits";
    homepage = "https://github.com/wislertt/zerv";
    license = lib.licenses.asl20;
    mainProgram = "zerv";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
})
