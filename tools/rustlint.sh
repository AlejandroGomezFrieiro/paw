#!/bin/sh
# The checks of the Rust code that clippy does not do, cheap enough for each
# commit (.githooks/pre-commit) and part of `nix flake check` (check
# `rustlint`). The rules are ast-grep rules in tools/ast-grep/rules, each
# with examples in tools/ast-grep/tests:
#
# - constant-fn: no free function that gives a constant, such as a serde
#   default `fn one() -> f64 { 1.0 }`. A type with `Default` says the default.
# - serde-default-fn: no `#[serde(default = "name")]`.
# - one-value-helper: no free `is_zero`, `is_one`, `is_false` or `is_true`
#   helper. paw-core's `model::serde_util::is_default` does the job.
# - model-names-higher-layer: no module of paw-core's model names the
#   session, the sync, the API or the kernel.
#
# The lints of clippy (casts, unwrap, long functions) are in
# [workspace.lints.clippy] of Cargo.toml, and `cargo clippy -- -D warnings`
# checks them.
#
#   tools/rustlint.sh        check, and print each place at fault
cd "$(dirname "$0")/.." || exit 1
if ! command -v ast-grep > /dev/null; then
  echo "rustlint: no ast-grep outside the dev shell; the Rust pattern rules did not run" >&2
  exit 0
fi
ast-grep test --skip-snapshot-tests > /dev/null || exec ast-grep test --skip-snapshot-tests
ast-grep scan crates extensions
