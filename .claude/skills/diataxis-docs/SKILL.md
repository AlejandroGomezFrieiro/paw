---
name: diataxis-docs
description: Write, review, restructure or move paw's documentation by the Diátaxis framework (tutorials, how-to guides, reference, explanation), in plain-writing for external pages (README, docs/, extension and crate READMEs) and ASD-STE100 Simplified Technical English for internal text. Use whenever a task writes or changes anything under docs/, a README (top level, crates/*, extensions/*), the tutor's lessons, :help pages or docs/reference/api.md's generator, or asks where a piece of documentation belongs, why a page reads badly, or to "document", "write up", "add docs for" a feature — even when it only says "update the README" or "add a section".
---

# Documentation with Diátaxis

Diátaxis (diataxis.fr, by Daniele Procida) says there are four kinds of
documentation, because a user's need sits on two axes:

| | **acquisition** (study) | **application** (work) |
| --- | --- | --- |
| **action** (doing) | **tutorial**: learning-oriented, a lesson | **how-to guide**: goal-oriented, directions |
| **cognition** (knowing) | **explanation**: understanding-oriented, discussion | **reference**: information-oriented, description |

"There are four and only four types": the two axes cover the whole
territory. Almost every documentation problem is a page that crosses or
blurs these boundaries.

## The compass: use it on every piece you write or read

Ask two questions, of a page, a section, a paragraph or a sentence:

1. Does it inform **action** (what the user does) or **cognition** (what the user knows)?
2. Does it serve the **acquisition** of skill (study) or its **application** (work)?

| action + acquisition | action + application | cognition + application | cognition + acquisition |
| --- | --- | --- | --- |
| tutorial | how-to guide | reference | explanation |
| "Can you teach me to…?" | "How do I…?" | "What is…?" | "Why…?" / "Tell me about…" |
| a lesson | a series of steps | dry description | discursive explanation |
| teaching a child to cook | a recipe | the label on a food packet | a book on food's social history |

Use it most when you feel doubt: "intuition provides an immediate answer that
is also wrong" surprisingly often. Rules of thumb: boring, listy, tabular → reference;
something you could read in the bath → explanation; the reader has their
hands on paw and a goal → how-to; the reader is learning paw and we lead → tutorial.

## Tutorials (docs/tutorials/, and the tutor's lessons)

A lesson. Its purpose is that the learner acquires skill and confidence, not
that something gets done. "The instructor is condemned to be absent", so the
tutorial must work for every user, every time.

- **Don't teach: give things to do.** The learner learns from what they do.
- **Say where we are going**, never what they will learn: "In this tutorial
  we will make a four-bar loop and mix it." Not "you will learn…".
- **A visible result at every step**, early and often; show the exact
  expected output ("The status line now says `recording take 1`").
- **Narrate the expected**: "You will notice that…", "After a moment, …".
  Flag the likely slip: "If the clip stays grey, you probably pressed `r`
  before `I`."
- **Point things out in passing** ("Notice the `[+]` beside the name").
- **One path, no choices or alternatives**, no options, no "you could also".
- **Minimal explanation**: one clause and a link ("We use `V` because the
  whole track should move; see [About visual mode](…)").
- **Concrete and particular**: this project, these notes, this key.
- **Repeatable and safe**: a practice project the learner can reopen;
  undo always gets them back.
- **Usefully complete**: every action, concept and tool the lesson needs is met in it.
- Language: "We…", "First, do x. Now do y.", "The output should look like…",
  "Notice that…", and at the end a mild admiring summary of what was made.
- Test it: drive the lesson with real keys (the tutor's tests do), and fix
  every place a learner could get lost.

## How-to guides (docs/how-to/)

Directions for an already-competent user with a real goal. Work, not study.

- **Title says exactly what it shows: "How to …"** ("How to record a MIDI
  take over a loop"). Not "Recording" (whether? what?).
- **Goals of the user, not operations of the machinery.** "How to keep the
  drums out of a pitch operator", not "The `:drums.map` command".
  A guide may cut across many commands and views.
- Open with one line: "This guide shows you how to…" and what it assumes.
- **Action and only action**: no teaching, no digressions, no full option
  lists ("See [`:render`](…) for every option").
- **Real-world forks**: conditional imperatives — "If the track has no
  input, press `I` first. To record several takes, …".
- **Omit the unnecessary**; start and end at sensible points the reader
  joins to their own work. Order steps by necessity and by the user's flow.
- A how-to can be basic; a tutorial can be advanced. The difference is study vs work.

## Reference (docs/reference/, generated docs/reference/api.md, extension READMEs' tables)

Technical description of the machinery, consulted while working.

- **Describe and only describe**: austere, neutral, authoritative, no
  opinions, no instructions to reach a goal, no history.
- **Mirror the structure of the machinery**: the Lua API by module, keys by
  view and mode, commands alphabetically or by area, options in one table,
  the protocol by message. Not by user journey.
- **Consistent patterns**: every command, key and option entry has the same
  shape (name, arguments/default, one-sentence effect, limits). Same words for same things.
- **Short examples are welcome** to illustrate usage, never to teach.
- Warnings as plain facts: "`:w!` overwrites without asking. Never…".
- Limits are reference too: what is not done (docs/reference/limits.md).
- Generated reference stays generated (tools/apidoc.lua → api.md, types);
  never edit generated output by hand. Generated alone is not enough: the
  hand-written reference covers what the generator cannot.

## Explanation (docs/explanation/)

Discussion that builds understanding, read away from the work.

- **Title takes an implicit "About"**: "About the kernel and the Lua
  runtime", "About scenes: one view, two frontends", "About why MIDI is the truth".
- **Context and connections**: design decisions, history, constraints,
  alternatives considered ("REAPER does x; paw does y because…"), how the
  parts interact ("A turn ends with hooks, then scenes are sent…").
- **Opinions and perspective are allowed** and expected; weigh alternatives.
- **Bounded**: start from a real or imagined "why" question; no steps, no
  option tables. Link to the reference and how-tos instead.

## Common collapses to fix

- Tutorial ↔ how-to (the most common): a lesson that offers choices, or a
  guide that teaches. Split: lesson in tutorials, task in how-to.
- How-to written from the machinery ("The X command does…") → that's reference;
  write the guide from the goal, link the reference.
- Reference that grows into explanation (why, history, what-if) → move the
  discussion to an explanation page, keep the facts.
- Explanation absorbing instructions or option lists → move them out.
- Explanation sprinkled through every page → collect it into "About …" pages.

## paw's layout

```
README.md                    landing: what paw is, try it (a tiny tutorial), links into each kind
docs/README.md               the manual's contents, four sections by kind, one line per page
docs/tutorials/              lessons; the course is docs/tutorials/course/, GENERATED from
                             extensions/tutor/lua/tutor/lessons/*.lua by extensions/tutor/make-docs.lua
docs/how-to/                 one task per page, file named after the task: record-a-take.md
docs/reference/              keys, commands, options, views, devices, protocol, file formats,
                             api.md (GENERATED by tools/apidoc.lua), limits.md
docs/explanation/            about-*.md: architecture, scenes, MIDI as truth, the key rule, ...
crates/*/README.md           the crate's landing page, same rules in small
extensions/<name>/README.md  the extension's landing page: one-paragraph what, then sections
                             by kind in this order — Try it (a 5-step tutorial), How to …
                             (goals), Reference (keys, commands, options tables), About (why)
extensions/<name>/doc/*.md   more pages of :help; a long reference goes in doc/reference.md
```

Each page is one kind. A landing/contents page only introduces and links;
it is the one place where kinds sit side by side, each under its heading.

Rules specific to paw:

- **:help reads these files** (runtime/lua/paw/help.tl): docs/**.md,
  extensions' README.md and doc/*.md. Tags come from headings and from code
  spans at their first description, so keep each key, command (`:s`),
  option (`'timebind'`) and Lua name described once, in reference, in the
  first column of a table or at the start of a list item. Other pages
  mention it as code and link to it.
- **Tests read the docs**: a test checks every command and key an extension
  registers appears in its README or its doc/*.md; tutor tests check the course matches
  the lessons; tests/apidoc.lua checks api.md is current. Run
  `nix develop -c tests/tools/suite.sh` after any move.
- **Links**: relative Markdown links; after moving a page, grep the whole
  repo (code comments, manifests, READMEs, tests, flake.nix) for the old
  path and fix every one. Code comments point at reference or explanation, never tutorials.
- **Style**: plain-writing for external pages, STE for internal text
  (next section); terminal first, the graphical
  window second; no marketing words; no emoji; never name the owner's
  unpublished projects or home paths.
- **Pictures** belong to tutorials (what you will see) and to landing pages
  (what paw is). Reference may have a screenshot of a view's layout with
  labels. Keep their make scripts (docs/images/make, extensions' images/make).

## Language: plain-writing outside, STE inside

paw has two kinds of text. Each kind has its own style. Diátaxis decides
*what* a page says and where, for both kinds. The style decides *how* each
sentence says it.

| Kind | Text | Style |
| --- | --- | --- |
| External | `README.md`, `docs/**`, `extensions/*/README.md`, `extensions/*/doc/**`, `crates/*/README.md`, the tutor's lessons (they make the course), the doc comments that `tools/apidoc.lua` turns into `docs/reference/api.md` | plain-writing |
| Internal | `AGENTS.md`, `.claude/**` (skills), `bench/**`, Backlog tickets, design documents, other code comments, commit messages, pull request text, replies in chat | ASD-STE100 |

### plain-writing (external pages)

Load the skill in `.claude/skills/plain-writing` (`SKILL.md`), and read
its `PAW.md`. The main rules are these:

- Everyday words, complete sentences, and long sentences that explain.
- A topic sentence first in each paragraph. Contractions are allowed.
- No em dash, no en dash and no middle dot in prose. Straight quotes.
- Headings in sentence case. No puffery, no analogies, no negative
  parallelism ("not only X, but Y").
- No sentence that starts with "This", "That", "These" or "Those". No
  count at the start ("Two cautions.").
- A procedure gives its steps in order, in a numbered list or with
  "First", "Second", "Third".

The paw glossary below and the safety instructions (7.x) apply to
external pages too. The other STE rules do not.

### ASD-STE100 Simplified Technical English (internal text)

Internal text is in ASD-STE100 Simplified Technical English (Issue 9).

**Words (1.x)**
- One word, one meaning, one part of speech. Use a word only in its usual
  meaning ("follow" means "come after"; to obey a rule, write "obey").
- No synonyms for one thing: pick one word and keep it (rule 9.4). paw's
  words are fixed in the glossary below.
- Technical names (TN) are allowed for things: paw's names (track, clip,
  lane, device, view, buffer, pane, scene, role, register, quickfix list),
  and every code span (`:render`, `paw.qf`, `gU`, file names, option names)
  is a technical name and counts as one word. Do not use a technical name
  as a verb ("yank the clip" → "copy the clip with `y`", unless `yank` is
  the command's name in code).
- Technical verbs (TV) are allowed for computer actions where no simple
  verb fits: run, build, install, load, save, render, record, play, quantize,
  undo, redo, type, click, drag, select, paste, map (a key). Do not use them as nouns
  ("the render" → "the rendered file"; "a save" → "when you save").
- No slang, jargon or idiom ("out of the box", "under the hood", "spin up",
  "kick off", "a no-op" → "does nothing").
- American spelling (rule 1.14): color, behavior, center, license (noun
  and verb), gray. Code and file names keep their own spelling.

**Noun clusters (2.x)**: not more than three nouns together ("track
output routing menu" → "the menu of track outputs").

**Verbs (3.x)**
- Only: infinitive, imperative, simple present, simple past, simple future
  (will), and the past participle as an adjective ("the clip is selected").
- No present perfect or continuous ("has been saved" → "is saved";
  "is playing" → "plays"), no "-ing" form except in a technical name
  ("Recording" as a heading → "Record audio" / "Recordings"; "while
  playing" → "while the song plays").
- Active voice. Passive only in description when the agent is unknown.
- An action is a verb, not a noun ("do the adjustment" → "adjust";
  "perform a deletion" → "delete").
- No phrasal verbs ("set up" → "configure"/"prepare", "look up" → "find",
  "turn on" → "enable"/"start", "go back" → "return", "carry out" → "do").

**Sentences (4.x)**
- Short and clear. No contractions, no omitted words ("Done." →
  "The operation is complete." only where a sentence is needed; tables
  and lists may use short fragments for values).
- A vertical list for complex text: steps, conditions, alternatives.
- Connecting words between related sentences (then, but, because, if).
- Articles and demonstratives where English needs them ("Select the
  clip", not "Select clip").
- One topic per paragraph, not more than six sentences per paragraph.

**Procedures (5.x)**: steps in internal text (for example in AGENTS.md or a skill)
- Not more than 20 words in a sentence.
- One instruction per sentence, unless the actions are simultaneous
  ("Hold `Shift` and click the clip").
- Imperative: "Press `R`." not "You should press `R`" or "`R` is pressed".
- Put a condition or purpose first, with a comma: "If the track has no
  input, press `I`." "To record a take, press `R`."
- Notes give information, not instructions.

**Descriptive writing (6.x)**: the other internal text
- Not more than 25 words in a sentence.
- Give the most important information first. Use paragraphs and headings
  to show the structure. Keep the same words for the same things.

**Safety instructions (7.x)**: for data loss and loud sound only. Start
with the level word in bold (**WARNING** for data loss or hearing damage,
**CAUTION** for a smaller risk), then a clear command, then the risk:
"**WARNING:** Save the project before you use `:e!`. `:e!` discards the
changes that are not saved."

**Punctuation and counts (8.x)**: no semicolons. A hyphenated word, a code
span and a text in parentheses each count as one word. In a vertical list,
a colon counts as a full stop.

**Miscellaneous (9.x)**: when a word-for-word change does not work, write
the sentence again with a different construction. Write "for example" and
"that is" (not "e.g.", "i.e."), "and other" (not "etc.").

**paw glossary (one word for each thing, rule 9.4)**: track (not channel
strip), clip (not item, region), note, lane (an automation or controller
lane), device (instrument or effect on a track; a plugin is a device that
paw did not write), view (arrange view, piano roll, mixer, ...), window
(a part of the screen that shows a view; "the window" alone is wrong — say
"the graphical window" for paw-gui), project (not session, song file),
command (`:name`), key, option (`paw.opt.name`), extension (not plugin, add-on),
kernel, frontend (the terminal or the graphical window), buffer, register.

### How to check

Vale checks the Markdown files with the project's styles. `.vale.ini`
gives each path its styles: STE for internal files, Plain for external
pages.

```sh
nix develop -c tools/vale.sh                 # every page
nix develop -c tools/vale.sh docs/how-to/*.md
```

- `Plain` (.vale/styles/Plain), external pages: the rules of
  plain-writing that a pattern can find (dashes in number ranges, the
  middle dot in prose, curly quotes, heading case, overused and puffery
  words, plain words, "not just X, but Y", openings with a demonstrative
  or a count). At the level warning until phase B (the task after
  TASK-73) rewrites the docs. External pages also keep STE.Spelling, STE.Glossary,
  STE.PassiveBy and STE.Paragraphs.
- `STE` (.vale/styles/STE), internal files: the rules above: sentence
  and paragraph length (25 words), semicolons, contractions, tenses,
  "-ing" forms, the passive with "by", phrasal verbs, unapproved words,
  American spelling, the glossary.
- `Readability`, internal files: Flesch-Kincaid and Gunning fog grade of
  each page.
- `write-good`: cliches, "There is" openings, repeated words.
- `alex`: inclusive language (music and Vim words such as master, attack
  and yank are allowed).
- `AiTells`: patterns of machine-written prose (stock phrases, hidden verbs,
  "not just X, but Y", vague link text, dashes, file paths outside code).
- `Vale`: spelling, with paw's words in
  .vale/styles/config/vocabularies/Paw/accept.txt (add a real word there,
  never a misspelling).

Vale skips code blocks and code spans. Errors must be fixed. A warning
is fixed or kept on purpose (a technical name, a quoted UI label).
Vale is a help, not the standard: read every sentence yourself too.

## Workflow

Diátaxis is a guide, not a plan: structure "develops from within" by improving pieces.

1. **Choose** a piece: a page, a section, a paragraph.
2. **Assess** it with the compass: what need does it serve, how well? Does
   its language fit its kind? What should be added, moved, removed?
3. **Decide** the single next change that improves it now: split a mixed
   section, move a paragraph to its kind's page, retitle a guide "How to…",
   cut an option list from a how-to and link the reference.
4. **Do it and commit** (with its links and tests fixed). Repeat.

Never create empty quadrant folders or placeholder pages ("It's horrible");
a folder appears when the first real page moves into it. Documentation is
never finished but should always be complete: useful, accurate, and in a
healthy structural state after every commit.

Quality: functional quality (accurate, complete, consistent, precise) is
the craft's job and comes first — check every fact against the code and
by running paw. Diátaxis then gives the conditions for deep quality: flow,
fit to the user's need, anticipating the reader.

## Checklist before calling a docs change done

- [ ] Every page (and every section of a landing page) is one kind, by the compass.
- [ ] Tutorials: "we", one path, results shown at each step, no choices, minimal explanation linked.
- [ ] How-tos: titled "How to …", goal-first, conditional imperatives, no teaching, links to reference.
- [ ] Reference: neutral, structured like the machinery, consistent entries, each name described once.
- [ ] Explanation: "About …", why/context/alternatives, no steps or option tables.
- [ ] External pages: plain-writing (.claude/skills/plain-writing); internal text: STE (descriptive sentences ≤ 25 words, active voice, approved verb forms, no semicolons); glossary words in both; `tools/vale.sh <pages>` has no errors, and each warning left is on purpose.
- [ ] docs/README.md and the README landing pages link the new or moved pages.
- [ ] No stale path anywhere (`grep -rn "docs/<old>"`), `:help <tag>` still lands, suite green.
