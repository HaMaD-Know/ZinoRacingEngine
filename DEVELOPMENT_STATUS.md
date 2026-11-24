# Development Status

Last updated: 2026-11-24 · Version **1.1.0** · **All 11 phases complete** + Easy mode

Per-phase details (what, files, decisions, tests, limits): [docs/PHASE_REPORTS.md](docs/PHASE_REPORTS.md).

| Phase | Status |
|---|---|
| 1 Foundation (environment, architecture, editor shell, Godot bridge, test scene) | ✅ |
| 2 Editor (multi-scene, road point drag, box select, Apple-style UI) | ✅ |
| 3 Block coding (147 blocks, compiler, runtime, Block Studio) | ✅ |
| 4 Vehicle Studio (GLB/glTF/FBX import, wheel fit, tuning, test drive, engine audio) | ✅ |
| 5 Track Studio (generator, barriers, sectors, grid, pit lane, racing line) | ✅ |
| 6 Racing (circuit/sprint/time trial/elimination, AI, replays, sectors) | ✅ |
| 7 Cinematic graphics (Ultra Max default, time of day, weather, wet roads, headlights, post FX) | ✅ |
| 8 Open world (terrain sculpt/paint, vegetation, water, buildings, tunnels, traffic, streaming) | ✅ |
| 9 Tools (Asset Store, UI Studio, Audio Studio, camera modes) | ✅ |
| 10 iOS (Build Center, touch controls, Xcode export, CI workflow) | ✅ |
| 11 Release (portable Zino.exe, engine add-ons, docs, samples) | ✅ |
| Easy mode (Make a Game, Simple/Advanced, Game tab, block recipes, Coach) | ✅ |

## Tests
- Headless: `.\tools\run-tests.ps1` → **61 tests, 4,670 checks, all passing** (~3 min; includes a real
  Godot-editor bridge session, full AI races, and real Windows and iOS exports).
- Windowed self-test (`--zino-selftest=<dir>`): ~42 steps including a real Asset Store download and the Make a Game → Simple mode → recipe → play path; also run
  against the released Zino.exe.
- Benchmark (Iris Xe, 1600×900): Ultra Max 8.3 · Ultra 11.2 · High 18.8 · Balanced 30.9 · Performance 31.1 FPS.

## Known limits
- Ultra Max is slow on this laptop; use toolbar *Preview → Balanced* while editing (game output stays Ultra Max).
- iOS: the IPA must be compiled and signed on macOS (Xcode, or the generated GitHub Actions workflow);
  not tested on a physical iPhone. No Android export preset.
- Blocks are a node graph (Blueprint-style), not Scratch-style snapped stacks.
- No GDExtension/C++ layer; vehicles use Godot's `VehicleBody3D` with Zino extensions.
- Poly Haven has no car models; cars come from your own GLB/glTF/FBX files.
- No installer: the release is a portable folder and needs Godot 4.7.2 for Godot integration and
  exports (path in `zino_config.json` or Home › Settings).
- Self-tests add their projects to Recent Projects (remove them with "Remove").

## How to run
```powershell
.\tools\run-editor.ps1          # from source
.\tools\build-release.ps1       # builds builds\ZinoEditor\Zino.exe
.\tools\run-tests.ps1
```
