# midilsp

MIDI LSP, a language server for music, as an entry of `paw.lsp`. This
extension tells paw where the engine is and how to start it. It keeps the
preset and the rules with the project, and lists the problems of all
servers. All that it shows goes through the generic parts of the core
(`paw.diagnostic`, `paw.harmony`, `paw.complete`). So any other server that
uses the same protocol shows the same way.

```lua
paw.ext.load("/path/to/paw/extensions/midilsp")
```

## Try it

1. Install the engine, `reaper-midi-lsp`, on the `PATH`.
2. Type `:ext.load midilsp`, then `:midilsp`. paw shows where the engine is
   and how it runs.
3. Open a MIDI clip with two voices in parallel fifths in the piano roll.
   After a moment, the notes show diagnostics.
4. Press `<Space>lD`. The list of problems opens.
5. Put the cursor on a problem with a fix, and press Enter. paw applies the
   fix.

## How to choose the rules

- To check the rules of one profile of the engine, type
  `:midilsp.preset strict-counterpoint`.
- To disable one rule, type `:midilsp.rule parallel-perfect off`.
- To see all the rules and switch them, press `<Space>lR`.

## Reference

| Command | Keys | Effect |
| --- | --- | --- |
| `:midilsp` | | shows where the engine is and how it runs. `:midilsp start`, `:midilsp stop` |
| `:midilsp.preset strict-counterpoint` | | sets the rules to check, as one of the profiles of the engine |
| `:midilsp.rule parallel-perfect off` | `<Space>lR` | enables or disables a rule. Alone, a list to switch them |
| `:problems` | `<Space>lD` | the diagnostics of all servers, with their fixes. Enter goes to one, or applies a fix |
| | `<Space>li` | the language servers and what they can do |

- The engine is `paw.opt.midilsp_cmd`. If it is not set, it is
  `$MIDI_LSP_ENGINE`. If that is not set, it is `reaper-midi-lsp` on the
  `PATH`.
- [Language servers and diagnostics](../../docs/reference/language-servers.md) describes what paw
  sends to the engine.
- The tests of the extension run against the real engine when paw finds
  one. Otherwise, the suite skips them.
