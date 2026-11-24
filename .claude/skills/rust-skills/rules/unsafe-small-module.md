# unsafe-small-module

> Put the `unsafe` code of one job in a small module with a safe public API

## Why It Matters

A safe wrapper is sound only if all the code that can break its invariants is in one place. Rust privacy works per module, so any safe code in the same module can change a field that the `unsafe` code relies on. When the unsafe code sits in a large module, a reviewer must read the whole module to trust it. When it sits in a small module, with private fields and a public API that cannot be misused, a reviewer reads one file.

## Bad

```rust
// A big module: the raw pointer and length are visible to all of its code.
pub struct Plugin { ptr: *mut f32, len: usize /* ... 30 more fields ... */ }
impl Plugin {
    fn set_len(&mut self, n: usize) { self.len = n; } // safe code breaks `get`
    pub fn get(&self, i: usize) -> f32 { unsafe { *self.ptr.add(i) } }
}
```

## Good

```rust
mod raw_buf {
    /// A buffer that the host owns. `ptr` and `len` are private and change only here.
    pub struct RawBuf { ptr: *mut f32, len: usize }
    impl RawBuf {
        /// # Safety
        /// `ptr` is valid for `len` reads until the buffer drops.
        pub unsafe fn new(ptr: *mut f32, len: usize) -> Self { Self { ptr, len } }
        pub fn get(&self, i: usize) -> Option<f32> {
            // SAFETY: `i < len`, and the constructor says that `ptr` is valid for `len` reads.
            (i < self.len).then(|| unsafe { *self.ptr.add(i) })
        }
    }
}
```

## Notes

- This is the module-level partner of [unsafe-minimize-scope](unsafe-minimize-scope.md), which keeps each `unsafe` block small.
- In paw, the plugin hosts (`crates/paw-plugins`) are the main case. Wrap each raw handle (a library, an instance, a buffer) in one small type with a `Drop`.

Source: <https://rust-unofficial.github.io/patterns/patterns/structural/unsafe-mods.html>

## See Also

- [unsafe-safety-comment](unsafe-safety-comment.md)
- [unsafe-ffi-boundary](unsafe-ffi-boundary.md)
- [unsafe-miri-ci](unsafe-miri-ci.md)
