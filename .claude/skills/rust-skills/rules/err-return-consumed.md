# err-return-consumed

> When a function takes a value by move and can fail, give the value back in the error

## Why It Matters

A function that consumes its argument and then fails destroys the value. The caller must clone the value before the call, only for the case that it fails. If the error carries the value, the caller keeps the original and can retry, queue it, or drop it. The standard library does this: `mpsc::Sender::send` returns `SendError(T)`, and `String::from_utf8` returns an error with `into_bytes`.

This matters most for a queue between threads. A push to a full queue must not lose the message, and the audio thread must not clone it to be safe.

## Bad

```rust
fn push(queue: &mut Queue, msg: Msg) -> Result<(), Full> { /* msg is lost on error */ }

// The caller clones each message in case the push fails.
if push(&mut queue, msg.clone()).is_err() {
    retry_later.push(msg);
}
```

## Good

```rust
struct Full<T>(T);

fn push(queue: &mut Queue, msg: Msg) -> Result<(), Full<Msg>> { /* ... */ }

if let Err(Full(msg)) = push(&mut queue, msg) {
    retry_later.push(msg);
}
```

## Notes

- `rtrb::Producer::push` already does this (`PushError::Full(value)`). Use the returned value. Do not clone before the push.
- Implement `Error` for the type, and keep the value out of its `Display` text.
- A function that takes `&T` or `&mut T` has no need for this.

Source: <https://rust-unofficial.github.io/patterns/idioms/return-consumed-arg-on-error.html>

## See Also

- [err-custom-type](err-custom-type.md)
- [own-borrow-over-clone](own-borrow-over-clone.md)
- [async-bounded-channel](async-bounded-channel.md)
