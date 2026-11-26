{ lib, rustPlatform, fetchFromGitHub }:
rustPlatform.buildRustPackage {
  pname = "heavy";
  version = "0.1.3";
  src = fetchFromGitHub {
    owner = "mokevnin";
    repo = "heavy";
    rev = "fc31480379e77abf99a033df23a3a9472042f5f6";
    hash = "sha256-jziZBefVeczbzlLNMWd5OmphicnPfFYmKhFizvhKJ4M=";
  };
  cargoHash = "sha256-SMRf955Ayeoo04o0tvzhGPo9vhk7SHvtuaxdC2paC7M=";
  meta = {
    description = "A machine-wide counting semaphore for heavy commands";
    homepage = "https://github.com/mokevnin/heavy";
    license = lib.licenses.asl20;
    mainProgram = "heavy";
  };
}
