#!/usr/bin/env python3
"""The no-comments hook of Claude Code (.claude/settings.json, PostToolUse on
Edit and Write) and of pi (.pi/extensions/paw.ts). It runs the ast-grep rules
of tools/ast-grep/comments on the edited file and reports each comment on a
line that the edit added, with exit 2, so that the agent deletes it. Doc
comments, SAFETY notes, tool directives, license lines and the usage header
of a script stay.

The added lines come from the structuredPatch of Claude Code, the unified
patch of pi (tool_response.patch), or else every line of the file.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

LANGUAGES = {
    ".rs": ".rs", ".lua": ".lua", ".tl": ".tl", ".nix": ".nix", ".sh": ".sh",
    ".bash": ".sh", ".py": ".py", ".ts": ".ts", ".mts": ".ts", ".js": ".js", ".mjs": ".js",
}
SHEBANGS = {"sh": ".sh", "bash": ".sh", "python3": ".py", "python": ".py"}


def suffix_of(path):
    suffix = LANGUAGES.get(os.path.splitext(path)[1])
    if suffix or os.path.splitext(path)[1]:
        return suffix
    with open(path, errors="replace") as file:
        first = file.readline()
    match = re.match(r"#!\s*\S*?(?:/env\s+)?([\w.]+)\s*$", first.strip())
    return SHEBANGS.get(match.group(1)) if match else None


def added_lines(response, path):
    patch = response.get("structuredPatch")
    if patch:
        lines = set()
        for hunk in patch:
            number = hunk["newStart"]
            for line in hunk["lines"]:
                if line.startswith("+"):
                    lines.add(number)
                if not line.startswith("-"):
                    number += 1
        return lines
    text = response.get("patch")
    if text:
        lines, number = set(), 0
        for line in text.splitlines():
            hunk = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)", line)
            if hunk:
                number = int(hunk.group(1))
            elif line.startswith(("+++", "---")):
                continue
            elif line.startswith("+"):
                lines.add(number)
                number += 1
            elif line.startswith(" "):
                number += 1
        return lines
    with open(path, errors="replace") as file:
        return set(range(1, sum(1 for _ in file) + 2))


def main():
    data = json.load(sys.stdin)
    response = data.get("tool_response") or {}
    path = (data.get("tool_input") or {}).get("file_path") or response.get("filePath") or ""
    if not os.path.isfile(path) or not shutil.which("ast-grep"):
        return 0
    root = subprocess.run(["git", "-C", os.path.dirname(os.path.abspath(path)), "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True).stdout.strip()
    config = os.path.join(root, "tools/ast-grep/comments/sgconfig.yml")
    relative = os.path.relpath(os.path.abspath(path), root) if root else ""
    if not os.path.isfile(config) or relative.startswith(("target/", "..")):
        return 0
    suffix = suffix_of(path)
    if not suffix:
        return 0
    lines = added_lines(response, path)
    with tempfile.TemporaryDirectory() as scratch:
        copy = os.path.join(scratch, "edited" + suffix)
        shutil.copyfile(path, copy)
        scan = subprocess.run(["ast-grep", "scan", "-c", config, "--json=compact", copy],
                              capture_output=True, text=True)
    try:
        matches = json.loads(scan.stdout or "[]")
    except json.JSONDecodeError:
        return 0
    found = []
    for match in matches:
        start = match["range"]["start"]["line"] + 1
        end = match["range"]["end"]["line"] + 1
        if any(line in lines for line in range(start, end + 1)):
            found.append(f"  L{start}: {match['text'].splitlines()[0][:100]}")
    if not found:
        return 0
    print(f"no-comments: {len(found)} comment(s) on the lines that this edit added to {relative}:", file=sys.stderr)
    print("\n".join(found[:30]), file=sys.stderr)
    if len(found) > 30:
        print(f"  and {len(found) - 30} more", file=sys.stderr)
    print("Delete them (skill no-comments). Only doc comments, SAFETY notes, tool directives, license lines "
          "and the usage header of a script stay.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
