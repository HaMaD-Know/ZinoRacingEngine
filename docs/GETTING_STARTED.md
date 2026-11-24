# Getting Started with Zino Racing Engine

## Run the Zino Editor
```powershell
.\tools\run-editor.ps1
```
(or `F:\Godot\Godot_v4.7.2-stable_win64.exe --path ZinoEditor`)

## The easy way: Make a Game (recommended)
1. On the Home screen press **✨ Make a Game**.
2. Pick a game type, a car and its colour, a track, the time and weather, then a name.
3. **Create & Play** — your game opens ready to drive. Press **▶ Play your game**.
4. Change things on the **Game** tab (right side): laps, opponents, skill, colour, handling, camera,
   time of day, weather. Everything can be undone (Ctrl+Z).
5. Add rules from **Logic › ✨ Recipes…** (boost on F, final lap alert, lap timer, rain from lap 2,
   save best lap, score, victory message…). Each recipe is normal blocks you can change.
6. Export from **Publish** (iPhone / Windows).

The **Coach** in the corner shows these steps and ticks them off; *Show me* takes you there.
Hide it with *Hide*, bring it back with *View › Show Coach*.

### Simple and Advanced mode
New users start in **Simple mode**. Press **Advanced** (top right, or *View › Advanced Mode*) for every
professional tool: World, UI and Audio studios, gizmo space and snapping, the console and more.
Both modes edit the same game — you can switch at any time.

## Zino on iPhone / iPad
Build the app on GitHub: **Actions › Zino editor iOS build › Run workflow**, then download the
`ZinoRacingEngine-ipa` artifact. Without Apple secrets the `.ipa` is unsigned: install it with a
sideloading tool (for example Sideloadly with your Apple ID; free Apple IDs must reinstall every 7 days).
On iPad: drag one finger to orbit, tap to select, pinch to zoom, drag two fingers to pan. Your projects
appear in the Files app under Zino. Publishing games needs Zino on Windows/Mac or the game's own
GitHub workflow (Publish › Create GitHub Actions iOS workflow).

## Create a project the advanced way
1. **New Project (advanced)…** on the Home screen (or pick a template card).
2. Choose a name, a folder, a game type (Circuit, Drift, Drag, Kart, Open World…), the graphics
   preset (Ultra Max by default), default vehicle physics, environment and platforms.
3. **Create Project** — Zino writes the project and opens the editor with a ready circuit,
   a car, a chase camera, a sun, start/finish line and checkpoints.

## Edit
| Action | How |
|---|---|
| Select | Left-click in the viewport or the hierarchy; Ctrl/Shift-click to add |
| Move / Rotate / Scale | W / E / R (Q = select only), drag the gizmo handles; hold Shift for fine moves |
| Snap | Toolbar **Snap** (hold Ctrl to invert while dragging); steps in Home › Settings |
| Camera | RMB drag orbit · MMB or Shift+RMB pan · wheel zoom · RMB + WASD/QE fly · F frame |
| Views | Viewport button or View menu: Perspective, Top, Front, Side |
| Add objects | **Add** tab on the left, or the Scene / Racing menus |
| Undo / Redo | Ctrl+Z / Ctrl+Y |
| Duplicate / Delete / Rename | Ctrl+D / Delete / F2 |
| Reparent | Drag items in the hierarchy |
| Save | Ctrl+S (autosave runs every 60 s; crash recovery on next open) |

## Drive
Press **Play** (F5). W/S throttle & brake (S reverses when stopped), A/D steer, Space handbrake,
R reset, C camera mode. **Stop** (F8) returns to editing — play never changes your scene.

## Graphics on a laptop
Ultra Max (SDFGI, SSR, SSIL, volumetric fog, 8K shadows, MSAA 4x + TAA + SMAA) is the default for
your game. On integrated GPUs set the toolbar **Preview** to *Balanced* while editing — this only
changes the editor viewport, never your game's output quality (Project › Project Settings).
Measure your machine: `F:\Godot\Godot_v4.7.2-stable_win64_console.exe --path ZinoEditor -s res://tools/benchmark_presets.gd`.

## Work in the Godot editor too
**Tools › Open in Godot Editor** launches Godot on your project. The Zino Bridge plugin connects
automatically (status pill turns green), builds your scene as `Worlds/Main.tscn`, and mirrors
edits both ways. Use it for scripts, shaders and anything Zino does not cover yet.

## Tests
```powershell
.\tools\run-tests.ps1
```
