# Owner answers to the architecture plan (grilling, 2026-11-23)

Verbatim answers. They feed the ADRs 0017 to 0023 and a revision of containers.md and architecture-plan.md.

## Round 1: containers (Q3, Q3b)

1. Where sound lives: "I think we should separate video and audio even if they come from the same source. So the player video and player sound are reasonable to separate. I think we might need some more complicated design for routing outputs. Once again, we are limiting ourselves to old-school DAW ways of working somehow, while we should be able to define any input/output relationships easily. I think some sort of graph representation of input/outputs is going to be needed at some point to make sure each lane generates the output properly."
2. One container or two: "These were meant as examples, and do not need to necessarily be different. A single container might have all of them."
3. Editing a derived lane: "A derived lane should not be editable unless you 'render' it. They are sort of a modifier on top of some source, and unless we make them 'independent' (aka, go from derived to source) their editing should be limited to how they act on the source, and not necessarily their timings."
4. Takes for every lane kind: "I think in general yes, the take idea should be possible for all lane types. An example that comes to mind: with a diffsinger (think of openutau) we could generate different takes given the same source. This is a crucial design in our UX, so we might need to refine this."
5. The word: "Let's setup Lane as the source of truth."
6. Mixed kinds in a lane: "I think, for simplicity at this stage, Lanes should not be able to mix different kinds of clips. In a sense, it's starting to become a typed non-linear editor so that we can easily define 'views' and 'editors'."

## Round 2: lanes and the graph

Preface: "We have to think carefully how we can produce a 'mix' in the music sense."

1. Mute, solo, arm, fader: "I think those might belong to lanes better, and likely only specific lanes that would allow you to record, right? Let's refine"
2. How many graphs: "I think having both a project graph as well as being able to view/edit/export a container graph makes sense to me. We should compose the project graph from its building pieces."
3. Mixed speeds in one picture: "Elaborate with a specific example, I am not sure."
4. Producer timing: "I think the producer's own business, but I am happy to refine this together with examples."
5. Render and the link back: "Let's consider both cases to make the choice. I think the link should still exist somehow so we can come back/reuse it, but for performance reasons it might make sense to 'delink' it."
6. Comping on derived takes: "Comping makes sense."
7. Type granularity: "Let's discuss this further with specific examples"

## Round 3: making a mix

Owner: "Yeah, I think this makes sense, let's go with your suggestions". Accepted:

- A. One graph with two kinds of arrows: stored lanes and live signals. "Render" materializes any signal arrow into a lane (freeze = render a sampler output; print = render a bus). The mixer view is that graph filtered to the live audio nodes (strips, buses, sends, master) drawn as columns.
- B. A mix is the live audio part of the graph: strips (fader, pan, inserts), buses that sum, sends, master. Automation is a lane of kind `curve` that feeds a node parameter. Arm on source lanes whose kind can be recorded (audio, MIDI, curve, maybe camera video). Mute on any lane and any strip or bus. Solo on a strip or bus (only path to master); solo of a lane = only what it feeds. Strip ownership (the round asked, no recommendation given; orchestrator's recommendation, taken under "your suggestions"): a strip is a free node in the model; a new audio-producing lane gets its own strip by default (familiar), and two lanes may share one strip.
- C. Producer timing is the producer's business: it reports the span its output covers (pre-utterance, tails). Per-note producer controls (phoneme timing, breath, pitch curves, as in OpenUtau) live on the source notes as attributes the producer owns, edited in the producer's editor; the derived lane stays fully derived.
- D. Render keeps provenance by default (recipe + hash of the source); paw says when the source changed and offers "re-derive as a new take"; `:lane.detach` cuts the link.
- E. A type is a base kind plus properties (channels, lyrics present, rig, frame rate). Ports declare what they need; paw inserts a converter when one exists, else refuses with a message that names the missing property.

## Round 4: takes, comping, outside processes

Owner: "I think this sounds good, let's go with your suggestions". Accepted:

1. Source or derived is a property of each take, not of the lane; a comp may pick from either.
2. When the source changes: re-bake the takes the comp uses first, the others when the user looks at them; partial bakes when the producer supports them. An edited (rendered) take never re-bakes: it gets a stale mark and the offer "re-derive as a new take".
3. A comp is source data: ranges that each name a take, with crossfades for audio; stored with the lane, undoable; downstream producers read the comp.
4. MIDI comp: a note that crosses a comp boundary is kept whole from the take where it starts.
5. Keys (starting point, refined with screens): takes fold under any lane (`za`); `[` `]` step the active take; visual selection + `<localleader>c` comps that range to the take under the cursor; `K` on a comp range names the take and seed.
6. Opening a project never starts an outside program; it plays kept results. Re-bake needs the extension; the first run of each outside program in a project asks once.
7. Outside jobs run like plugin helpers: scratch HOME, working folder in the project cache, no network unless the extension declares it, progress, cancel, one reorderable queue (`:bakes`).
8. A missing program: the lane keeps its last bake with an "absent" mark; `K` names what to install.

## Round 5: the modifier stack (Q2)

Owner: "I agree with your suggestions right now. Piano-roll UX is something we will have to refine, as it's the default (but not necessarily only!) editor view for midi". Accepted:

1. One stack type on a clip or on a lane; a lane stack runs after each clip's stack. A derived lane differs only in that its output goes to another lane.
2. One word, "render", for stacks and derived lanes (replaces "Apply"); rendering a stack keeps provenance, so the user can re-derive.
3. Render only a prefix of a stack (the first n entries), never one entry in the middle.
4. Piano roll: source notes solid (ink), result as ghosts, `\m` swaps. The piano roll UX needs its own refinement; it is the default MIDI editor, not the only one (editor subject: several editors per stream kind).
5. Clip label `+3 q16 hum`, `ƒN` for many entries, `?` for an entry that waits.
6. Keys as TASK-75: `<Space>cs` panel (on a lane header: the lane stack), `<Space>ca` add, `<Space>cA` render all, `\a` render up to the entry, `\t` save as template. Refined with golden screens.
7. `:clip.recipe` is chain-language text, `off` disables an entry, edited in a buffer, `:w` one undo step.

## Round 6: templates, store, project files (Q4, Q6)

Owner: "I agree with all of the points". Accepted:

1. A template is anything whose kind is in the template family. Built in: project, container, lane, graph (rack), stack, export preset. Extensions add kinds with their own format.
2. A template keeps the shape by default; a flag keeps the content ("song starter"). Reusable musical material goes in a separate clip library.
3. Insert copies by default; "insert linked" keeps a link with overrides per instance. A linked definition is always copied into the project; `:template.update` pulls a newer version from the store.
4. One layout `templates/<kind>/` in four layers: project, user (`$XDG_DATA_HOME/paw/templates/`), extension, bundled; the nearer layer wins; the picker shows the origin. Racks move to `templates/rack/`, export presets to `templates/export/`.
5. Project folder: a folder per container (nested), a subfolder per lane with its clip files and takes, `devices.chain` for the container's graph, `ext/<name>/` for extension data kept byte for byte when absent.
6. The Template contract starts as a Teal record in core with a Rust list of kinds; a Rust trait comes with the first Rust-native template kind (m-11 or Wasm).

## Round 7: last points

Owner: "Agreed with all". Accepted:

1. The user word for the container is "part" (as in a score: Violin I is a part). Not "track".
2. Rule 4 becomes: "Lanes are the truth. Source lanes hold the data. A derived lane is a recipe plus its kept result. A project opens and plays without the extension or program that made a derived lane." AGENTS.md rule 4 and the public page change in the same work as ADR 0019.
3. Q1: close m-3 and m-4; the architecture work runs beside m-2 and m-9.
4. Q7: a video monitor view draws frames with half blocks, or the kitty graphics protocol where the terminal has it; a video lane in the arrange view shows clip names, times, and thumbnails where images work. Phase 5.
5. Revise the design before any code: containers.md, architecture-plan.md and the Proposed ADRs from these answers, then a new roadmap for the owner. A1 waits for it. Batches 18 and 19 land; unrelated work (TASK-299, the last m-2 ticket) goes on.

## Lane heads (TASK-322), 2026-11-23

The owner: "Should we modify the 'head' of lanes so it's possibly custom per lane… An utau diffsinger might want to showcase the singer's picture in the 'head'… We also are going to need a 'default' one." Then "sure, let's see where this design takes us", and on the design (backlog/docs/designs/lane-heads.md): "Sure, accept". Q1-Q9 accepted as recommended; ADR 0034 accepted.

## Time motions (TASK-326), 2026-11-23

The owner: "Let's approve 0036 and close m-2". Q1-Q9 of backlog/docs/designs/time-motions.md accepted as recommended; ADR 0036 accepted. m-2 closed (all 51 tickets done).

ADR 0033 (paw-types, the value types that the model and the engine share): the owner, "Accept then", 2026-11-23. Accepted.

ADR 0037 (chain language 2 details): the owner, "Accept 0037", 2026-11-23. Accepted.

## 2026-11-24 (morning report, owner: "I accept all except for the push")

- ADR 0038 (upkeep parts read the session and own no state): accepted.
- Notation commands: `:part.*` of the notation extension becomes `:staff.*`.
- `<Space>t` stays the parts group.
- TM1: swing and bar restarts move h/l (kept).
- G2: an absent split kind plays its first branch; its warning stays in the document warnings until G3.
- Esc stops the song and the take (kept).
- Clean-up of the six old worktrees whose commits are on main: approved.
- No push: batches 21, 22, W1 and later stay local.
