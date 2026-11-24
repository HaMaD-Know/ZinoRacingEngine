# HANDOFF — Zino Racing Engine (read this first)

Written 2026-11-23 for whoever continues this job (human or AI).

## What this is
A racing-game development environment built on **Godot 4.7.2** (the user switched from UE5 → Unity → Godot).
The **Zino Editor** is itself a Godot app (`ZinoEditor/`). Games made with it are Godot projects that
contain two add-ons copied from `ZinoEditor/addons/`: `zino_runtime` (game runtime) and `zino_bridge`
(Godot editor plugin). Read `ARCHITECTURE.md`, `docs/PHASE_REPORTS.md`, `docs/PROTOCOL.md`,
`docs/PROJECT_FORMAT.md`.

## User requirements still in force
- Do all phases 1–11 one by one, test each, write a report per phase (append to `docs/PHASE_REPORTS.md`).
- **The finished app must still open on the Home screen.** (It does: `app/main.tscn` → `ZinoApp.show_home()`.)
- Graphics default **Ultra Max** (never auto-downgrade; editor preview quality is separate).
- **Apple-style UI** (done: `app/zino_theme.gd`, Light/Dark/System in Home › Settings).
- **Professional block coding** (done: 147 blocks, compiler, runtime, Block Studio).
- **Asset Store** (done: Poly Haven CC0 store + Zino built-ins, `app/store/asset_store.gd`, `core/zino_store_client.gd`).
- Primary export target iOS. Desktop editor on Windows.
- Don't commit to git unless the user asks (nothing is committed yet; repo initialised on `main`).

## Environment
- Godot: `F:\Godot\Godot_v4.7.2-stable_win64.exe` (+ `_console.exe` for CLI). **Self-contained mode**
  (`F:\Godot\_sc_`): editor data, `user://` and export templates live in `F:\Godot\editor_data\`.
- Export templates 4.7.2 installed (incl. `ios.zip`, Windows) in `F:\Godot\editor_data\export_templates\4.7.2.stable\`.
- C: has only ~7 GB free — keep everything on F:. Laptop: Iris Xe, 12 GB RAM (Ultra Max ≈ 8 FPS @1600×900).
- `F:\UnityCache` (1.6 MB) is leftover from the Unity attempt; safe to delete by hand.

## How to run / test
```powershell
.\tools\run-editor.ps1                     # the app (Home screen)
.\tools\run-tests.ps1                      # headless suite (needs --import first; script does it)
.\tools\run-tests.ps1 -Filter test_race    # one file
F:\Godot\Godot_v4.7.2-stable_win64_console.exe --path ZinoEditor -- --zino-selftest=<out dir>   # windowed smoke test + screenshots
```
- Always `--headless --import` after adding new `class_name` scripts (refreshes the class cache).
- Parse-check one script: `godot_console --headless --path ZinoEditor --check-only -s res://path.gd`.
- **Godot 4.7 treats "type inferred from Variant" as an ERROR**: use `var x: float = ...` when the
  right side is untyped (Dictionary access, untyped loop vars, ternaries mixing types).
- Don't name methods `_set`/`_get` (they override Object virtuals). Don't name inner classes after
  native classes (e.g. `Thread`).
- The Bash tool breaks on very long heredocs; write patch scripts to the scratchpad with the Write tool
  and run them with python.
- Headless renderer is a dummy: MultiMesh transforms etc. can't be read back in tests.

## Status by phase
| Phase | State |
|---|---|
| 1 Foundation | ✅ done, tested |
| 2 Editor (multi-scene, road point drag, box select, Apple theme) | ✅ done, tested |
| 3 Block coding (library, compiler, runtime, Block Studio, game context) | ✅ done, tested |
| 4 Vehicle Studio (model import GLB/glTF/FBX, wheel fit, tuning, test drive) | ✅ done, tested |
| 5 Track Studio (generator, barriers, checkpoints, grid, pit lane, racing line) | ✅ done, tested |
| 6 Racing (race rules circuit/sprint/timeTrial/elimination, AI, replays, sectors) | ✅ done, tested |
| 7 Cinematic graphics (time of day, weather, wet roads, headlights, DOF, speed blur) | ✅ done, tested |
| 8 Open world (terrain sculpt/paint, vegetation, water, buildings, tunnels, traffic, streaming) | ✅ done, tested |
| 9 Tools (Asset Store, UI Studio, Audio Studio, camera modes, asset importer) | ✅ done, tested (54/54 suite) |
| 10 iOS (Build Center, touch controls, Xcode export, CI workflow) | ✅ done, tested (real Windows + iOS exports) |
| 11 Release (Zino.exe + engine/ + docs + samples via tools/build-release.ps1) | ✅ done, released exe self-tested |

## Status: all phases done + Easy mode (v1.1.0). Optional follow-ups are in ROADMAP.md › Next.

### Easy mode (v1.1.0, user asked "make it easier but still professional")
- Home › **✨ Make a Game** → `app/home/make_game_wizard.gd` → `core/zino_quick_game.gd` (`create(choices)`).
- Simple/Advanced: `editor_screen.gd` (`simple`, `SIMPLE_WORKSPACES`, `set_advanced()`), setting `simpleMode`
  (default true). Workspace keys stay the same (Scene/Track/Vehicle/Blocks/Store/Build); only labels change.
- Game tab: `app/editor/game_panel.gd` (right tab 0). Right tabs: 0 Game, 1 Inspector, 2 Track, 3 World.
- Recipes: `app/blocks/block_recipes.gd` + `ZinoBlockStudio.insert_recipe()/open_recipes()`.
- Coach: `app/editor/coach.gd`, progress in `project.zino` → `coach: {enabled, done[]}`.
- Tests: `tests/test_quick_game.gd`, `tests/test_recipes.gd`; self-test steps after "project reopens cleanly".

## Original step-by-step notes (now completed, kept for reference)
1. **Test Phase 9**: write `tests/test_tools.gd` covering: `ZinoStoreClient.plan_files` (textures/hdris/models
   from a sample `/files` JSON), `filter`/`categories`; material with `albedoTexture` loads via `ZinoAssets`
   (needs `ZinoModelLoader.project_root` set); HDRI sky (`settings.skyHdri`) → `PanoramaSkyMaterial`;
   `model` entity builds with box collision; `ZinoAudio.render` returns N frames, louder with load;
   `ZinoTouchControls.default_layout()` and `apply_layout`; HUD `apply_layout` offsets.
   Optionally one live store download (network) of a small texture at 1k into a temp project.
   Then run the full suite (`.\tools\run-tests.ps1`) and the windowed self-test; add self-test steps for the
   Store/UI/Audio workspaces (screenshots). Append the Phase 9 report.
2. **Phase 10 Build Center** (new workspace "Build"): validation checks (bundle id format, version, icon,
   project.godot renderer has `.mobile` override, textures ETC2/ASTC import setting on, memory estimate from
   asset sizes, entities/features not supported on Mobile renderer → warnings), generate
   `export_presets.cfg` for iOS (bundle id, version, team id placeholder left EMPTY — never store signing
   secrets) and Windows; include filter `*.zscene,*.zblocks,project.zino,Config/*.json,Assets/*`; run
   `godot --headless --path <game> --export-release "iOS" Builds/iOS/<name>.xcodeproj` (works on Windows:
   produces the Xcode project; IPA needs a Mac) and Windows `.exe` export; show logs; add a GitHub Actions
   workflow template (`.github/workflows/ios.yml`, macos runner, signing via repo secrets) into game projects.
   Touch controls: add `test_touch.gd`; UI Studio Touch tab already edits `settings.touch`.
3. **Phase 11**: export the Zino Editor itself (`ZinoEditor/export_presets.cfg`, Windows Desktop preset) to
   `F:\Projects-HaMaD-Html\ZinoRacingEngine\builds\ZinoEditor\Zino.exe`; copy `ZinoEditor/addons/zino_runtime`,
   `zino_bridge` to `builds/ZinoEditor/engine/addons/` and `docs/` + root *.md to `builds/ZinoEditor/docs/`
   (`ZinoProjectService.engine_addons_dir()` and home `_doc_files()` already look there). Exclude
   `addons/zino_bridge` from the editor export (it is an EditorPlugin) and `tests/`, `tools/`.
   Verify the exported exe opens on the **Home screen** and can create + open a project. Sample projects,
   version bump, CHANGELOG, DEVELOPMENT_STATUS, ROADMAP updates.
4. Update `DEVELOPMENT_STATUS.md`, `ROADMAP.md`, `CHANGELOG.md` (they still describe Phase 1 only).

## Key files
- App: `ZinoEditor/app/` (zino_app.gd root, home/, editor/editor_screen.gd workspaces, viewport/, blocks/, studios/, store/)
- Editor core: `ZinoEditor/core/` (command stack, scene edits, project service, bridge server, asset importer, store client)
- Runtime: `ZinoEditor/addons/zino_runtime/` (core/ format, entities, templates, scene builder; blocks/; race/; vehicles/; track/; world/; rendering/; game/ context, hud, audio, touch, zino_game)
- Tests: `ZinoEditor/tests/` (`run_tests.gd`, ~45 tests) and `app/zino_selftest.gd`.
