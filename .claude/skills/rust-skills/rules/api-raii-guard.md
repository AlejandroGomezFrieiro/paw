# api-raii-guard

> Use a guard type to undo a change on every exit path, and keep its `Drop` short, infallible and quick

## Why It Matters

Cleanup after the work does not run when `?`, `return` or a panic leaves early. A guard type puts the cleanup in `Drop`, so it runs on each path. For example, a guard restores a flag, releases a lock, ends a span, or closes an undo group. The guard also holds the borrow, so the guarded value cannot be used while the change is active.

## Good

```rust
#[must_use = "the guard restores the flag when it drops"]
struct Muted<'a> { flag: &'a mut bool, was: bool }

impl<'a> Muted<'a> {
    fn new(flag: &'a mut bool) -> Self {
        let was = std::mem::replace(flag, true);
        Self { flag, was }
    }
}

impl Drop for Muted<'_> {
    fn drop(&mut self) { *self.flag = self.was; }
}
```

## Limits of `Drop`

- `Drop` cannot return an error. If the cleanup can fail and the caller must know (flush a file, commit), give the type a `finish(self) -> Result<..>` method, and let `Drop` do a best-effort cleanup only.
- `Drop` does not run after `mem::forget`, after a leak, or when the process aborts or exits. Do not rely on it for the one thing that must happen.
- Do not wait, lock or panic in `Drop`. A panic in `Drop` while the thread unwinds aborts the process.
- **Audio thread:** a value that drops there frees its memory there. Send a large value (a buffer, a `Vec`, an `Arc` whose count can reach zero) to another thread to drop it, as the garbage queue of the sampler does.
- Mark the guard `#[must_use]`. Without it, `let _ = guard;` drops the guard at once.

Sources:
<https://rust-unofficial.github.io/patterns/patterns/behavioural/RAII.html>,
<https://rust-unofficial.github.io/patterns/idioms/dtor-finally.html>

## See Also

- [mem-drop-order](mem-drop-order.md)
- [api-must-use](api-must-use.md)
- [test-fixture-raii](test-fixture-raii.md)
