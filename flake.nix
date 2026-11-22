{
  description = "paw, a personal audio workstation, with a small Rust kernel and everything else in Lua";

  inputs.nixpkgs.url = "nixpkgs";
  # What extensions/utau's engine is built against: the pinned OpenUtau
  # commit (see extensions/utau/engine/README.md).
  inputs.openutau = {
    url = "github:openutau/OpenUtau/bc194b6fe4897427a73066390b286e11205fd10f";
    flake = false;
  };
  # Builds the workspace in layers: every dependency once, in a derivation
  # of its own that the program and the checks reuse (docs/explanation/about-the-nix-build.md).
  inputs.crane.url = "github:ipetkov/crane";

  outputs = { self, nixpkgs, openutau, crane }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});

      # The graphical frontend loads its windowing libraries at run time.
      # `libglvnd` is libGL and libEGL, which the window draws with; they find
      # the system's driver themselves (on NixOS in /run/opengl-driver), which
      # must match the machine and so is not named here. `fontconfig` also
      # finds a font for Japanese and the like.
      guiLibs = pkgs: with pkgs; [
        wayland libxkbcommon fontconfig libx11 libxcursor libxi libxcb libglvnd
      ];
      # Plugins built elsewhere open the display's libraries by name when
      # they make a window, and name others as needed. Nothing is on the
      # loader's path on NixOS, so the build writes down where these are
      # (`crates/paw-plugins/src/libs.rs`).
      pluginLibs = pkgs: with pkgs; [
        libx11 libxext libxrender libxrandr libxinerama libxcursor libxcomposite
        libxfixes libxi libxcb libGL alsa-lib fontconfig freetype zlib curl
        stdenv.cc.cc.lib
      ];

      # The Rust workspace with crane, in layers. `deps` is every crate the
      # workspace depends on, compiled once (checked, built, and built for
      # the tests); it changes only with Cargo.toml, Cargo.lock or
      # `.cargo`. The program and every check start from it and compile
      # only the workspace's own crates.
      rust = pkgs:
        let
          lib = pkgs.lib;
          craneLib = crane.mkLib pkgs;
          # Only what cargo reads, so that a change to the manual, an
          # extension or an example does not rebuild the program. The
          # runtime's Lua is compiled into the binary (`include_dir!`).
          cargoFiles = lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./.cargo ./crates ./runtime ];
          src = lib.fileset.toSource { root = ./.; fileset = cargoFiles; };
          # The crates as cargo downloads them, each a store path, so every
          # file in them is read-only. LuaJIT's build copies its source tree
          # and then writes its version file over the copied one, which fails
          # on a read-only copy; the build writes that file itself, so the
          # tree goes without it.
          cargoVendorDir = craneLib.vendorCargoDeps {
            inherit src;
            overrideVendorCargoPackage = p: drv:
              if p.name == "luajit-src" then
                drv.overrideAttrs { postInstall = "rm $out/luajit2/.relver"; }
              else drv;
          };
          common = {
            inherit src cargoVendorDir;
            pname = "paw";
            version = "0.1.0";
            strictDeps = true;
            nativeBuildInputs = with pkgs; [ pkg-config rustPlatform.bindgenHook ];
            buildInputs = with pkgs; [ alsa-lib pipewire lilv lv2 serd sord sratom fontconfig ];
            # `.cargo/config.toml` sets this for LuaJIT; saying it here as
            # well makes it hold however cargo is set up in the build,
            # because without it `paw.limit` cannot stop a compiled loop.
            # LuaJIT is a dependency, so `deps` must have it too.
            TARGET_CFLAGS = "-DLUAJIT_ENABLE_CHECKHOOK";
            # Frame pointers, as nixpkgs' own Rust builds have them (for
            # profilers; they also make the unwinding tables smaller). And
            # the binaries name the source file of every place that can
            # panic: the crates' long store paths are shortened.
            RUSTFLAGS = "-Cforce-frame-pointers=yes --remap-path-prefix=${cargoVendorDir}/${builtins.hashString "sha256" "registry+https://github.com/rust-lang/crates.io-index"}=/cargo-vendor";
            # bindgen's flags carry a seed made from the derivation's own
            # output path, and the build scripts that run bindgen rerun
            # when the flags change: without this every derivation would
            # build PipeWire's bindings, and all that uses them, again.
            preBuild = ''
              export BINDGEN_EXTRA_CLANG_ARGS="$(echo "$BINDGEN_EXTRA_CLANG_ARGS" | sed 's/-frandom-seed=[^ ]*//g')"
            '';
          };
          deps = craneLib.buildDepsOnly common;
          withDeps = common // { cargoArtifacts = deps; };
        in {
          inherit deps;
          # `paw` (the terminal, `--headless`, `ctl`), `paw-gui` and
          # `paw-mcp`, as cargo builds them.
          programs = craneLib.buildPackage (withDeps // {
            pname = "paw-programs";
            nativeBuildInputs = withDeps.nativeBuildInputs ++ [ pkgs.patchelf ];
            # The window's build script writes where its libraries are into
            # the binary, so that it runs from any shell; so does the plugin
            # host.
            PAW_GUI_LIBS = lib.makeLibraryPath (guiLibs pkgs);
            PAW_PLUGIN_LIB_DIRS = lib.makeLibraryPath (pluginLibs pkgs);
            # The tests are the checks (`nix flake check`) and the dev shell's.
            doCheck = false;
            # The fixup phase trims the binaries' library paths to what they
            # are linked against, which drops the window's: it opens those by
            # name. They are put back here, after it.
            postFixup = ''
              patchelf --add-rpath ${lib.makeLibraryPath (guiLibs pkgs)} $out/bin/paw-gui
            '';
          });
          # What `nix flake check` runs, each from `deps`. The Lua suite and
          # the window's tests need a private X server, plugins and their own
          # directories, which a build sandbox has none of: they run in the
          # dev shell (`tests/tools/suite.sh`, `cargo test -p paw-gui`).
          # Nothing is built on top of a check, so none keeps its `target`.
          checks = {
            clippy = craneLib.cargoClippy (withDeps // {
              cargoClippyExtraArgs = "--all-targets";
              doInstallCargoArtifacts = false;
            });
            # The tree has never been run through rustfmt as a whole, and
            # doing it would collide with every branch in flight, so this
            # says how much it would change and does not fail. Once
            # `cargo fmt` has been run on all of it, the plain
            # `craneLib.cargoFmt` makes it a check that fails.
            fmt = craneLib.mkCargoDerivation {
              inherit src;
              pname = "paw";
              version = "0.1.0";
              pnameSuffix = "-fmt";
              cargoArtifacts = null;
              cargoVendorDir = null;
              nativeBuildInputs = [ pkgs.rustfmt ];
              buildPhaseCargoCommand = ''
                if ! cargo fmt --all -- --check > fmt.diff; then
                  echo "warning: rustfmt would change $(grep -c '^Diff in' fmt.diff) places (cargo fmt in the dev shell)"
                fi
              '';
              doInstallCargoArtifacts = false;
              installPhaseCommand = "mkdir -p $out";
            };
            # The Rust tests that need no display, audio device or Lua
            # suite: those of the libraries and the engine's own. Some read
            # the sound files in tests/fixtures, and paw-mcp's the manual.
            tests = craneLib.cargoNextest (withDeps // {
              src = lib.fileset.toSource {
                root = ./.;
                fileset = lib.fileset.unions [ cargoFiles ./tests/fixtures ./docs ];
              };
              cargoNextestExtraArgs = "--workspace -E 'not (package(paw-gui) | binary(suite) | binary(remote) | binary(safety))'";
              doInstallCargoArtifacts = false;
            });
          };
        };

      # The programs ready to run, with what they need beside them.
      paw = pkgs:
        let inherit (rust pkgs) programs deps;
        in pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "paw";
          version = "0.1.0";
          # The extensions, examples and configuration go in `share/paw`.
          # They are not in the Rust build's source, so a change to one of
          # them only remakes this, in a second.
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [ ./extensions ./examples ./config ./runtime ./tlconfig.lua ];
          };
          nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
          installPhase = ''
            mkdir -p $out/share/paw
            # runtime/ for the Teal declarations (runtime/types) and the
            # runtime's Teal modules they name; tlconfig.lua points at them.
            cp -r extensions examples config runtime tlconfig.lua $out/share/paw/
            # `PAW_HOME` is where `paw doctor` finds its script. ffmpeg is
            # there for MP3, Ogg and Opus export (no codec is linked into the
            # program); it goes last on the PATH, so that the user's own wins.
            # fc-list is how the window finds a font for Japanese and the like.
            # curl is how extensions/plugstate asks TONE3000's library.
            # The window starts the `paw` beside its binary, which is the
            # unwrapped one; it inherits these from the window's wrapper.
            for bin in paw paw-gui paw-mcp; do
              makeWrapper ${programs}/bin/$bin $out/bin/$bin \
                --set-default PAW_HOME $out/share/paw \
                --suffix PATH : ${pkgs.lib.makeBinPath [ pkgs.ffmpeg-headless pkgs.fontconfig.bin pkgs.curl ]}
            done
          '';
          # The extensions as packages, and the program with some of them:
          # `paw.withExtensions (exts: [ exts.utau ])`.
          passthru = {
            inherit programs deps;
            extensions = extensionsFor pkgs;
            withExtensions = pick: withExtensions pkgs finalAttrs.finalPackage (pick (extensionsFor pkgs));
          };
          meta = {
            description = "A hackable DAW with a small Rust kernel and everything else in Lua";
            license = with pkgs.lib.licenses; [ mit asl20 ];
            mainProgram = "paw";
            platforms = [ "x86_64-linux" "aarch64-linux" ];
          };
        });

      # Every extension as a package holding `share/paw/extensions/<name>`.
      # Most are Lua and nothing else; one with native parts (an engine to
      # build, a library) has a `nix/default.nix` of its own, given the
      # flake's inputs it asks for, and crane for a Rust workspace of its own.
      extensionsFor = pkgs:
        let
          lib = pkgs.lib;
          dirs = lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./extensions);
          plain = name: pkgs.runCommand "paw-extension-${name}" { passthru.extensionName = name; } ''
            mkdir -p $out/share/paw/extensions
            cp -r ${./extensions + "/${name}"} $out/share/paw/extensions/${name}
          '';
          inputs = { inherit openutau; craneLib = crane.mkLib pkgs; };
          own = name:
            let f = import (./extensions + "/${name}/nix");
            in pkgs.callPackage f (builtins.intersectAttrs (builtins.functionArgs f) inputs);
        in
        lib.mapAttrs (name: _:
          if builtins.pathExists (./extensions + "/${name}/nix/default.nix") then own name else plain name) dirs;

      # The program with extensions: each one is loaded at startup from its
      # package (`PAW_EXTENSIONS`), before the configuration, whatever the
      # configuration says.
      withExtensions = pkgs: base: exts: pkgs.symlinkJoin {
        name = "paw-with-${pkgs.lib.concatMapStringsSep "-" (e: e.extensionName) exts}";
        paths = [ base ] ++ exts;
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          for bin in paw paw-gui paw-mcp; do
            rm $out/bin/$bin
            makeWrapper ${base}/bin/$bin $out/bin/$bin \
              --prefix PAW_EXTENSIONS : ${pkgs.lib.concatMapStringsSep ":" (e: "${e}/share/paw/extensions/${e.extensionName}") exts}
          done
        '';
        passthru = { extensions = exts; };
        meta = base.meta // { mainProgram = "paw"; };
      };

      # One program of that build, by name.
      only = pkgs: name: pkgs.runCommand name { meta.mainProgram = name; } ''
        mkdir -p $out/bin
        ln -s ${paw pkgs}/bin/${name} $out/bin/${name}
      '';

      # paw that sings: the program with extensions/utau and its engine.
      # The style packages Vale checks the docs with (tools/vale.sh joins
      # them with the project's own in .vale/styles; see .vale.ini). AiTells
      # (patterns of machine-written prose) is not in nixpkgs: its release is
      # pinned here.
      valeStyles = pkgs: let
        packaged = pkgs.vale.withStyles (s: [ s.readability s.write-good s.alex ]);
        aitells = pkgs.fetchzip {
          url = "https://github.com/krishnasunkam/vale-ai-tells/releases/download/v1.0.0/AiTells.zip";
          sha256 = "12gm0fmg61wf0zp2bprbs68f16b0ca5s30k42fzp6xjxcnq9xm7w";
        };
      in pkgs.runCommand "paw-vale-styles" { } ''
        mkdir -p $out
        for d in ${packaged}/share/vale/styles/*; do ln -s "$d" $out/; done
        ln -s ${aitells} $out/AiTells
      '';

      # Vale on README.md and every page: a check that fails on an error
      # (warnings are reported, not failed on). bench/RESULTS.md is a dated log
      # of measurements, not a page to read as the manual: it is not checked.
      docsCheck = pkgs: pkgs.runCommand "paw-docs-vale" {
        src = nixpkgs.lib.fileset.toSource {
          root = ./.;
          fileset = nixpkgs.lib.fileset.unions ([ ./.vale.ini ./.vale ./README.md ./AGENTS.md ./docs ./extensions ./crates ./bench/README.md ./bench/DAWS.md ]);
        };
        nativeBuildInputs = [ pkgs.vale ];
      } ''
        mkdir styles
        for d in ${valeStyles pkgs}/* $src/.vale/styles/*; do ln -s "$d" styles/; done
        export VALE_STYLES_PATH=$PWD/styles
        cd $src
        vale --config .vale.ini --minAlertLevel=error README.md AGENTS.md docs crates/*/README.md extensions/*/README.md extensions/*/doc bench/README.md bench/DAWS.md
        touch $out
      '';

      # `cyan check` on every Teal file (tools/tlcheck.sh), with the Teal of
      # nixpkgs: the version runtime/lua/tl.lua is (0.24.8).
      tealCheck = pkgs: pkgs.runCommand "paw-teal-check" {
        src = nixpkgs.lib.fileset.toSource {
          root = ./.;
          fileset = nixpkgs.lib.fileset.unions [ ./runtime ./config ./extensions ./tlconfig.lua ./tools/tlcheck.sh ];
        };
        nativeBuildInputs = [ (luaTools pkgs).cyan ];
      } ''
        sh $src/tools/tlcheck.sh cyan
        touch $out
      '';

      # luacheck on every Lua file, with .luacheckrc: unused and undefined
      # names, values set and never read.
      luaCheck = pkgs: pkgs.runCommand "paw-luacheck" {
        src = nixpkgs.lib.fileset.toSource {
          root = ./.;
          fileset = nixpkgs.lib.fileset.unions [
            ./.luacheckrc
            (nixpkgs.lib.fileset.fileFilter (file: file.hasExt "lua") ./.)
          ];
        };
        nativeBuildInputs = [ pkgs.luajitPackages.luacheck ];
      } ''
        cd $src
        luacheck --no-cache --formatter plain --codes .
        touch $out
      '';

      # Every Lua and Teal file is formatted with StyLua and cerulean
      # (tools/fmtcheck.sh): the check fails on a file they would change.
      formatCheck = pkgs: pkgs.runCommand "paw-format" {
        src = nixpkgs.lib.fileset.toSource {
          root = ./.;
          fileset = nixpkgs.lib.fileset.unions [
            ./stylua.toml ./.styluaignore ./tools/fmtcheck.sh
            (nixpkgs.lib.fileset.fileFilter (file: file.hasExt "lua" || file.hasExt "tl") ./.)
          ];
        };
        nativeBuildInputs = [ pkgs.stylua (luaTools pkgs).cerulean ];
      } ''
        cd $src && sh tools/fmtcheck.sh
        touch $out
      '';

      pawUtau = pkgs: (paw pkgs).withExtensions (exts: [ exts.utau ]);

      # The Teal tools that nixpkgs has not, or has old or with a fault.
      luaTools = pkgs: pkgs.callPackage ./nix/lua-tools.nix { };
    in {
      packages = forAll (pkgs: {
        default = paw pkgs;
        paw = only pkgs "paw";
        paw-gui = only pkgs "paw-gui";
        paw-mcp = only pkgs "paw-mcp";
        paw-utau = pawUtau pkgs;
        utau-engine = (extensionsFor pkgs).utau.engine;
        # extensions/sampler's plugin and command, on their own.
        paw-sampler = (extensionsFor pkgs).sampler.engine;
        # extensions/ara's attachment, and the ARA SDK's test plug-in.
        paw-ara = (extensionsFor pkgs).ara.bridge;
        ara-test-plugin = (extensionsFor pkgs).ara.testPlugin;
      });

      # `nix flake check`: clippy, rustfmt, the Rust tests a sandbox can run,
      # the program itself, Vale on the docs, `cyan check` on the Teal,
      # luacheck on the Lua, and how much the formatters would change.
      checks = forAll (pkgs: (rust pkgs).checks // { paw = paw pkgs; docs = docsCheck pkgs; teal = tealCheck pkgs; lua = luaCheck pkgs; format = formatCheck pkgs; });

      apps = forAll (pkgs:
        nixpkgs.lib.genAttrs [ "paw" "paw-gui" "paw-mcp" ] (name: {
          type = "app";
          program = "${only pkgs name}/bin/${name}";
        }) // {
          default = { type = "app"; program = "${paw pkgs}/bin/paw"; };
          paw-utau = { type = "app"; program = "${pawUtau pkgs}/bin/paw"; };
        });

      # For a home-manager configuration:
      #   programs.paw = { enable = true; extensions = [ "utau" ]; };
      homeManagerModules.default = { config, lib, pkgs, ... }:
        let cfg = config.programs.paw;
        in {
          options.programs.paw = {
            enable = lib.mkEnableOption "paw, a personal audio workstation";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              description = "The program, without extensions.";
            };
            extensions = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "utau" ];
              description = "Extensions to build in and load at startup, with whatever they need (utau: OpenUtau and its engine).";
            };
          };
          config = lib.mkIf cfg.enable {
            home.packages = [
              (if cfg.extensions == [ ] then cfg.package
               else cfg.package.withExtensions (exts: map (name: exts.${name}) cfg.extensions))
            ];
          };
        };

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          # xmllint checks the DAWproject files of extensions/interop against the
          # format's XML schema.
          nativeBuildInputs = with pkgs; [ cargo rustc clippy rustfmt rust-analyzer pkg-config rustPlatform.bindgenHook ffmpeg-headless sccache cargo-sweep (lib.getBin libxml2) ];
          # Every git worktree has a `target/` of its own, and cargo shares
          # nothing between them: each one compiles the same four hundred
          # crates again. sccache keeps what rustc made in one place, shared
          # by every checkout, with a ceiling on its size; it only caches
          # builds that are not incremental. `cargo sweep -t 14` clears what
          # no build has used for two weeks (tools/sweep.sh does every tree).
          RUSTC_WRAPPER = "sccache";
          SCCACHE_CACHE_SIZE = "40G";
          CARGO_INCREMENTAL = "0";
          # What the window tests (`crates/paw-gui/tests/window.rs`) drive: a
          # private X server, a window manager, a pointer and key sender, and
          # tesseract to find words on a screenshot.
          # The Teal and Lua tools (docs/explanation/about-teal.md): `tl`
          # (the version of runtime/lua/tl.lua), `cyan` (tools/tlcheck.sh),
          # the language servers of both, the formatters (`ceru` for Teal,
          # `stylua` for Lua) and `luacheck`; nix/lua-tools.nix has those
          # that nixpkgs has not, or has old.
          packages = with pkgs; [ xvfb openbox xdotool imagemagick tesseract vale curl luajitPackages.tl ]
            ++ (with luaTools pkgs; [ cyan teal-language-server cerulean ])
            ++ [ pkgs.lua-language-server pkgs.stylua pkgs.luajitPackages.luacheck ];
          # The style packages Vale checks the docs with (tools/vale.sh joins
          # them with the project's own in .vale/styles; see .vale.ini).
          PAW_VALE_STYLES = "${valeStyles pkgs}";
          buildInputs = with pkgs; [ alsa-lib pipewire lilv lv2 serd sord sratom fontconfig ];
          # The graphical frontend's libraries are on the path here;
          # `PAW_GUI_LIBS` is where its build script finds them, to write
          # into the binary, so that the binary also runs from a shell that
          # is not this one.
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (guiLibs pkgs);
          PAW_GUI_LIBS = pkgs.lib.makeLibraryPath (guiLibs pkgs);
          PAW_PLUGIN_LIB_DIRS = pkgs.lib.makeLibraryPath (pluginLibs pkgs);
          # Plugins in all three formats for the test suite to host.
          PAW_TEST_PLUGINS = "${pkgs.lsp-plugins}/lib:${pkgs.surge-xt}/lib:${pkgs.neural-amp-modeler-lv2}/lib:${pkgs.sfizz-ui}/lib";
          # Sample amp models for Neural Amp Modeler, from its sources
          # (extensions/plugstate's tests load them).
          PAW_TEST_NAM_MODELS = "${pkgs.neural-amp-modeler-lv2.src}/models";
          # The ARA SDK's test plug-in and extensions/ara's attachment, which
          # extensions/ara/tests.lua host.
          PAW_TEST_ARA = "${(extensionsFor pkgs).ara.testPlugin}";
          PAW_ARA_BRIDGE = "${(extensionsFor pkgs).ara.bridge}/lib/paw-ara.so";
        };
        # `nix develop .#profile`: the default shell and the profilers that
        # bench/profile uses (bench/profile.md). perf samples the program's
        # own processes without root when perf_event_paranoid is 2 or less.
        profile = self.devShells.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ (with pkgs; [
            perf samply inferno heaptrack valgrind hyperfine
          ]);
        });
      });
    };
}
