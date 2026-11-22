# The singing engine

`paw-utau-engine` is the program that sings for extensions/utau. It is a host for
OpenUtau.Core (phonemizers, resamplers, DiffSinger and the other renderers),
and the extension talks to it over a Unix socket (`lua/utau/proto.lua` on
the extension side, `PawUtau.Protocol` on the engine side).

- The engine is MIT licensed (`LICENSE`).
- The engine is built against OpenUtau at `bc194b6fe4897427a73066390b286e11205fd10f`,
  which the top flake takes as its `openutau` input. OpenUtau is MIT licensed
  (its `LICENSE.txt`, kept in the build's source), and the `libworldline.so` that it
  ships is installed beside the engine.
- `nix/engine-deps.json` is the NuGet lock for that pair.

## Build it

`nix build .#utau-engine` builds the engine alone, and `nix build .#paw-utau` builds
paw with the extension and the engine in it (see `../nix`). Without Nix, you need
a .NET 10 SDK and OpenUtau checked out at the commit above in
`../third_party/OpenUtau`, and then you run:

```
dotnet publish PawUtau.Engine -c Release -o out
```

Then point the extension at the engine with `paw.opt.utau_engine = "/path/to/out/paw-utau-engine"`
or `PAW_UTAU_ENGINE=/path/to/out/paw-utau-engine`.
