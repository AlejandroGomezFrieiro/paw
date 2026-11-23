---
name: paw-code
description: "How to write and change code in paw (Rust, Teal and Lua). The loop of implement, test and three rounds of refactor, and the rules for code style, tests, maintainability, comments and logic. Use it for each ticket that changes code, and for each review of code."
---

# Code in paw: implement, test, refactor

Use this skill for each change of code. It adds a method to the rules for agents
(the instructions for agents). The language skills give the details: `rust-skills` for
Rust, `teal` for Teal, `paw-extension` for extensions, `prune-tests`
for tests. The owner took these rules from the workflow
`rust-programming.md` of `stackpress/rust` (2026-11-22) and adapted
them to paw.

## 1. The loop

1. **Find the contract.** Read the code, its callers, its tests and the
   ticket. Find the owner of the feature: the module that a person
   opens first to change it. Write down what must change and what must
   stay the same: the order of effects, the errors, the undo step, the
   message to the user. Keep the changes of other people.
2. **Make it work with little code.** Write the smallest clear code
   that gives the behavior. Do not add a layer, a trait or a registry for a
   future need. Write the comments while you write the code. Refactor
   only what stops you now.
3. **Prove it.** Write the tests of part 3. Fix each real failure before
   you say that the code works.
4. **Round 1: logic.** Read each path of the code with the signals of
   part 6. Make hard decisions clear: a named predicate, an early return,
   a short function, a table. Keep the behavior: the order of matches,
   the first error, the undo step. Run the tests again.
5. **Round 2: responsibility.** Ask the questions of part 4. Move code to
   the module that owns it. Keep code that belongs together in one place.
   Remove a wrapper that adds nothing. Run the tests again.
6. **Round 3: consistency and comments.** Make the code like the code
   next to it: names, errors, options, how a command or key is added.
   Write the comments of part 5. Fix each comment that is no longer
   true. Run the tests, the format check and the lint checks again.
7. **Repeat a round when it is necessary.** Do three rounds at least. A
   round with no change is correct when you write what you examined and
   why the code is clear. Do not make changes only to fill a round. Do
   not change the style of code that is already clear.
8. **Report each round.** Give what each round found and changed, or
   what it examined. Give the checks that you ran, and what you are not
   sure of.

## 2. Code style

- Use clear names. Do not abbreviate. Name the domain, the stage or the
  owner: `take_lane`, `fold_state`, not `helper`, `manager`, `util2`.
- Make imports and exports explicit. A module exports what its callers
  need and no more. In Rust, use `pub(crate)` where it is possible.
- Use a concrete struct, record or function first. Add a trait or an
  interface only when two adapters use it now (one adapter is a seam on
  paper). No Factory in paw's own types; use a Builder for a value with
  many optional settings.
- Make a wrong state difficult to write: one `enum` type with all of its
  cases, not two flags that can disagree. In Teal, use a record type and
  an `enum` type, and no `any` where a value has a shape.
- A fallible input (a file, a project, a user command, a plugin) gives
  an error or a message, not a panic or a stack trace (rule 6).
- A fix of a crash has a test that crashed on the old code.
- Do not weaken a lint with `allow` or with a cast to make a check pass.
  If a rule is wrong, write why in the report.
- In Rust: borrow a value in place of a clone, but not when lifetimes
  make clear ownership hard to read. On the audio thread: no lock, no allocation, no wait.

## 3. Tests

The skills `rust-testing` and `lua-testing` give the details for each
language: the helpers, the commands, and the kinds of test to write.

- A test proves a behavior that a user or a caller relies on. It fails
  only when that behavior breaks (`prune-tests`). It does not copy the
  steps of the implementation.
- Test the edges: empty, zero, the first and the last item, an unknown
  value, an error, the undo step. A fix of the user experience uses the
  real keys.
- Where a result depends on a combination (mode and selection and view,
  for example), write a small table of the cases that change the result,
  and test each row.
- Use mutation as a lens: would a test fail if `>` became `>=`, if `and`
  became `or`, if a negation went away, or if an error was lost?
- **No test depends on time or load.** No sleep, no deadline as an
  assertion, no count of frames, no "done when idle". Wait for an event
  or a state, or step the clock. A time in milliseconds goes to
  `bench/` and not into a pass or a fail. A test that fails under load is
  a bug in the test.
- A test leaves no state behind: options, keys, hooks, tabs, files.
- Do not make a test pass by a retry, a wider tolerance, a skip, or an
  assertion that is always true.

## 4. Maintainability

Look for these signals in the code that you change:

- **Too much in one file.** One file holds several concerns that are not
  related: state, keys, drawing, the file format, rules of the domain.
  Split it only when the file makes the next change hard to find.
- **No owner.** The behavior of one feature is in many places that are
  not related.
- **A place for left-over helpers.** A helper of one feature belongs
  next to that feature. A shared module holds only what all use.
- **Hidden links.** A caller must know the internals of another
  module, or a small change needs edits in files that are not related.
- **Too many small files.** Do not split a small file that is about one
  thing, or a private flow that only one caller uses.
- **A reference to a higher layer.** A module of the runtime reads only
  its own layer and the layers below it. [The layers](layers.md) gives
  the order, and `tools/layers.lua` checks it.

Ask these questions, and name what moves:

- Where does a person look for this behavior first?
- Which module owns this code?
- Which file must become smaller?
- What must stay where it is, because a move adds only ceremony?

Do not write "clean this up". Name the responsibility that moves and
where it goes.

## 5. Comments

- Write one comment for each logical block of code: the purpose of the
  block, not one comment for each file or function.
- Write a comment on the line where the code hides the intent: a branch,
  a change of state, a chain of calls with a rule in it, an order of
  events, a format on disk, an `unsafe` block, an assumption.
- When a condition and its result each take several lines, write one
  comment for the condition and one for the result.
- For a field of state, write what it holds, what changes it, and what
  must always be true of it.
- Doc comments (`///`, `---`) give the contract of a declaration. Line
  comments explain how the code runs.
- Do not repeat the syntax in words. Do not keep code in comments. Do not
  add words only to fill space.
- Change the comment in the same edit as the code. A comment that is not
  true is a defect.
- Language: comments are internal text, in Simplified Technical English
  (the instructions for agents). The doc comments that `tools/apidoc.lua` reads are
  external text: they use `plain-writing`.

## 6. Logic signals

These are lenses for a review, not numbers to report.

- **Paths.** How many paths through the code must a test prove?
- **Depth.** A condition in a condition in a loop; a callback with
  guards in it.
- **Hard conditions.** Many `and` and `or` in one condition, mixed
  negation, the same part twice, concerns that are not related in one
  condition.
- **Combinations.** Modes, selections, options, kinds of track, states of
  the transport: which combinations change the result, the effect or the
  error?
- **Untested branches.** The `else`, the default, the error, the empty
  case, the first match in an order, a failure of a process or a file.
  Line coverage does not prove branch coverage.
- **Fan-out.** A function that both decides and calls many modules is a
  risk. Split the decision from the calls.
- **The same rule twice.** The same decision in two modules, or in the
  code and the docs. Put it in one place when that removes a risk of
  disagreement.

## 7. Not in force yet

- Coverage floors (70 % of lines for each crate that changes). paw has no
  coverage tool for Lua and Teal yet. Measure Rust coverage only when a
  ticket asks for it.
- The lints `missing_docs` and `unwrap_used` as errors. They belong to
  the work on the interface of `paw-core` and the workspace lints.
