# The Teal tools of the dev shell that nixpkgs does not have, or has old or
# with a fault. Each one runs on the Teal of nixpkgs (0.24.8, the version
# runtime/lua/tl.lua is) and on LuaJIT, like paw's own code.
#
#   cyan                  `cyan check` type-checks every Teal file in one
#                         process (tools/tlcheck.sh)
#   teal-language-server  completion, hover and errors in an editor
#   cerulean              the formatter of Teal files (`ceru`)
#
# docs/explanation/about-teal.md tells what each one is for in paw.
{ lib, stdenvNoCC, fetchFromGitHub, luajit, luajitPackages, makeBinaryWrapper }:
{
  # cyan 0.4.1 stops reporting after the first file with an error (`ok = ok
  # and report(...)` does not call `report` once `ok` is false): the exit
  # status is right, but the errors of the other files are not printed.
  # Report every file, then combine.
  cyan = luajitPackages.cyan.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      for f in $out/share/lua/5.1/cyan/tlcommon.lua $out/share/lua/5.1/cyan/tlcommon.tl; do
        substituteInPlace "$f" --replace-fail \
          'ok = ok and common.report_result(res, cfg)' \
          'ok = common.report_result(res, cfg) and ok'
      done
    '';
  });

  # nixpkgs has teal-language-server 0.1.3, which neither hovers nor
  # reports errors on paw's files; 0.3.0 does, with the same Teal.
  teal-language-server = luajitPackages.teal-language-server.overrideAttrs (old: rec {
    version = "0.3.0-1";
    src = fetchFromGitHub {
      owner = "teal-language";
      repo = "teal-language-server";
      rev = "0.3.0";
      hash = "sha256-xv15ljjXQuopZxuLItIQ1g5jVrcu+4lrxbmn9aa3qJk=";
    };
    knownRockspec = "${src}/teal-language-server-${version}.rockspec";
    # nixpkgs loosens the pins of 0.1.3 here; 0.3.0 pins the versions that
    # nixpkgs has (tl 0.24.8, luv 1.52.1, ltreesitter 0.3.0).
    postConfigure = "";
  });

  # Not in nixpkgs. Its release on LuaRocks is Lua that Teal wrote for Lua
  # 5.4; this compiles the tagged Teal source for LuaJIT instead.
  cerulean =
    let lua = luajit.withPackages (ps: with ps; [ tl luafilesystem compat53 ]);
    in stdenvNoCC.mkDerivation rec {
      pname = "cerulean";
      version = "1.9.2";
      src = fetchFromGitHub {
        owner = "efredriksson";
        repo = "cerulean";
        rev = "v${version}";
        hash = "sha256-8U4z3lUMP08txWHDST63v1YJOFDxUWmRKO9YuBFgX5I=";
      };
      # The release sets its version when it makes the rock; do it here.
      postPatch = ''
        substituteInPlace src/cerulean/cli.tl --replace-fail 'local version = "dev"' 'local version = "${version}"'
      '';
      nativeBuildInputs = [ lua makeBinaryWrapper ];
      buildPhase = ''
        runHook preBuild
        mkdir -p $out/share/lua/5.1/cerulean
        cd src
        for f in cerulean/*.tl; do
          case "$f" in *.d.tl) continue ;; esac
          tl gen -I . --gen-target=5.1 "$f" -o "$out/share/lua/5.1/''${f%.tl}.lua"
        done
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/libexec
        echo 'require("cerulean")' > $out/libexec/ceru.lua
        makeWrapper ${lua}/bin/luajit $out/bin/ceru \
          --add-flags $out/libexec/ceru.lua \
          --prefix LUA_PATH ';' "$out/share/lua/5.1/?.lua;$out/share/lua/5.1/?/init.lua"
        runHook postInstall
      '';
      meta = {
        description = "A formatter for Teal";
        homepage = "https://github.com/efredriksson/cerulean";
        license = lib.licenses.mit;
        mainProgram = "ceru";
      };
    };
}
