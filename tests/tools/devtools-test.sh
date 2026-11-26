#!/bin/sh
# Tests the cargo queue (tools/bin/cargo) and the no-comments hook
# (tools/comment-hook.py) with a stand-in cargo, in a scratch folder. The
# flake's check `devtools` runs it; it needs heavy, git and python3.
#
#   tests/tools/devtools-test.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
failed=0
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; failed=1; fi
}

mkdir -p "$work/fake" "$work/repo/tools/bin" "$work/other"
cat > "$work/fake/cargo" << 'EOF'
#!/bin/sh
echo "jobs=$CARGO_BUILD_JOBS args=$*"
[ "$1" = build ] && mkdir -p target/debug && touch target/debug/paw
exit 0
EOF
chmod +x "$work/fake/cargo"
cp "$here/tools/bin/cargo" "$work/repo/tools/bin/cargo"
cp "$here/tools/queue-defaults.sh" "$here/tools/stamp.sh" "$work/repo/tools/"
(cd "$work/repo" && git init -q && touch Cargo.toml && git add . && git -c user.name=t -c user.email=t@t commit -qm init)
(cd "$work/other" && git init -q)
export PAW_CARGO=$work/fake/cargo PAW_CARGO_LOCKS=$work/locks PAW_CARGO_SLOTS=1 PAW_CARGO_WAIT=0
unset CI HEAVY_HELD CARGO_BUILD_JOBS CARGO_TARGET_DIR
cd "$work/repo" || exit 1
cargo=$work/repo/tools/bin/cargo
cores=$(nproc)

check "a light command runs at once" "$("$cargo" metadata)" "jobs= args=metadata"
check "a build gets the cores of its slot" "$("$cargo" check)" "jobs=$cores args=check"
"$cargo" build > /dev/null
check "a build of paw writes its stamp" "$(cat target/debug/paw.stamp)" "$(tools/stamp.sh)"
CARGO_TARGET_DIR=$work/other/target "$cargo" check > /dev/null 2>&1
check "a target of another checkout is refused" "$?" 2

mkfifo "$work/ready" "$work/gate"
heavy --pool cargo --slots 1 --dir "$work/locks" -- sh -c "echo > '$work/ready'; read x < '$work/gate'" &
read -r _ < "$work/ready"
"$cargo" check > /dev/null 2>&1
check "a build waits while the slot is held (timeout 0)" "$?" 75
check "a cargo inside a held slot runs at once" "$(HEAVY_HELD=cargo "$cargo" check)" "jobs= args=check"
echo > "$work/gate"
wait

cp -r "$here/tools/ast-grep" tools/
printf '// Make a.\nfn f() {\n    let a = 1; // one\n}\n' > a.rs
patch='[{"newStart":1,"lines":["+// Make a.","+fn f() {","     let a = 1; // one"," }"]}]'
hook_input='{"tool_input":{"file_path":"'"$work"'/repo/a.rs"},"tool_response":{"structuredPatch":'"$patch"'}}'
out=$(echo "$hook_input" | python3 -I "$here/tools/comment-hook.py" 2>&1)
check "the hook reports a comment that the edit added" "$(echo "$out" | grep -c '^  L')" 1
check "the hook names its line" "$(echo "$out" | grep '^  L' | cut -c1-6)" "  L1: "
exit "$failed"
