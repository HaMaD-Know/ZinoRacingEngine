# Zino Racing Engine — Architecture

Zino is a racing-game development environment built on **Godot 4.7** (MIT licence). It is a
standalone desktop application (the **Zino Editor**) plus a shared racing **runtime** that
every game made with Zino ships, plus a **Godot editor plugin** for advanced work. They talk
over a local, authenticated WebSocket bridge.

## 1. Why Godot (engine decision)

The brief asked for Unreal Engine 5. On this machine (Iris Xe, 12 GB RAM, 7 GB free on C:, no
Visual Studio) UE5 was not installed and not practical. Unity 6 was started and dropped at the
user's request. Godot 4.7 was chosen because it fits the hardware, needs no C++ toolchain for
GDScript, has official iOS export, built-in `VehicleBody3D` raycast vehicles, Vulkan Forward+
rendering (SDFGI, SSR, SSIL, volumetric fog), WebSockets and editor plugins — so every layer
of the hybrid architecture can be built **and tested** here. See ENVIRONMENT_REPORT.md.

| Original brief (UE5) | Zino on Godot |
|---|---|
| Custom desktop app + UE editor plugin | Zino Editor (a Godot application) + Zino Bridge (Godot `EditorPlugin`) |
| Chaos Vehicles + extensions | `VehicleBody3D` + `ZinoVehicle` extensions (gearbox, RPM, aero, speed-sensitive steering) |
| Blueprints | GDScript / Godot editor (opened from Zino via the bridge) |
| C++ | GDExtension (needs a C++ compiler; planned, not set up) |
| Lumen / Nanite | SDFGI / SSIL / SSR / volumetric fog (Forward+); Mobile renderer on iOS |
| UE iOS pipeline | Godot iOS export → Xcode on macOS |

## 2. Components

```
ZinoRacingEngine/
  ZinoEditor/                      Godot project = the Zino Editor application
    app/                           Editor UI (home, wizard, editor screen, viewport, panels)
    core/                          Editor-only logic (undo/redo, project service, bridge server)
    addons/zino_runtime/           Shared runtime — copied into every Zino project
      core/   format, entities, templates, scene builder, input
      rendering/ graphics presets, PBR material presets
      track/  road spline + mesh + collision generation
      vehicles/ ZinoVehicle (VehicleBody3D), chase camera
      bridge/ ZinoProtocol (shared protocol definition + validation)
      game/   zino_game.tscn — runtime entry point of exported games
    addons/zino_bridge/            Godot editor plugin — copied into every Zino project
    tests/                         Headless test suite (run_tests.gd + test_*.gd)
    tools/                         benchmark_presets.gd
  docs/                            Getting started, protocol, project format
  tools/                           PowerShell launch / test scripts
```

### A. Zino Editor (desktop application)
A Godot application (`ZinoEditor/project.godot`, main scene `app/main.tscn`). UI is built in
code (`app/`), theme in `zino_theme.gd`. Screens:
- **Home** (`home/home_screen.gd`): Home, Projects, Templates, Documentation, Settings.
- **New Project Wizard** (`home/new_project_dialog.gd`): name, location, game type (8 templates),
  graphics preset, default vehicle profile, starting environment, target platforms.
- **Editor** (`editor/editor_screen.gd`): menu bar (File … Help), toolbar, hierarchy, add palette,
  3D viewport, inspector, console / bridge log / content browser, status bar.

`editor/editor_session.gd` owns the open project: scene document, `ZinoCommandStack`
(undo/redo), selection, play mode, autosave, and the bridge server.

### B. Zino Bridge (Godot editor plugin)
`addons/zino_bridge/` in each project. When a Zino project is opened in the Godot editor, the
plugin reads `Cache/zino_bridge_session.json`, connects to the Zino Editor and executes
validated commands against the Godot editor (build the scene as `Worlds/<scene>.tscn`, create /
update / delete / select / transform objects, assign materials, import assets, save, play,
stop). Godot-side selection and transform edits are sent back as events. Protocol: docs/PROTOCOL.md.

### C. Godot runtime
Rendering (Forward+ on desktop, Mobile on iOS), physics (Godot Physics, 120 Hz), audio, input.

### D. Zino runtime framework (`addons/zino_runtime`)
- `ZinoFormat` — scene/project format, ids, validation, atomic file IO.
- `ZinoSceneBuilder` — turns a scene document into Godot nodes; **the same builder** is used by
  the editor viewport (edit mode), the in-editor playtest and exported games (play mode) and the
  Godot editor plugin (author mode). Incremental updates via change sets.
- `ZinoVehicle`, `ZinoChaseCamera`, `ZinoRoadBuilder`, `ZinoGraphics`, `ZinoMaterials`, `ZinoInput`.

## 3. Data flow

```
 user edit ─► ZinoSceneEdits ─► ZinoCommandStack.execute ─► change set
                                       │
          ┌────────────────────────────┼─────────────────────────────┐
          ▼                            ▼                             ▼
  viewport builder.apply_changes   hierarchy / inspector       bridge: CREATE/UPDATE/DELETE_OBJECT
                                                                     │  (Godot editor plugin)
                                                                     ▼
                                                            Godot scene in the editor
  Godot-side edits ─► TRANSFORM_CHANGED / SELECTION_CHANGED events ─► executed as commands
```

The Zino scene file (`Scenes/*.zscene`, JSON) is the **source of truth**. Godot `.tscn` files in
`Worlds/` are generated from it by the bridge for advanced editing.

## 4. Key decisions

- **One builder, many modes.** Editor preview, playtest, exported game and Godot authoring all
  build nodes with `ZinoSceneBuilder`, so what you see is what ships.
- **Snapshot commands.** Each edit stores deep copies of affected entities before/after plus list
  index. Simple, generic, exact undo for every operation; no per-operation inverse code.
- **Dictionary entities.** Entities are JSON-native Dictionaries; unknown keys from newer Zino
  versions survive round trips. Validation (`ZinoFormat.validate_scene`) guards every load and save.
- **Atomic saves with backup.** `.tmp` write + rename, previous version kept as `.bak`; autosave to
  `Cache/autosave/` with recovery on open.
- **Security of the bridge.** Loopback only, random port, 256-bit per-session token in a file only
  local processes can read, 5 s hello timeout, one client, size caps, command whitelist and
  payload validation in the plugin, asset paths confined to `Assets/`. No arbitrary code execution.
- **Graphics.** User-controlled presets (`ZinoGraphics`), default **Ultra Max**. Editor preview
  and game output are stored separately in `project.zino`; nothing is downgraded automatically;
  missing renderer features are reported (`capability_warnings`). Source assets are never modified.
- **Coordinates.** Zino scene space = Godot space: metres, +Y up, −Z forward, Euler degrees (YXZ).
  `VehicleBody3D` drives along +Z, so `ZinoVehicle.ENGINE_FORWARD_SIGN = -1` (verified by test).

## 5. Known limits of the architecture (current)
- Single scene per project in the editor UI (format supports many).
- No GDExtension/C++ layer yet; vehicle model is `VehicleBody3D`-based (not a tyre-model sim).
- iOS export requires macOS + Xcode; not implemented yet (Phase 10).
