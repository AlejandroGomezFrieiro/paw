#!/bin/sh
# Run the quarantined Rust tests and report them: part of the tier before a
# push. A quarantined Rust test is `#[ignore = "quarantine: <the fix>"]`, with
# a line in tests/quarantine.txt: its binary id and name as nextest prints
# them (`paw-core::it model::a_test`), a tab, and the fix. tools/testlint.lua
# checks that the two agree. The Lua runner reads the Lua lines itself.
#
#   tests/tools/quarantine.sh
#
# It prints each result, and exits 0 whatever the results are: a quarantined
# test does not fail the tier. A test that passes is a sign that its fix is
# merged, and its line and its ignore can go.
cd "$(dirname "$0")/../.." || exit 1
filter=""
names=""
while IFS="$(printf '\t')" read -r name fix; do
  case "$name" in
    paw*" "*" "*) ;; # a Lua test: a sentence
    paw*" "*)
      binary=${name%% *}
      test=${name#* }
      part="(binary_id(=$binary) & test(=$test))"
      filter="${filter:+$filter | }$part"
      names="$names
  $name (waits for: $fix)"
      ;;
  esac
done < tests/quarantine.txt
if [ -z "$filter" ]; then
  echo "quarantine: no Rust test is in tests/quarantine.txt"
  exit 0
fi
echo "quarantine: the Rust tests in tests/quarantine.txt:$names"
cargo nextest run --workspace --profile gate --run-ignored only --no-fail-fast -E "$filter"
echo "quarantine: the results above do not fail the tier; remove the line and the ignore of a test whose fix is merged"
exit 0
