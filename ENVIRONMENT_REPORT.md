# Zino Racing Engine — Development Environment Report

Inspected: 2026-11-23

## Hardware

| Item | Value | Impact |
|---|---|---|
| OS | Windows 11 Home Single Language 10.0.26200, 64-bit | Supported by Godot 4 |
| CPU | Intel Core i5-1135G7, 4 cores / 8 threads, 2.4 GHz | Fine for Godot; shader compilation on first launch takes a little while |
| RAM | 11.7 GB total, ~2 GB free at inspection | Low. The Zino Editor keeps one 3D world and loads assets lazily |
| GPU | Intel Iris Xe (integrated, shared memory, driver 31.0.101.4502), Vulkan capable | Runs Forward+; the **Ultra Max** preset will be slow (expect low frame rates) — use the viewport preview quality setting while editing |
| C: | 7.2 GB free | **Critical.** Nothing in this project is stored on C: |
| D: | 243 GB free | OK |
| F: | 733 GB free | Repository, Godot and all projects live here |

## Software

| Tool | Status |
|---|---|
| **Godot Engine** | **4.7.2-stable (official)** at `F:\Godot\Godot_v4.7.2-stable_win64.exe` (+ `_console.exe` for headless/CLI use). Downloaded from the official GitHub release; SHA-512 verified |
| Godot export templates | Not installed yet (~1.2 GB). Needed only for exporting games (Phase 10/11); will ask before downloading |
| Git | 2.55.0 |
| Node.js / Python | 24.18.1 / 3.12.10 (not used by the engine) |
| .NET | Runtimes only (not needed: Zino uses GDScript, not C#) |
| Visual Studio / C++ compiler | Not installed. Not needed for GDScript; needed only if native GDExtension (C++) modules are added later |
| Unity 6000.0.85f2 | Installed at `F:\6000.0.85f2`, **not used** (project switched to Godot) |
| Unreal Engine | Not installed, not used |

## Engine decision history

1. Original brief: Unreal Engine 5 — not installed, ~80 GB with Visual Studio, poor fit for Iris Xe / 12 GB RAM / 7 GB free on C:.
2. Unity 6 was started and then dropped at the user's request.
3. **Final: Godot 4.7.2.** Lightweight, MIT-licensed, Vulkan Forward+ renderer for desktop, official iOS export, built-in vehicle physics (`VehicleBody3D`), WebSocket networking and editor plugins — everything Phase 1 needs, and all of it testable on this machine.

## Still required later

- **iOS export:** a Mac with Xcode (local, remote, or a hosted macOS CI runner) and an Apple Developer account. Godot exports the Xcode project on Windows; compiling and signing happen on macOS. Signing credentials are never stored in the repository.
- **Godot export templates** (~1.2 GB) for any export.

## Housekeeping note

`F:\UnityCache` (1.6 MB) was created during the short Unity attempt. The tool sandbox would not let me delete it; it is safe to delete by hand.
