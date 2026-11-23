---
name: architecture
description: "Read, update and check paw's architecture documentation: the local folder architecture/ (arc42 sections, decision records, a roadmap) that is the source of truth for the target design. Use it before you write a design, before you start a bundle of tickets, before you change a contract (a trait, a file format, a `paw.*` function, a protocol, a layer), and when a bundle merges. Also use it when a task says \"architecture\", \"ADR\", \"decision\", \"target design\", \"design document\" or \"Groma draft\", or asks why paw is built as it is."
---

# The architecture documentation of paw

The architecture documentation tells what paw is now and what paw is
built to be. The owner and the agents use it as the source of truth for
the target design. A ticket, a design or a review that disagrees with it
is wrong, or it needs a new decision first.

The documentation is local to the owner's machine. Git does not keep
it. A clone has no copy. Then the public pages in `docs/explanation`
give the current design, and the instructions for agents give the rules.

## 1. Where the documentation is

The folder is `architecture/` at the top of the main checkout, beside
`groma/` and the Backlog folder. An agent in a worktree does not see it
in the worktree. Find it from the common git folder:

```sh
arch="$(git rev-parse --path-format=absolute --git-common-dir)/../architecture"
```

The local file `CLAUDE.local.md` gives the absolute path.

## 2. The method

The method takes parts of five sources:

| Source | What paw uses | What paw does not use |
| --- | --- | --- |
| arc42, lean | The twelve sections as a fixed order. Each section is short. A section links to other text and does not copy it. | The full template with all subsections. A section with nothing true to say stays short. |
| Architecture decision records (Nygard, MADR) | One file for each decision, with a status. An accepted record does not change. A new record supersedes it. | Tools such as `adr-tools` or `log4brains`. A short script is enough. |
| C4 (Groma) | The map of the code as it is. Drafts for the planned parts. | Structurizr. A second model of the same code would drift from Groma. |
| Documentation that lives with the code | The text that a script can check: links, citations, statuses, tickets. | Pages that only repeat the code. |
| Fitness functions | The checks that keep the code in agreement with the rules (part 7). | Checks of speed in tests (the instructions for agents send those to `bench/`). |

The instructions for agents have the role of a "constitution": the philosophy and the
rules. The architecture documentation does not copy it. The tickets and
the design documents in the Backlog have the role of specifications and
plans. The architecture documentation keeps only the result of each
decision.

## 3. The layout

```text
architecture/
  README.md                  the index, the legend of marks, the status
  01-goals.md                goals and quality goals
  02-constraints.md          rules that paw cannot change
  03-context.md              users, outside systems, interfaces
  04-solution-strategy.md    the main ideas, with links to the ADRs
  05-building-blocks.md      crates, runtime, extensions (Groma ids)
  06-runtime.md              the turn, the sync, the audio thread
  07-deployment.md           Nix, processes, platforms
  08-concepts.md             kinds, modifiers, templates, graph, lanes
  09-decisions.md            the list of ADRs by subject
  10-quality.md              quality scenarios and their guards
  11-risks.md                risks and technical debt
  12-glossary.md             one word for one thing
  13-roadmap.md              the target, phase by phase
  decisions/
    README.md                the log: number, title, status, date
    NNNN-title-with-dashes.md
```

## 4. Current and target

Each section from 04 to 13 has two parts:

- `## Current`: what the code on main does now. Each fact gives a
  citation such as `crates/paw-core/src/model.rs:121`, or a link to a
  page in `docs/`.
- `## Target`: what paw is built to be. Each item names an accepted ADR
  and the work that makes it. The work is a ticket id or a bundle of
  the roadmap (`bundle A1`). An item of a proposed ADR says "Proposed".

A heading that starts with "Target" starts a target part. The part ends
at the next heading of the same level or higher. The lint (part 7)
reads each list item and each table row in a target part.

A section can mark one item with a word at the start, in bold:
**Current**, **Target** or **Proposed**. Use the bold mark only where a
split in two parts is not clear.

## 5. When to read it

Read the documentation before each of these tasks:

1. Before you write a design document. Read `04-solution-strategy.md`,
   `08-concepts.md` and the ADRs of the subject.
2. Before you start a bundle or a ticket that changes a contract. A
   contract is a trait, a type that is saved, a file format, a function
   of `paw.*` or `paw.api`, a message of the protocol, or a layer.
3. Before you review a branch for a merge.
4. When a ticket and the documentation disagree. Stop and tell the
   coordinator. Do not choose one by yourself.

## 6. When and how to update it

### 6.1 A new decision

1. Write a new ADR in `decisions/` with the next number. Use the
   template in part 8. Set `status: proposed`.
2. Add a line to `decisions/README.md` and to `09-decisions.md`.
3. Add the proposed target items to the sections, each marked
   "Proposed".
4. Tell the coordinator. The owner accepts or rejects the ADR.
5. When the owner accepts it, set `status: accepted` and the date.
   Remove the word "Proposed" from its items.

Agents propose. Only the owner accepts or rejects an ADR. An agent can
accept an ADR only when the owner gave the decision in words. Then the
ADR quotes the words of the owner and gives the date.

### 6.2 A changed decision

Do not edit the text of an accepted ADR. Write a new ADR that supersedes
it. Set the old ADR to `status: superseded by NNNN`. Change only its
status line. Edit an ADR only to fix a broken link or a word with an error.

### 6.3 A design document

A design document in the Backlog feeds one or more ADRs. When the owner
accepts the ADRs, the design document is history. Add one line at its
top: "Superseded by architecture/decisions/NNNN (date)". The ADR links
the design document as its source. Do not copy the design into the
sections. Copy only the result.

### 6.4 A merged bundle

When a bundle merges on main, do these steps in the same work:

1. Move each item that the bundle made from `## Target` to `## Current`.
   Add a citation of the code.
2. If the bundle made a planned part of the Groma map, accept its draft
   with `groma accept <id>`. Run `groma agent-instructions` first.
3. If the bundle changed a contract, update `08-concepts.md`.
4. Update the phase in `13-roadmap.md`.
5. Run the lint.

### 6.5 A change of a contract

A change of a contract updates the documentation in the same work. If
no ADR allows the change, stop. Write a proposed ADR first.

## 7. The checks

Run the lint after each change of the documentation:

```sh
.claude/skills/architecture/archlint.sh
```

It finds these errors:

- A relative link to a file that does not exist.
- A citation `path:line` to a file that does not exist or that is too
  short.
- An ADR with no status, a status that is not known, or no date.
- An ADR number used two times, or a "superseded by" to no ADR.
- An ADR that `decisions/README.md` does not list.
- A target item with no ticket and no bundle.
- A ticket id that the Backlog does not have.
- A `groma:<id>` that the Groma map does not have.

It gives a note for a target item that names a bundle and no ticket.
The coordinator makes the ticket.

The lint checks the documentation. Other checks keep the code in
agreement with the rules of the documentation. They are the fitness
functions of paw:

| Rule | Check | Where it runs |
| --- | --- | --- |
| No module of the runtime reads a higher layer | `luajit tools/layers.lua` | the suite, `nix flake check` |
| No test reads the clock, sleeps or reads the machine | `luajit tools/testlint.lua` | the suite, `nix flake check` |
| The chain crates have no dependency on paw | `tools/chaindeps.lua` | `nix flake check`, when the chain crate is on main |
| The Teal types are correct, with no new `any` | `tools/tlcheck.sh`, `runtime/types/any-allowed.txt` | the suite, `nix flake check` |
| The API reference agrees with the code | `tools/apidoc.lua check` | the suite |
| The audio thread does not allocate | the Rust test of no allocation (skill `rust-testing`) | `cargo test` |
| Each extension names its commands and keys | the test of the READMEs | the suite |
| The docs obey the styles | `tools/vale.sh` | the hook, `nix flake check` |

A new rule in an ADR gets a check when a script can find a fault. The
ADR names the check in its "Guard" line.

## 8. The ADR template

```markdown
---
status: proposed
date: YYYY-MM-DD
deciders: owner
tickets: [TASK-n]
groma: [paw-kernel]
---

# NNNN. A title that names the decision

## Context

The problem and the forces, in neutral words. Links to the design
documents and the code.

## Decision

What paw does. One paragraph in active voice. For an accepted ADR of
the owner, a quote of the owner's words and the date.

## Consequences

What gets better, what gets worse, what other work follows.

## Guard

The check that keeps the decision true, or "None".
```

Put a quote of the owner in a `text` block. Vale does not read the
block, so the words stay exact.

The status is one of `proposed`, `accepted`, `rejected`, `deprecated`
or `superseded by NNNN`. The title of a file is lowercase words with
dashes: `0007-generic-modifier.md`.

## 9. Links to tickets and to Groma

- A target item names its ticket (`TASK-n`) or its bundle.
- A ticket that makes an ADR true gets the ADR in its references:
  `backlog task edit <id> --add-ref architecture/decisions/NNNN-title.md`.
- A Groma element is written `groma:<id>`, for example
  `groma:paw-kernel`. `groma view <file>` gives the id of the
  component that owns a file.
- A planned part gets a Groma draft (`groma draft`). The draft names
  the ADR in its overview. Read `groma agent-instructions` first, and
  do not edit the files of `groma/` by hand.

## 10. Style

The documentation is internal text. Write it in ASD-STE100 Simplified
Technical English, as the skill `diataxis-docs` tells. Draw pictures as
text, not wider than 74 columns. Do not copy the code. Cite it.
