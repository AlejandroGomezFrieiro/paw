# About the Nix build

<!-- tags: crane nix-build -->

The flake uses [crane](https://github.com/ipetkov/crane) to build paw in
two layers, so a change to paw does not compile all of its dependencies
again. paw has more than five hundred Rust dependencies, LuaJIT among them,
and a build that compiles all of them for each change is slow.

## Two layers

The first layer is the dependencies. crane compiles every crate that the
workspace depends on one time, into a derivation of its own
(`.#default.deps`), and the derivation changes only when `Cargo.toml`,
`Cargo.lock` or `.cargo` change.

The second layer is paw's own crates. The programs and each check start
from the first layer and compile only paw's crates, so a change to a crate
or to the Lua runtime compiles only those few crates again.

The extensions, the examples and the configuration are not part of the Rust
build, and the package copies them next to the programs. A change to an
extension copies files and compiles nothing.

## Why crane

crane gives the two layers and the checks (clippy, rustfmt, nextest) with
little work. The dependencies have no git sources, so nobody needs to write
a hash by hand. Two other tools can build a Rust workspace with Nix, and
each one has a cost that crane does not have:

- crate2nix makes a derivation for each crate, so its cache is finer. But it
  needs a generated file that agrees with `Cargo.lock`, and an override for
  each crate with a build script, e.g., LuaJIT, bindgen and the scripts
  that write library paths into the programs.
- naersk makes the same two layers as crane and needs less upkeep, but it
  has no checks.

## Why the tests do not run in the build

The Lua suite and the tests of the graphical window need an X server,
plugins and folders of their own, and a build sandbox has none of them.
`nix flake check` therefore runs only the Rust tests that need none of
them, and the full tests run in the dev shell.

## See also

- [The Nix package](../reference/nix-package.md).
- [How to install paw with Nix](../how-to/install-paw.md).
