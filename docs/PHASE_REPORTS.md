# Phase Reports

One report per development phase: what was implemented, files, decisions, tests and known issues.
Phase 1 is described in DEVELOPMENT_STATUS.md.

---

## Phase 2 — Editor completion ✅

**Implemented**
- Multiple scenes per project: File › New Scene (from any template), Open Scene, Save Scene As, Set as
  Start Scene; double-click a `.zscene` in the Content Browser; unsaved-changes prompt when switching.
- Road control points: select a road → blue handles appear; drag them on the ground (snapping
  supported); the road regenerates on release; undoable.
- Box selection: drag on empty viewport space (Ctrl/Shift adds to the selection).
- **Apple-style UI** (user request): macOS-inspired Light/Dark/System appearance (Home › Settings),
  system font (SF Pro if installed, otherwise Segoe UI Variable), system-blue accent, rounded
  controls, segmented tabs, translucent menus with shadows, sidebar-style lists.
- Bug fixes found by the self-test: viewport picking used the wrong World3D (clicks would fail);
  physics now keeps real time at low frame rates (`max_physics_steps_per_frame = 40`).

**Files**: `app/editor/editor_session.gd`, `editor_screen.gd`, `content_panel.gd`,
`app/viewport/viewport_panel.gd`, `app/zino_theme.gd`, `app/zino_ui.gd`, `app/zino_app.gd`, home screen.

**Tests**: self-test steps — road point moved, box selection, new scene from template, switch scene,
save as, scene list, real click-picking of the car. All pass.

**Moved**: the Asset Library page is delivered with the Asset Store (Phase 9).

---

## Phase 3 — Block Coding ✅

**Implemented**
- **Block library**: 147 blocks in 19 categories — Events (game start, player joins, every frame, timer,
  countdown, race start/finish, lap, checkpoint, collision, key, button, area, messages), Race (start,
  stop, restart, finish, laps, countdown, score, lap/position/lap time/best lap/race time…), Vehicles
  (speed, RPM, gear, position, power, top speed, throttle/brake/steer/handbrake control, gears,
  gearbox mode, player control, reset, teleport, paint, handling profile, nitro), Physics (velocity,
  force, impulse, gravity, suspension, tyre grip, wheel contact, mass, downforce), AI (start/stop,
  difficulty, behaviour, racing line, targets), Camera (mode, FOV, shake, target), Environment (time
  of day, weather, fog, exposure, presets, sun), Audio (sounds, music, volumes, engine/tyre sound),
  UI (messages, big text, HUD elements, progress bars, labels, results, menus), Input, Logic, Loops
  (repeat, forever, while, until, for, for-each, break, wait, wait-until, stop), Math (operators,
  functions, min/max, clamp, blend, random, vectors), Text (join, lap-time formatting…), Variables,
  Lists, Functions (define, call, call-with-result, return, parameters, recursion), Data (save/load
  between sessions) and Debug.
- **Compiler** (`zino_block_compiler.gd`): typed IR; validation of unknown blocks, type mismatches,
  doubled connections, flow cycles, value cycles, undefined/duplicate functions, invalid literals and
  enums, unreachable blocks (warning), newer formats. **Code view**: readable Zino Script (clearly
  labelled pseudocode; the runtime executes the IR, not this text).
- **Runtime** (`zino_block_runtime.gd`): event-driven threads with explicit frames; async waits;
  every loop kind; automatic yield after 4000 steps per frame so infinite loops never freeze the
  game (plus a warning); recursion limit 64; runtime errors stop only the failing script and point
  at the block; execution trace signal.
- **Game backend for every block** (`zino_game_context.gd`): race manager, AI opponents, HUD,
  procedural engine/tyre audio, environment (time of day, weather, wet roads), camera control,
  save data. Used identically by the editor playtest and exported games.
- **Block Studio** (Blocks workspace): GraphEdit canvas with zoom, minimap, snapping, drag-and-drop,
  copy/paste/duplicate, delete, tidy-up, undo/redo; searchable categorised palette; inline literal
  editors (numbers, booleans, text, vectors, colours, enums); live validation with red error
  outlines and a Problems list; Code view; Variables manager; live execution Trace and runtime errors
  during playtests; program list (new/rename/delete). Every new project gets a working starter
  program (race messages, final-lap warning, best-lap saving, results).
- Vehicle additions used by blocks: script/AI input overrides, engine power, top-speed override,
  nitro, manual gearbox (Q/E), neutral gear, collision events.

**Tests**: `test_blocks.gd` (8 tests: starter program, variables/loops/conditions, recursive
functions, infinite-loop safety, async waits, lists/text/broadcasts, validation errors, runtime error
isolation) and `test_race.gd` (full 3-car AI race with real physics; checkpoint order). Self-test:
Block Studio opens the starter program (22 blocks, no problems), add + undo a block, playtest starts
a race with 3 AI cars, countdown → racing.

**Known limits**: blocks are a node graph (Blueprint-like) rather than Scratch-style snapped stacks;
the trace shows blocks of all programs but highlights only those in the open program.

---

## Phase 4 — Vehicle System & Vehicle Studio ✅

**Implemented**
- Vehicle workspace: vehicle list, **Import Car Model** (GLB / glTF / FBX via Godot's runtime
  importers; files copied into `Assets/Vehicles`, never overwritten, recorded in
  `Assets/asset_index.json`), automatic wheel-mesh detection (FL/FR/RL/RR naming patterns) with wheel
  positions, radius and width fitted to the meshes, manual wheel-mesh mapping, model scale / offset /
  rotation, procedural body toggle.
- Tuning tabs: body and mass, centre of mass, handling profile, paint; wheel positions and
  steer/drive/handbrake flags; engine force, top speed, RPM range, final drive, reverse, automatic /
  manual gearbox, editable gear ratio list; suspension, damping, anti-roll, steering, tyre grip,
  brakes, aerodynamics; chase camera; procedural engine sound (cylinders, character, volume).
- 3D turntable preview with wheel markers; **Test Drive** pad with live telemetry (speed, gear, RPM,
  top speed, 0–100 km/h, wheels grounded).
- Runtime: imported models replace the procedural body; wheel meshes are re-parented onto the
  physics wheels so they spin and steer. Procedural engine voice (RPM + throttle) and tyre squeal.

**Tests**: `test_vehicle_model.gd` (GLB export → import without overwrite → asset index → runtime load →
4 wheels detected → model attached with wheel meshes on physics wheels → car drives > 30 km/h);
self-test: studio import + 4-wheel fit + test drive.

**Fixed during the phase**: roll resistance defaults were inverted for Godot's `wheel_roll_influence`
(cars could roll over) — now 0.7 (sim 0.45, kart 0.9).

---

## Phase 5 — Track Studio ✅

**Implemented** (Track workspace / Track tab)
- Seeded procedural circuit generator (size, control points, irregularity, width, elevation,
  banking) with automatic relaxation so no corner is tighter than 1.5× the road width; generates an
  editable road + start/finish + 3 sector checkpoints + 6-slot grid + guardrails, and puts the
  player car on the grid. Re-generating replaces the previous generated group (undoable).
- For any road: guardrails / concrete walls / tyre barriers that follow the road and are rebuilt
  whenever the road changes (collision included); evenly spaced sector checkpoints; starting grid;
  pit lane; dashed centre line; computed **racing line** (curvature smoothing clamped inside the
  road) shown in the viewport and used by the AI.
- Track statistics: length, corners, tightest radius. Drag road control points in the viewport (Phase 2).

**Tests**: `test_track.gd` — 5 seeds: valid, plausible length, min radius, racing line on the road and
not longer than the centreline; checkpoints/grid counts; guardrail mesh + collision hit by a ray at the
expected distance; an AI car completes a lap of a generated circuit with banking and guardrails.

**Fixed during the phase**: auto-placed checkpoints were rotated 90°; AI cars that flip or get stranded
now recover onto the racing line (standard racing-game recovery; normal driving never teleports).

---

## Phase 6 — Racing Systems ✅

**Implemented**
- RaceManager (built in Phase 3, extended): countdown, grid, checkpoint order, laps, lap and **sector
  times** (shown live in the HUD), live positions, finish, results, restart, and modular race rules:
  **circuit, sprint, time trial, elimination** (last car out each time the leader completes a lap).
- AI opponents on the same vehicle physics: racing-line following, corner speed planning from
  curvature and braking distance, difficulty and behaviour (cautious / balanced / aggressive),
  overtaking by lateral offset, stuck recovery, flip recovery.
- **Replays**: every race is recorded (30 Hz); "Watch Replay" in the results plays it back with a
  cinematic trackside camera that cuts along the track following the leader.
- Race configuration in the inspector's World section: enable, mode, laps, countdown, AI count,
  difficulty, behaviour, auto start.

**Tests**: `test_race.gd` — full 3-car AI race (positions, lap times, no teleporting), checkpoint
order, elimination and time-trial rules, replay record/playback accuracy.

---

## Phase 7 — Cinematic Graphics ✅

**Implemented**
- Presets Ultra Max (default) → Performance (Phase 1) plus: time of day (sun position, colour, sky
  energy, moonlight), weather (clear, cloudy, rain with GPU particles, storm with lightning, fog),
  **wet roads** (darker, glossy, clear-coat sheen), car **headlights** that switch on at night / in
  storms / fog, post-processing (depth of field, glow, contrast, saturation), **speed blur** (radial
  screen-space blur driven by speed and nitro — Godot has no built-in motion blur).
- The editor viewport previews time of day and weather live while editing.
- View › Performance Stats (draw calls, primitives, VRAM, RAM) and View › Benchmark Presets (FPS of
  the open scene at every preset).
- Removed a deprecated Godot call (SSR roughness quality).

**Tests**: `test_environment.gd` — night lighting + headlights, sunset colour, rain particles + wet
roads + drying, fog, DOF/glow/contrast/saturation from settings, speed blur strength vs speed.

---

## Phase 9 — Additional Tools & Asset Store ✅

**Implemented**
- **Asset Store** (Home › Asset Store to browse; editor "Store" workspace to download): Poly Haven CC0
  textures (871), HDRI skies (999) and models (522) with cached thumbnails, search, categories and
  1K/2K/4K; downloads are MD5-verified, never overwrite, and are recorded with author and licence in
  `Assets/asset_index.json`. One click applies a texture set to selected objects, an HDRI as the sky,
  or places a model prop (with collision). **Zino Built-in** section: material presets, a car for every
  physics profile, ready-made circuits and environment presets.
- **UI Studio** ("UI" workspace): live 1920×1080 HUD preview; drag elements or edit anchor, offset,
  scale and visibility (undoable); the same canvas designs **touch controls** (Phase 10).
- **Audio Studio**: sound library (import OGG/WAV/MP3, preview), scene music + loop, mixer
  (master/music/effects/engines), live engine-sound designer (cylinders, character, RPM, throttle).
- Camera modes: chase, close chase, hood, bumper, cockpit, orbit (+ trackside replay cameras).
- Materials accept texture maps; scenes accept HDRI skies; new `model` entity type for props.
- Bridge fix: the plugin switches back to the Zino scene if Godot opens another scene after start-up.

**Tests**: `test_tools.gd` (download planning incl. path-traversal rejection, filtering, textured
materials, HDRI sky, model prop collision, engine synthesis, touch and HUD layouts); self-test: UI Studio,
touch designer, Audio Studio, real catalogue load and a real MD5-verified download of `asphalt_02`
applied to a cube. Full headless suite: 54 tests passing.

---

## Phase 10 — iOS & Build Center ✅

**Implemented**
- **Build Center** ("Build" workspace): iOS (primary) and Windows targets; app name, version, bundle
  identifier, Apple Team ID (an identifier — no passwords or certificates are ever stored), device
  family; validation (export templates present, version/bundle/team formats, Mobile renderer override,
  ETC2/ASTC compression, features unavailable on the iOS Mobile renderer, very large textures,
  memory estimate, missing asset references, start scene); generates `export_presets.cfg` and a
  1024×1024 PNG app icon; runs Godot's official exporter on a background thread with a live log and an
  artifacts list. iOS export on Windows produces the **Xcode project**; the generated
  **GitHub Actions workflow** (`.github/workflows/zino-ios.yml` + `ExportOptions.plist`) compiles,
  signs (from repository secrets) and uploads the IPA on a macOS runner.
- **Touch controls** (runtime + UI Studio "Touch Controls" designer): arrows / steering wheel / tilt
  (gyroscope) steering, accelerator, brake, handbrake, nitro, gear shift, camera, pause; repositioning,
  resizing, opacity, sensitivity, automatic/manual gearbox, auto-accelerate; anchored for any aspect ratio;
  shown automatically on touch devices.
- Exported games load imported audio resources (raw files are not packaged).

**Tests**: `test_build.gd` — validation rules, export presets without secrets, **real Windows export
whose .exe was launched and ran the game**, **real iOS Xcode-project export**, CI workflow.
`test_tools.gd` covers touch layouts. Not testable here: compiling/signing the IPA (needs macOS + Apple
account) and running on a physical iPhone.

---

## Phase 11 — Release ✅

**Implemented**
- Version **1.0.0** (engine, project dependency, Windows file version).
- `ZinoEditor/export_presets.cfg` + `tools/build-release.ps1` → `builds/ZinoEditor/`: `Zino.exe`
  (105 MB, Windows), `engine/addons/` (runtime + Godot bridge copied into every new project), `docs/`,
  `Samples/` (Circuit Race, Drift Sunset, Open World, Kart Cup) and `zino_config.json` (path of the
  Godot 4.7 editor used for Godot integration and exports; changeable in Home › Settings).
- Release excludes tests and tools; the app has no dependency on test code.
- Test scratch space moved into the repository (`.test_tmp/`, git-ignored) so exports never fill C:.

**Verified**: full headless suite 56/56 (4,453 checks); the **released Zino.exe** opens on the Home screen
and passes the windowed self-test (project creation from the shipped engine add-ons, editor, viewport
picking, undo/redo, duplicate, hierarchy, Block Studio). Found and fixed during release testing: the
self-test referenced test-only code, which broke the packaged build.

**Limits**: no installer (portable folder); compiling/signing the iOS IPA needs macOS and an Apple
Developer account (Xcode project export and CI workflow are ready).

## Easy mode (v1.1.0) ✅

**Request:** "it feels very hard to make a game … make it easier but still I can make a professional game."

**What:** Make a Game wizard (Home), Simple mode by default with an Advanced toggle, Game tab with
plain-language settings, 10 block recipes, the Coach checklist, AI grid-slot start fix, camera start view.

**Files:** `core/zino_quick_game.gd`, `app/home/make_game_wizard.gd`, `app/home/home_screen.gd`,
`app/editor/game_panel.gd`, `app/editor/coach.gd`, `app/editor/editor_screen.gd`,
`app/blocks/block_recipes.gd`, `app/blocks/block_studio.gd`, `addons/zino_runtime/game/zino_game_context.gd`,
`addons/zino_runtime/vehicles/zino_chase_camera.gd`.

**Decisions:** Simple mode hides tools but never changes data, so a game made in Simple mode is a normal
professional project in Advanced mode. Recipes insert ordinary blocks (no hidden magic) as one undo step.
The Coach detects progress from real state (play mode, car colour, race settings, block count, Publish shown).

**Tests:** `test_quick_game.gd` (every game type creates a valid project; a quick game races with AI),
`test_recipes.gd` (every recipe compiles, links hit real inputs, all recipes combine with the starter
program, a recipe runs in the interpreter). Full suite 61 tests / 4,670 checks pass. Windowed self-test
adds: wizard → Simple mode → Game tab + Coach → laps edit + undo → recipe → Publish → play.

**Limits:** the Coach has 5 fixed steps; recipes are inserted with default values (edit them afterwards).
