#!/bin/sh
# The end-to-end scenarios: a user who works on a project day after day.
#
# DO NOT RUN THIS unless the owner or the release check asks for it. It is
# for CI (the short mode on pull requests, the full mode each night) and for
# the main checkout before a tagged release, not for agents that test a
# change: use tests/tools/suite.sh for that. tests/tools/suite.sh and the
# default `nix flake check` do not run it.
#
#   tests/tools/e2e.sh                     every scenario, every day, seed 1
#   tests/tools/e2e.sh --short             the short mode: the first days of each
#   tests/tools/e2e.sh song --seed 7       one scenario, another seed
#   tests/tools/e2e.sh song --days 3       days 1 to 3 only
#   tests/tools/e2e.sh song --approve      approve the renders of this seed as golden
#
# Each day is a new paw process on the project that the day before saved.
# The work of a run is in target/e2e/<scenario>-seed<N> (the project, a copy
# of it after each day in days/, and the project of a failed day). A failure
# prints the scenario, the seed, the day, the step and the command that
# repeats it. See docs/explanation/about-the-e2e-tests.md.
. "$(dirname "$0")/env.sh"
cd "$ROOT" || exit 1
export HOME=$SCRATCH/e2e-home CLAP_PATH= VST3_PATH= LV2_PATH=
mkdir -p "$HOME"

ALL="song interop"
scenarios= seed=1 days= approve= short=
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) seed=$2; shift ;;
    --days) days=$2; shift ;;
    --short) short=1 ;;
    --approve) approve=approve ;;
    -*) echo "e2e.sh: unknown option $1" >&2; exit 2 ;;
    *) scenarios="$scenarios $1" ;;
  esac
  shift
done
[ -n "$scenarios" ] || scenarios=$ALL

started=$(date +%s)
failed=0
for scenario in $scenarios; do
  [ -f "tests/e2e/scenarios/$scenario.lua" ] || { echo "e2e.sh: no scenario $scenario" >&2; exit 2; }
  # How many days the scenario has, and how many the short mode runs.
  total=$(grep -c '^days\[[0-9]*\] = function' "tests/e2e/scenarios/$scenario.lua")
  quick=$(sed -n 's/^-- short: \([0-9]*\)$/\1/p' "tests/e2e/scenarios/$scenario.lua")
  n=${days:-$total}
  [ -n "$short" ] && [ -z "$days" ] && n=${quick:-2}
  work=$ROOT/target/e2e/$scenario-seed$seed
  rm -rf "$work"
  mkdir -p "$work/days" "$work/library"
  cp tests/e2e/assets/*.mid tests/e2e/assets/*.wav "$work/library/"
  day=1
  while [ "$day" -le "$n" ]; do
    project=
    [ "$day" -gt 1 ] && project=$work/project
    # A day that hangs is a failure too: the limit is far above a day's time.
    timeout 900 "$BIN/paw" --clean --no-plugins --audio null --no-listen $project \
      -l tests/e2e/run.lua "$scenario" "$day" "$seed" "$work" $approve > "$work/day$day.out" 2>&1
    code=$?
    grep '^e2e: ' "$work/day$day.out"
    sed -n '/^E2E FAIL/,/^kept:/p' "$work/day$day.out"
    if [ "$code" -ne 0 ]; then
      grep -q '^E2E FAIL' "$work/day$day.out" || { tail -20 "$work/day$day.out"; echo "E2E FAIL scenario $scenario, seed $seed, day $day: paw ended with $code"; }
      failed=$((failed + 1))
      break
    fi
    cp -r "$work/project" "$work/days/day$day"
    day=$((day + 1))
  done
  # The last day's save opens again, in a new process.
  if [ "$code" -eq 0 ]; then
    "$BIN/paw" --clean --no-plugins --audio null --no-listen "$work/project" \
      -l tests/e2e/run.lua "$scenario" "$day" "$seed" "$work" check > "$work/check.out" 2>&1 || {
      sed -n '/^E2E FAIL/,/^kept:/p' "$work/check.out"; failed=$((failed + 1)); }
    grep '^e2e: ' "$work/check.out"
  fi
done
echo "e2e: $(( $(date +%s) - started )) s"
[ "$failed" -eq 0 ] && echo "all passed" || echo "$failed failed"
[ "$failed" -eq 0 ]
