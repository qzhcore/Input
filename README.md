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

## Project Structure

```text
InputSystem/
|-- .github/
|   `-- workflows/
|       `-- ci.yml
|-- src/
|   `-- InputSystem.lua
|-- aftman.toml
|-- default.project.json
|-- LICENSE
|-- README.md
|-- selene.toml
|-- stylua.toml
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

Install pinned tooling with Aftman:

```powershell
aftman install
```

Run local checks:

```powershell
rojo sourcemap default.project.json --output sourcemap.json
selene src
stylua --check src
```

The GitHub Actions workflow in [.github/workflows/ci.yml](.github/workflows/ci.yml) runs the same checks on pull requests and pushes to `main`.

Recommended branch protection for `main`:

- Require pull request reviews before merge.
- Require the `luau` CI job to pass.
- Require branches to be up to date before merge.
- Block force pushes.
- Block branch deletion.

## Contributing

Friends and contributors should use this flow:

1. Ask for collaborator access or fork the repository.
2. Create a branch from `main`.
3. Make focused changes.
4. Run `selene src` and `stylua --check src`.
5. Open a pull request into `main`.
6. Wait for CI and review before merge.

Use `Write` access for trusted contributors who need to push branches directly. Use forks for new external contributors.

## Roadmap

- Runtime player-facing key rebinding once Roblox exposes stable IAS support.
- More device-specific adapters for mobile, console, and desktop action payloads.
- Example place with real `InputContext` and `InputAction` assets.
- Test harnesses for context-stack ordering and analog threshold behavior.
