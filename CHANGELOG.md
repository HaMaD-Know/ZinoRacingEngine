# Changelog

## 1.1.0 — 2026-11-24 — Easy mode (still professional)

### Added
- **✨ Make a Game** on the Home screen: five friendly steps (game type, car + colour, track, time and
  weather, final touches) create a complete, playable game in one click (`core/zino_quick_game.gd`,
  `app/home/make_game_wizard.gd`). Seven game types, six cars, five tracks, six scenes.
- **Simple mode** (default): friendlier workspace names (Build, Track, Car, Logic, Store, Publish),
  fewer toolbar options, no bottom console. **Advanced** toggle (toolbar or View menu) shows every
  professional tool; both modes edit the same project data.
- **Game tab**: Play button, race type, laps, opponents, skill, car colour, handling, camera, time of day,
  weather and traffic in plain language. Every change is undoable.
- **Block recipes**: 10 ready-made, pre-wired rules (boost on a key, final lap alert, lap timer, rain from
  lap 2, save best lap, stuck helper, speed bonus score, night race, GET READY, victory message) via
  **✨ Recipes…** in Logic/Blocks (`app/blocks/block_recipes.gd`).
- **Coach**: a 5-step checklist in the viewport that ticks itself off as you play, paint, tune, add a
  recipe and open Publish; *Show me* jumps to the right place (`app/editor/coach.gd`).
- Chase camera start view is set from the scene (`camera.startMode`).

- **Zino on iPhone/iPad**: touch navigation in the 3D view (one finger orbit/tap select, pinch zoom,
  two-finger pan), Retina UI scale, engine add-ons bundled in the app, projects visible in the Files app;
  desktop-only parts (Godot bridge, local export) hidden on iOS. GitHub workflow
  `.github/workflows/zino-editor-ios.yml` builds the editor `.ipa` (unsigned without Apple secrets).
- Game iOS workflow rewritten: Team ID injected, unsigned build without secrets, proper manual signing
  with the provisioning profile, Godot unpacked outside the game, macOS 26 runner + newest Xcode.

### Fixed
- AI opponents now start on the grid slots instead of piling up next to the player.


## 1.0.0 — 2026-11-24 — Phases 2–11

### Added
- Editor: multiple scenes, road control-point dragging, box selection, Apple-style Light/Dark/System UI.
- Block coding: 147 blocks in 19 categories, typed compiler with validation and code view, runtime
  interpreter (async waits, loop safety, functions, recursion, save data), Block Studio with live trace.
- Game systems: race manager (circuit, sprint, time trial, elimination; sectors), AI opponents, replays,
  HUD, procedural engine/tyre audio, time of day, weather, wet roads, headlights, DOF, speed blur.
- Vehicle Studio (GLB/glTF/FBX import, wheel detection and fitting, full tuning, test drive telemetry).
- Track Studio (procedural circuits, barriers, tunnels, sectors, grids, pit lanes, racing line).
- Open World (terrain sculpting/painting, vegetation, water, buildings, traffic, streaming distances).
- Asset Store (Poly Haven CC0 textures/HDRIs/models + Zino built-ins), UI Studio, Audio Studio,
  camera modes (chase, close, hood, bumper, cockpit, orbit, trackside replay).
- Build Center: iOS Xcode-project and Windows exports, validation, icons, GitHub Actions iOS workflow;
  touch controls (arrows, wheel, tilt) with designer.
- Release packaging: Zino.exe, engine add-ons, docs, sample projects.

### Fixed
- Viewport picking used the wrong World3D; physics fell behind real time at low FPS; vehicle roll
  resistance; checkpoint orientation; hairpins in generated tracks; AI flip recovery; trees on roads;
  bridge losing the scene when Godot opened another; release build depending on test code.


## 0.1.0 — 2026-11-23 — Phase 1 (Foundation)

### Added
- Zino Editor application (Godot 4.7.2): home screen (Home, Projects, Templates, Documentation,
  Settings), New Project wizard with 8 racing templates, main editor with menus, toolbar,
  hierarchy, add palette, 3D viewport, inspector, console, bridge log and content browser.
- 3D viewport: orbit/pan/zoom/fly camera, Perspective/Top/Front/Side views, picking, multi-select,
  move/rotate/scale gizmo (world/local, snapping), grid, selection boxes, frame selection.
- Undo/redo for every edit, duplicate, delete, rename, drag-and-drop reparenting.
- Project format (`project.zino`, `Scenes/*.zscene`), validation, atomic saves with backups,
  autosave and crash recovery, add-on repair.
- Zino runtime add-on: scene builder, spline road generator, `ZinoVehicle`, chase camera,
  graphics presets (Ultra Max default), procedural PBR materials, runtime game entry scene.
- Zino Bridge: Godot editor plugin + loopback WebSocket server with token authentication and a
  validated command whitelist (16 commands, 4 events).
- In-editor playtest with real vehicle physics (Play / Pause / Stop).
- Headless test suite (31 tests), windowed app self-test, graphics benchmark tool.

### Changed
- Engine switched from Unreal Engine 5 (brief) → Unity 6 (briefly) → Godot 4.7.2 (final).
