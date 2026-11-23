"""A small language server for the mix, for the tests of paw.lsp: LSP's own
shapes, attached to the `mix` subject. A part whose fader is above 0 dB may
clip: a warning on it, fixed by bringing the fader to 0 dB. Every part gets
a label with its fader; hover says what a part's fader and pan are; a code
action on a part lowers it 6 dB.

    python3 mix_lint.py
"""

import json
import sys

docs = {}


def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def parts(doc):
    return doc["parts"] + [doc["master"]]


def publish(uri):
    doc = docs[uri]
    diagnostics, labels = [], []
    for t in parts(doc):
        labels.append({"location": {"uri": t["address"]}, "label": f"{t['volume']:+.1f} dB", "kind": "level"})
        if t["volume"] > 0:
            diagnostics.append({
                "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 0}},
                "severity": 2, "code": "hot-fader", "source": "mix-lint",
                "message": f"{t['name']}'s fader is at {t['volume']:+.1f} dB: it may clip",
                "data": {"location": {"uri": t["address"]},
                         "fixes": [{"title": f"Bring {t['name']} to 0 dB", "edit": [{"uri": t["address"], "set": {"volume": 0}}]}]},
            })
    send({"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": {"uri": uri, "diagnostics": diagnostics}})
    send({"jsonrpc": "2.0", "method": "paw/publishAnnotations", "params": {"uri": uri, "annotations": labels}})


def part_at(uri):
    for doc in docs.values():
        for t in parts(doc):
            if uri == t["address"] or uri.startswith(t["address"] + "/"):
                return t
    return None


def answer(method, params):
    if method == "initialize":
        return {"serverInfo": {"name": "mix-lint"},
                "capabilities": {"hoverProvider": True, "codeActionProvider": True,
                                 "paw": {"subjects": ["mix"], "annotations": True}}}
    if method == "textDocument/hover":
        t = part_at(params["paw"]["location"]["uri"])
        if not t:
            return None
        return {"contents": f"{t['name']}: fader {t['volume']:+.1f} dB, pan {t['pan']:+.2f}"}
    if method == "textDocument/codeAction":
        t = part_at(params["paw"]["location"]["uri"])
        if not t:
            return []
        return [{"title": f"Lower {t['name']} by 6 dB",
                 "edit": {"paw": [{"uri": t["address"], "set": {"volume": t["volume"] - 6}}]}}]
    if method == "shutdown":
        return None
    raise KeyError(method)


def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        message = json.loads(line)
        method, params = message.get("method"), message.get("params") or {}
        if method == "exit":
            return
        if method in ("textDocument/didOpen", "textDocument/didChange"):
            td = params["textDocument"]
            text = td.get("text") if method == "textDocument/didOpen" else params["contentChanges"][0]["text"]
            docs[td["uri"]] = json.loads(text)
            publish(td["uri"])
            continue
        if method == "textDocument/didClose":
            docs.pop(params["textDocument"]["uri"], None)
            continue
        if "id" not in message:
            continue
        try:
            send({"jsonrpc": "2.0", "id": message["id"], "result": answer(method, params)})
        except KeyError as e:
            send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": f"unknown {e}"}})


main()
