# own-split-borrow

> Split a struct into parts that change for different reasons, so a method of one part does not borrow the others

## Why It Matters

The compiler tracks borrows of separate fields, but not across a method call. A method that takes `&mut self` borrows the whole struct. A caller that holds a reference to one field cannot call it, and the usual "fix" is a `.clone()` or an index. When the struct holds groups of fields that change for different reasons, put each group in its own struct. A method then takes only the group that it needs, and the borrows stay apart.

## Bad

```rust
struct Mixer {
    gains: Vec<f32>,
    meters: Vec<f32>,
}

impl Mixer {
    fn set_meter(&mut self, i: usize, v: f32) { self.meters[i] = v; }

    fn update(&mut self) {
        for (i, g) in self.gains.iter().enumerate() {
            // Error: `set_meter` borrows all of `self`, and `gains` is still borrowed.
            self.set_meter(i, *g);
        }
    }
}
```

## Good

```rust
struct Gains(Vec<f32>);
struct Meters(Vec<f32>);

struct Mixer {
    gains: Gains,
    meters: Meters,
}

impl Meters {
    fn set(&mut self, i: usize, v: f32) { self.0[i] = v; }
}

impl Mixer {
    fn update(&mut self) {
        // Two fields, two borrows: the compiler accepts it.
        for (i, g) in self.gains.0.iter().enumerate() {
            self.meters.set(i, *g);
        }
    }
}
```

## Notes

- If the new structs have no meaning of their own, the split is wrong. Use a free function that takes the fields, or restructure the code.
- On the audio thread this removes clones and locks that only exist to satisfy the borrow checker.
- `CODING_STANDARDS.md` already says that a struct with fields that change for different reasons is two structs. This rule gives the borrow reason.

Source: <https://rust-unofficial.github.io/patterns/patterns/structural/compose-structs.html>

## See Also

- [own-borrow-over-clone](own-borrow-over-clone.md)
- [anti-clone-excessive](anti-clone-excessive.md)
- [closure-disjoint-capture](closure-disjoint-capture.md)
