# Handwired Doom for macOS

A local, native AppKit + MetalKit Doom vertical slice. It launches immediately with bundled **Freedoom Phase 1**. DoomGeneric supplies the temporary C game and software renderer; an exact frozen Metal circuit owns the locomotion part of every supported tic command. The long-term replacement contract is in [Docs/architecture.md](Docs/architecture.md), with the machine-readable [coverage ledger](Docs/circuit-coverage.json).

## Build and play

Requires Apple Silicon, macOS 14+, and Xcode. The project compiles its small Metal shaders from bundled source at runtime, so Xcode's optional offline Metal Toolchain component is not required.

```sh
xcodebuild -project HandwiredDoom.xcodeproj -scheme HandwiredDoom \
  -configuration Debug -derivedDataPath DerivedData \
  -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
open DerivedData/Build/Products/Debug/HandwiredDoom.app
```

Arrow keys move/turn; Shift runs; Option strafes; Space uses; Control or left click fires. **⌘⇧N** toggles the live circuit inspector; its buttons Pause, Step one tic, and Resume control simulation at tic boundaries. The menu's **File → Open IWAD…** accepts a user-owned commercial IWAD or another local Freedoom IWAD as an optional override. It relaunches the app with the selected path because DoomGeneric's current loader is single-boot. For development, `--iwad /absolute/path/to/freedoom2.wad` or `FREEDOOM_IWAD=/absolute/path/to/freedoom2.wad` overrides the bundled default. Config and saves normally live under `~/Library/Application Support/HandwiredDoom`; `HANDWIRED_DOOM_DATA_DIR` changes that local development directory.

The included `Assets/freedoom1.wad` is **official Freedoom 0.13.0**, release archive SHA-256 `3f9b264f3e3ce503b4fb7f6bdcb1f419d93c7b546f4df3e874dd878db9688f59`, WAD SHA-256 `7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d`. Its BSD-style notice and credits are in `Assets/` and copied into the app. To keep local development data ignored, `.local/` is excluded from Git. No commercial WAD is copied or packaged.

## Test

```sh
xcodebuild -project HandwiredDoom.xcodeproj -scheme CircuitTests \
  -configuration Debug -derivedDataPath DerivedData \
  -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
DerivedData/Build/Products/Debug/CircuitTests
DerivedData/Build/Products/Debug/CircuitTests --app-bundle \
  "$PWD/DerivedData/Build/Products/Debug/HandwiredDoom.app"
```

The parity executable compares 100,000 seeded in-domain snapshots against **the actual upstream `G_BuildTiccmd`**, the pure C extraction, the CPU graph, and the Metal graph. It also tests domain rejection, ring bounds/drops, pause/step scheduling, visualization invariance, and warm submit/wait latency. `--quick` runs 1,000 snapshots. `--emit-manifest Docs/locomotion-graph.json` regenerates the graph manifest, which tests compare byte-for-byte to the committed version. For WAD-backed evidence, see [Docs/validation.md](Docs/validation.md).

## Sources

`Sources/DoomCore` contains only the 80 C translation units required by the native application plus upstream headers and GPL license. It is copied from DoomGeneric commit `e257a09527062bfb986b6e5e0780839b6cbd5b71`; only `g_game.c` carries the circuit adapter and test hook. Handwired's execution model at commit `4ea7fcb27ebe93acf49b9f29a93e162b975bad46` informed the small affine/ReGLU/index-read IR. No TypeScript/browser code was embedded; its MIT license is included in `Docs/HANDWIRED-LICENSE.txt`. This repo stays local-only: no remote push, PR, distribution package, or App Store workflow.
