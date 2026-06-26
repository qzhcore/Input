# InputSystem

`InputSystem` is a configurable, Rojo-ready Luau wrapper for Roblox's Input Action System. The package currently focuses on two production-critical systems:

- A stack-based `InputContext` controller for enabling the correct action layout at the right priority.
- A VR input translation layer that normalizes controller and HMD data into a common payload shape.

The namespace is intentionally temporary. The public table is called `InputSystem` until the project gets a permanent package name.

## Status

This repository is an early open-source foundation. The API is designed to stay small while Roblox continues expanding the new Input Action System.

Supported focus areas:

- Keyboard and mouse friendly context architecture
- Gamepad and console-friendly action priority handling
- Mobile touch-zone documentation hooks
- VR trigger, thumbstick, hand, and HMD telemetry
- Strict Luau types
- Rojo, Wally, Selene, StyLua, and CI-ready project layout

## Architecture

The package is intentionally split into focused modules:

- `init.lua`: stable public API and composition root.
- `ContextStack.lua`: native `InputContext` stack activation and priority control.
- `ValueNormalizer.lua`: shared math transforms for `Direction1D`, `Direction2D`, and `Direction3D`.
- `Types.lua`: exported type contracts.
- `Devices/KeyboardMouse.lua`: desktop capability detection.
- `Devices/Mobile.lua`: mobile capability detection and touch-zone config access.
- `Devices/Console.lua`: gamepad and console capability detection.
- `Devices/VR.lua`: HMD and hand-controller telemetry translation.

This keeps platform-specific logic isolated while preserving one clean API for game code.

## Project Structure

```text
InputSystem/
|-- .github/
|   `-- workflows/
|       `-- ci.yml
|-- lib/
|   |-- Devices/
|   |   |-- Console.lua
|   |   |-- KeyboardMouse.lua
|   |   |-- Mobile.lua
|   |   `-- VR.lua
|   |-- ContextStack.lua
|   |-- InputStates.lua
|   |-- Logger.lua
|   |-- Types.lua
|   |-- ValueNormalizer.lua
|   `-- init.lua
|-- tests/
|   `-- InputSystem.spec.lua
|-- default.project.json
|-- foreman.toml
|-- Linking.lua
|-- LICENSE
|-- package.json
|-- pack.project.json
|-- README.md
|-- selene.toml
|-- stylua.toml
|-- testing.project.json
|-- types/
|   `-- index.d.ts
`-- wally.toml
```

## Installation

### With Wally

Add the package to your game's `wally.toml` after the first tagged release is published:

```toml
[dependencies]
InputSystem = "qzhcore/input@0.1.0"
```

Then install packages:

```powershell
wally install
```

The current repository includes its own [wally.toml](wally.toml) so it can be published cleanly when the API is ready.

### With roblox-ts

roblox-ts users can consume the package through a wrapper package or direct repository dependency. Type declarations live in [types/index.d.ts](types/index.d.ts), and package metadata lives in [package.json](package.json).

```ts
import InputSystem = require("@qzhcore/input");

const system = InputSystem.new({
	DefaultAnalogDeadZone: 0.12,
});

system.PushContext("Gameplay", InputSystem.Priority.Gameplay);
```

This repository still ships Luau as the runtime source. Your roblox-ts entry/init script can require the synced module from `ReplicatedStorage` or wrap the package API in TypeScript.

### With Rojo

Use [default.project.json](default.project.json) to sync the module into `ReplicatedStorage.InputSystem`:

```powershell
rojo serve default.project.json
```

In Roblox Studio, connect Rojo and require the module:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InputSystem = require(ReplicatedStorage.InputSystem)
```

## Quick Start

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputSystem = require(ReplicatedStorage.InputSystem)

local system = InputSystem.new({
	ContextParent = Players.LocalPlayer:WaitForChild("PlayerScripts"),
	DefaultAnalogDeadZone = 0.12,
	DefaultTrackpadDeadZone = 0.18,
	ContextPriorityNotes = {
		Gameplay = "Base movement context. Keep lower than UI overlays.",
		Menu = "Overrides gameplay so menu navigation sinks movement input.",
	},
	MobileTouchZones = {
		PrimaryStick = {
			ZoneId = "StarterGui.Controls.LeftStick",
			LinkedActionName = "Move",
			Notes = "Manual UI link: custom mobile left stick feeds the Move InputAction.",
		},
	},
	ManualActionLinks = {
		Interact = "StarterGui.Controls.InteractButton",
	},
	Logger = function(level, message, data)
		print(level, message, data)
	end,
})

system:PushContext("Gameplay", InputSystem.Priority.Gameplay)
system:PushContext("Menu", InputSystem.Priority.Menu)

local popped = system:PopContext()
local vrSnapshot = system:GetVRSnapshot()

system:Destroy()
```

## Public API

### `InputSystem.new(config)`

Creates a new controller.

Important config fields:

- `ContextParent`: where native `InputContext` instances are searched for or created.
- `CreateMissingContexts`: creates missing native `InputContext` instances when true or omitted.
- `DefaultAnalogDeadZone`: default thumbstick dead zone.
- `DefaultTrackpadDeadZone`: default trackpad dead zone.
- `Thresholds`: trigger, thumbstick, trackpad, and hand-delta tuning.
- `MobileTouchZones`: documents custom mobile UI zones manually linked to `InputAction` objects.
- `ManualActionLinks`: documents non-script design assets that feed an action.
- `ContextPriorityNotes`: explains why a context priority exists.
- `Logger`: receives safety logs and diagnostics.

### `system:PushContext(contextName, priority)`

Pushes an input context onto the stack and activates it if it is the highest-priority context.

```lua
system:PushContext("Gameplay", InputSystem.Priority.Gameplay)
system:PushContext("Vehicle", InputSystem.Priority.Vehicle)
```

### `system:PopContext()`

Removes the current top context and reactivates the next valid context.

```lua
local poppedContext = system:PopContext()
```

### `system:SetContextActive(contextName, active)`

Manually enables or disables a context without needing direct access to the native `InputContext`.

```lua
system:SetContextActive("Menu", true)
system:SetContextActive("Menu", false)
```

### `system:RegisterContext(contextName, context, priority)`

Registers an existing native `InputContext` instance.

```lua
system:RegisterContext("Gameplay", playerScripts.InputContexts.Gameplay, InputSystem.Priority.Gameplay)
```

### `system:NormalizeActionValue(actionKind, value, deadZone)`

Normalizes `Direction1D`, `Direction2D`, or `Direction3D` math before passing values to character, camera, or vehicle controllers.

```lua
local payload = system:NormalizeActionValue("Direction2D", moveVector, 0.12)
```

### `system:GetVRSnapshot()`

Returns the latest HMD, left-hand, and right-hand telemetry.

```lua
local snapshot = system:GetVRSnapshot()
print(snapshot.Enabled, snapshot.LeftHand.Trigger.Value)
```

### `system:Destroy()`

Disconnects listeners, disables contexts, and cleans up contexts created by the module.

## Input Payload

All normalized values use this exported type:

```lua
export type InputPayload = {
	State: Enum.InputActionState,
	Value: any,
	Delta: Vector3?,
}
```

## Context Priority Defaults

`InputSystem.Priority` includes documented defaults:

- `Gameplay = 100`
- `Vehicle = 200`
- `Menu = 500`
- `Modal = 900`
- `Debug = 1000`

Keep project-specific priority reasons in `ContextPriorityNotes`. This is important because priority values decide which action layout overrides or sinks input from another layout.

## Mobile And Custom UI

Custom mobile controls and UI buttons often live in `StarterGui`, Figma exports, or hand-authored interface modules. Because those assets exist outside this raw module, document each manual connection:

```lua
MobileTouchZones = {
	PrimaryStick = {
		ZoneId = "StarterGui.Controls.LeftStick",
		LinkedActionName = "Move",
		Notes = "Manual UI link: custom mobile stick feeds Move.",
	},
}
```

## DevOps

Install pinned tooling with Foreman:

```powershell
foreman install
```

Run local checks:

```powershell
rojo sourcemap default.project.json --output sourcemap.json
selene lib
stylua --check lib Linking.lua
```

Build local artifacts:

```powershell
rojo build testing.project.json --output build/InputSystemTesting.rbxlx
rojo build pack.project.json --output build/InputSystem.rbxm
```

The GitHub Actions workflow in [.github/workflows/ci.yml](.github/workflows/ci.yml) follows a dev/main pipeline:

- Pull requests and pushes run `quality`: Rojo sourcemap, Selene, StyLua, and roblox-ts declaration validation.
- Pushes to `dev` build a testing place artifact.
- Pushes to `main` build a distributable `.rbxm`, upload it as an artifact, optionally publish to Wally when `WALLY_AUTH_TOKEN` exists, and create a draft GitHub Release.

Development policy

- Do active work on `dev`.
- Open pull requests from `dev` or feature branches into `main`.
- Bump `version` in [wally.toml](wally.toml) before production-ready `main` releases.
- Keep `main` production-ready.

Recommended branch protection for `main`:

- Require pull request reviews before merge.
- Require the `quality` CI job to pass.
- Require branches to be up to date before merge.
- Block force pushes.
- Block branch deletion.

## Contributing

Friends and contributors should use this flow:

1. Install Foreman and run `foreman install`.
2. Branch from `dev`.
3. Make focused changes in `lib`.
4. Run `selene lib` and `stylua --check lib Linking.lua`.
5. Build with `rojo build pack.project.json --output build/InputSystem.rbxm` when changing package layout.
6. Open a pull request.
7. Merge to `main` only after CI is green and the Wally version is bumped for releases.


## Roadmap

- Runtime player-facing key rebinding once Roblox exposes stable IAS support.
- More device-specific adapters for mobile, console, and desktop action payloads.
- Example place with real `InputContext` and `InputAction` assets.
- Test harnesses for context-stack ordering and analog threshold behavior.
- Do a full release for Input.
