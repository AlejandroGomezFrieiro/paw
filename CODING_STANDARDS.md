# Standards of code for review

The reviewer of a change reads this file, together with the diff and the
ticket. It holds the rules that need judgment. A rule that a tool can
check is a check, not a line here: the hook `.githooks/pre-commit`,
`tools/guard-hook.py`, clippy, the lints of `tools/` and `nix flake
check` hold those rules. The skills give the full rules. The list below
names what a review looks for first.

## Rust (skill `rust-skills`)

- A value has a type. A function that only gives a constant, a flag
  that selects a behavior, or a string that names a method is a smell.
  The fix is a type with `Default`, an `enum`, or a trait.
- A struct with many fields that change for different reasons is two or
  more structs. A function that does many steps in a row is a struct
  with methods, or a sequence of named steps.
- One helper has one home. A second copy of a helper (a dB conversion, a
  table of pitch names, a reader of bytes) is a defect, even when the
  two copies agree today.
- The audio thread takes no lock, makes no allocation and does not wait.
  Look at each new call that a `process` function makes.
- A crate that `paw-crates.md` names does the job of hand-written code.
- A fix removes the class of the defect, not only the case that the
  report names. A range check after a cast that saturates keeps the
  cast: the fix is a checked conversion (`try_from`, `checked_*`) at the
  place where the value enters.

## Teal and Lua (skill `teal`)

- No `any` where a value has a shape.
- A module reads only the layers below it. A view does not read the
  private type of another view.

## Tests (skills `lua-testing`, `rust-testing`, `prune-tests`)

- Each new test guards one behavior that a user or a caller relies on,
  and fails only when that behavior breaks.
- A fix of the user experience has a test that uses the real keys.
- A test waits for a state or an event. It does not check a time.

## Comments and text (skills `paw-code` part 5, `plain-writing`)

- Code has no comments, only doc comments (skill `no-comments`). A doc
  comment gives the contract or the reason, in STE, not what the name says.
- A user page, a README and an API doc comment follow `plain-writing`.
  The other text follows STE.
- A change of behavior changes each page that tells about it.

## Design (skill `architecture`)

- A change of a contract (a trait, a saved type, a file format, a
  `paw.*` function, a protocol message, a layer) has its ADR, and the
  architecture documentation tells about it.
- A feature that not all users need is an extension. A change of the
  core for an extension is generic.
