# Zino Racing Engine — Roadmap

All phases 1–11 are complete (v1.0.0). Details: docs/PHASE_REPORTS.md. Known limits: DEVELOPMENT_STATUS.md.

## Next (post-1.0 ideas)
- Scratch-style stacked block view alongside the node graph
- Android export preset in the Build Center
- Installer for the Zino Editor
- GDExtension (C++) vehicle model option
- Physical-device iOS testing

## Completed (original plan; items marked partial during Phase 1 were finished later)

## Phase 1 — Foundation ✅
- ✅ Environment inspection and report
- ✅ Engine decision (Godot 4.7.2) and architecture
- ✅ Repository and project structure
- ✅ Zino Editor application shell
- ✅ Godot editor integration plugin (Zino Bridge)
- ✅ Working, authenticated connection between both applications (tested end-to-end)
- ✅ First milestone: home, create/open project, editor, viewport, hierarchy, selection,
  transform gizmos, save/load, racing test scene with a drivable four-wheel vehicle

## Phase 2 — Editor ✅
- ✅ Home screen, project management, main editor, hierarchy, viewport, inspector, save/load
- ✅ Undo/redo, duplicate, delete, multi-select, snapping, ortho views, autosave + recovery
- ✅ Content browser (browse/open) + asset importer; thumbnails in the Asset Store
- ✅ Multiple scenes per project in the UI, Save As, scene switching
- ✅ Box selection, road control-point gizmos in the viewport
- ✅ Asset Store page on the home screen (replaces the planned Asset Library)

## Phase 3 — Block Coding ✅
Block editor, categories, typed IR, validator, runtime interpreter, execution trace, code view (readable pseudocode — the runtime executes the IR).

## Phase 4 — Vehicle System ✅
- ✅ Shared vehicle model (`ZinoVehicle`): suspension, steering, engine RPM, automatic gearbox,
  brakes, handbrake, downforce, drag; 7 physics profiles as parameter sets
- ✅ Vehicle Studio (import car models, wheel placement, tuning preview), manual gearbox, audio

## Phase 5 — Track Studio ✅
- ✅ Spline roads (Catmull-Rom), width, banking, surfaces, edge lines, shoulders, collision
- ✅ Checkpoint / start-finish / grid entities
- ✅ Viewport spline editing, barriers, pit lanes, racing line, procedural generation

## Phase 6 — Racing Systems ✅
RaceManager (countdown, laps, sectors, positions, results), AI opponents.

## Phase 7 — Cinematic Graphics ✅
- ✅ Presets Ultra Max → Performance, SDFGI, SSR, SSAO, SSIL, volumetric fog, AgX, clear-coat paint
- ✅ Time of day, weather, wet roads, post-processing editor, profiling tools

## Phase 8 — Open World ✅
Terrain, streaming, vegetation, traffic.

## Phase 9 — Additional Tools ✅
UI Studio, Audio Studio, Camera Studio, asset import pipeline.

## Phase 10 — iOS ✅
Export templates, iOS preset, touch controls designer, Xcode export, GitHub Actions macOS build workflow (signing needs the user's Apple account).

## Phase 11 — Release ✅
Portable release (Zino.exe + engine add-ons), samples, docs, versioning 1.0.0. An installer is a post-1.0 item.
