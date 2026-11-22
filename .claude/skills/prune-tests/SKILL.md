---
name: prune-tests
description: Prune tests that guard no behavior.
argument-hint: "[optional path]"
---

Prune every test that guards no behavior.

**1. Find what each test depends on**

Keep a test only if it depends on the intended behavior: it should change only when that behavior changes, and fail only when it regresses.

If another test already guards the same behavior, prune the copy.

Prune tests that depend on:

**The past:** it asserts that removed code stays gone. To bring it back is a decision, not a regression.

For example:

- A feature was removed, and tests assert that it is gone.
- A module was moved, and a test asserts that it is absent from its old path.

**Nothing:** no change to the code can make it fail, so it has no reason of its own to change.

For example:

- It tests the browser: a `<button>` renders, or a click event fires. The browser is already tested.
- It mocks the unit under test, then asserts what the mock returns.
- It asserts what the type system already guarantees.

**The implementation:** it changes whenever the code does, also when the behavior did not change.

For example:

- The expected value is derived from the same logic as the code, so a wrong result still passes.
- It asserts private state, internal call order, or which helper was invoked.

**The machine:** it fails when the machine is slow or loaded, or when another test ran before it.

For example:

- It checks speed: a time, a share of a processor, or a count that changes with speed. Remove the speed check and keep the check of the behavior. If cost is the behavior, count the work. Move the measure to `bench/`, or delete it when a bench already measures it.
- It sleeps, reads the clock, or checks that nothing happened in a time. Rewrite it to wait for a state or an event, and to check an absence only after a sync point. When you remove a sleep or a clock read, make its line in `tests/timing-allowed.txt` smaller: `tools/testlint.lua` fails until you do.
- It reads state that it did not make. Rewrite it to make that state.

**2. Prune**

- Delete every test that is not anchored to intended behavior.
- Where one also covers behavior something relies on, rewrite it against that behavior instead.
- Delete production code that only existed for the tests you removed.

**What done looks like**

- Every test left is anchored to intended behavior.
- Each one would fail on a regression, and only on a regression.
- No test asserts code that no longer exists.
- No two tests guard the same behavior.
- No production code exists only for tests.

**Example**

```diff
--- a/pricing.test.ts
+++ b/pricing.test.ts
@@ rewritten: the expected value repeated the code's logic @@
 test("applies the discount", () => {
-  const price = 100;
-  expect(applyDiscount(price, 0.2)).toBe(price - price * 0.2);
+  expect(applyDiscount(100, 0.2)).toBe(80);
 });
--- a/cart.test.ts
+++ b/cart.test.ts
@@ rewritten against what callers see: it asserted private state @@
 test("adds an item to the cart", () => {
   const cart = new Cart();
   cart.add(book);
-  expect(cart._items.length).toBe(1);
+  expect(cart.total()).toBe(book.price);
 });
@@ deleted: checkout.test.ts already guards the same total @@
-test("total includes tax", () => {
-  expect(cartTotal([book], { tax: 0.1 })).toBe(11);
-});
--- a/export.test.ts
+++ b/export.test.ts
@@ deleted: it guards code that no longer exists @@
-test("legacy exporter is gone", () => {
-  expect(existsSync("src/export/legacy.ts")).toBe(false);
-});
--- a/session.test.ts
+++ b/session.test.ts
@@ deleted, with the production code that only existed for it @@
-test("clears the cache", () => {
-  _resetCacheForTests();
-  expect(_getCacheSize()).toBe(0);
-});
--- a/session.ts
+++ b/session.ts
@@ @@
-export function _resetCacheForTests() { cache.clear(); }
-export function _getCacheSize() { return cache.size; }
```
