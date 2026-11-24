# unsafe-ffi-boundary

> At a C boundary: borrow strings in, keep owned strings alive, return flat error codes, wrap each handle, and never let a panic out

## Why It Matters

C has no `Result`, no ownership and no way to unwind. Code that crosses the boundary must state the parts that C lacks. paw crosses it in each plugin host (CLAP, VST3, LV2) and in each `extern "C"` callback that a plugin calls.

## The rules

1. **Strings in.** Take `*const c_char` and read it with `CStr::from_ptr` in a small `unsafe` block. Check for a null pointer first. Borrow the data, and copy it only when Rust must keep it. Check UTF-8 with `to_str()`, and handle the error.
2. **Strings out.** Build a `CString`, keep it in a variable until the call returns, and pass `.as_ptr()`. The `CString` of a temporary drops at the end of the statement, and its pointer dangles.
3. **Errors.** Return a flat integer code (a `#[repr(C)]` `enum` or an `i32`) and put the details in an out parameter or a "last error" call. A Rust `enum` with data cannot cross.
4. **Handles.** Give C an opaque pointer made by `Box::into_raw`, take it back with `Box::from_raw` in the paired `free` function, and wrap it on the Rust side in a type with `Drop`. Each handle has one owner.
5. **Panics.** A panic that leaves an `extern "C"` function aborts the process. In a callback that runs in the host, write code that cannot panic, or wrap the body with `catch_unwind` and turn the failure into an error code. On the audio thread the callback also does no allocation and takes no lock.

## Bad

```rust
extern "C" fn name(out: *mut *const c_char) {
    let s = CString::new(make_name()).unwrap(); // panics on an inner NUL: the process aborts
    unsafe { *out = s.as_ptr() };               // `s` drops here: the pointer dangles
}
```

## Good

```rust
static NAME: &CStr = c"paw sampler"; // lives for the whole run

extern "C" fn name(out: *mut *const c_char) -> i32 {
    if out.is_null() { return ERR_NULL; }
    // SAFETY: `out` is not null, and the caller says that it is writable.
    unsafe { *out = NAME.as_ptr() };
    OK
}
```

Sources:
<https://rust-unofficial.github.io/patterns/idioms/ffi/errors.html>,
<https://rust-unofficial.github.io/patterns/idioms/ffi/accepting-strings.html>,
<https://rust-unofficial.github.io/patterns/idioms/ffi/passing-strings.html>,
<https://rust-unofficial.github.io/patterns/patterns/ffi/export.html>

## See Also

- [unsafe-small-module](unsafe-small-module.md)
- [unsafe-extern-block](unsafe-extern-block.md)
- [unsafe-safety-comment](unsafe-safety-comment.md)
