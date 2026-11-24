#!/bin/sh
# Refuses a commit that reformats Rust files it does not change.
#
# paw is not rustfmt-clean, so `cargo fmt` (or an editor's format on save)
# rewrites many files whose code stays the same. Such a commit hides the
# real change from review and conflicts with every open branch. A staged
# .rs file whose text is the same after spaces, line breaks and commas are
# taken out is only reformatted. More than $PAW_REFORMAT_MAX (3) such files
# in one commit is refused.
#
#   tools/reformat-check.sh       check the staged files (.githooks/pre-commit)
#   PAW_REFORMAT_MAX=200 git commit ...   a reformat that the owner wants
max=${PAW_REFORMAT_MAX:-3}
squash() { tr -d ' \t\n\r,'; }
only=""
n=0
for f in $(git diff --cached --name-only --diff-filter=M -- '*.rs'); do
  old=$(git show "HEAD:$f" 2> /dev/null | squash | cksum)
  new=$(git show ":$f" | squash | cksum)
  if [ "$old" = "$new" ]; then
    n=$((n + 1))
    only="$only
  $f"
  fi
done
if [ "$n" -gt "$max" ]; then
  echo "reformat-check: $n staged Rust files change only in their format:$only"
  echo "Unstage them (git restore --staged <file>; git checkout -- <file>) and keep the style of each file by hand."
  echo "A reformat that the owner asks for: PAW_REFORMAT_MAX=$n git commit ..."
  exit 1
fi
