# The pod image of paw (web/browserpod/README.md), from the flake:
#
#   nix build .#paw-pod       the image and the page files
#   nix build .#paw-pod-bin   paw for the pod alone
#
# BrowserPod's Rust pack is a pinned nightly with the target
# wasm32-browserpod-linux-musl, patched libc, rustix and linux-raw-sys, a
# clang wrapper and a musl sysroot. Its installer runs rustup online; here
# the nightly comes from its release files instead, each with its hash,
# and the pack goes beside it as the installer puts it. The crates come
# from web/browserpod/Cargo.lock (lock.sh), offline.
{ pkgs, craneLib, nativePaw, rev }:
let
  lib = pkgs.lib;
  version = "4.1.0";
  nightly = "2026-05-19";
  host = "x86_64-unknown-linux-gnu";
  component = name: sha256: pkgs.fetchurl {
    url = "https://static.rust-lang.org/dist/${nightly}/${name}-nightly-${host}.tar.xz";
    inherit sha256;
  };
  components = [
    (component "rustc" "18afjg7v4z94mzg24qhwxggcyppxzrjm8f8xwmzh8jqv5d0nvbdk")
    (component "cargo" "1q7cmzdaqrwk478grsd5vm11gxq6s2f3azlhlhbrvyjyknbnic60")
    (component "rust-std" "0m52h3bipcjrfbal9qiwp70zqh5l5v3z9jmih119kl3vavrjz5i9")
  ];

  # The pack, installed as its install.sh does: `pack/` with the wrappers,
  # `nightly/` with the compiler they run.
  pack = pkgs.stdenv.mkDerivation {
    pname = "browserpod-rust";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://rt.browserpod.io/${version}/rust/browserpod-rust-${version}.tar.gz";
      sha256 = "597d7c61687c0eb1d60f71c2ca8e2a15c68b98b0f3618333239cdfcf123c9f2d";
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.zlib pkgs.stdenv.cc.cc.lib ];
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    installPhase = ''
      [ "$(cat nightly-pin)" = "nightly-${nightly}" ]
      mkdir -p $out/nightly components
      for c in ${lib.concatStringsSep " " components}; do tar -xJf $c -C components; done
      for d in components/*; do bash $d/install.sh --prefix=$out/nightly --disable-ldconfig > /dev/null; done
      cp -R . $out/pack
      rm -rf $out/pack/install.sh $out/pack/components
      mkdir -p $out/pack/libexec
      ln -s $out/nightly/bin/rustc $out/pack/libexec/rustc
      ln -s $out/nightly/bin/cargo $out/pack/libexec/cargo
      ln -sfn $out/nightly/lib/rustlib/${host} $out/pack/lib/rustlib/${host}
      for pc in $out/pack/lib/native/pkgconfig/*.pc; do
        [ -e "$pc" ] && substituteInPlace "$pc" --replace-quiet @BP_PREFIX@ $out/pack
      done
    '';
  };

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../Cargo.toml ../../.cargo ../../crates ../../runtime ../../fuzz
      ./Cargo.lock ./sjlj.c ./build-paw.sh
    ];
  };

  # The crates of the pod's lock, as cargo downloads them. LuaJIT's build
  # writes its version file over the copied one: the flake's own build
  # does the same.
  vendor = craneLib.vendorCargoDeps {
    cargoLock = ./Cargo.lock;
    overrideVendorCargoPackage = p: drv:
      if p.name == "luajit-src" then drv.overrideAttrs { postInstall = "rm $out/luajit2/.relver"; } else drv;
  };

  # paw for the pod: crates/paw-tui's `paw`, a WebAssembly program.
  bin = pkgs.stdenv.mkDerivation {
    pname = "paw-pod-bin";
    version = "0.1.0";
    inherit src;
    nativeBuildInputs = [ pkgs.pkg-config ];
    dontConfigure = true;
    buildPhase = ''
      export HOME=$TMPDIR CARGO_HOME=$TMPDIR/cargo
      mkdir -p $CARGO_HOME
      cp ${vendor}/config.toml $CARGO_HOME/config.toml
      export BP_PACK=${pack}/pack BP_OFFLINE=1
      # 0 cores means all of them, which cargo's -j does not take.
      if [ "$NIX_BUILD_CORES" -gt 0 ]; then export BP_JOBS=$NIX_BUILD_CORES; fi
      export BP_CLANG=${pkgs.llvmPackages.clang-unwrapped}/bin/clang
      export BP_LLVM_AR=${pkgs.llvmPackages.bintools-unwrapped}/bin/llvm-ar
      bash web/browserpod/build-paw.sh . $out/bin/paw
    '';
    dontInstall = true;
    dontFixup = true;
  };

  # The image and the page files (make-image.sh).
  image = pkgs.runCommand "paw-pod-${bin.version}" {
    src = lib.fileset.toSource {
      root = ../..;
      fileset = lib.fileset.unions [
        ../../Cargo.toml ../../extensions ../../examples
        ./make-image.sh ./make-home.lua ./site
      ];
    };
    nativeBuildInputs = [ pkgs.e2fsprogs ];
    passthru = { inherit bin pack; };
  } ''
    bash $src/web/browserpod/make-image.sh $src ${nativePaw}/bin/paw ${bin}/bin/paw $out ${rev}
  '';
in
{ inherit pack bin image; }
