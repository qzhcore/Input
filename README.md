# InputSystem

`InputSystem` is a placeholder namespace for a production-grade wrapper around Roblox's Input Action System. The current package focuses on two core layers:

- A stack-based `InputContext` controller for priority-driven action layout activation.
- A VR hardware translation layer that normalizes controller and HMD telemetry into a common payload shape.

## Rojo Layout

```text
InputSystem/
├─ aftman.toml
├─ default.project.json
├─ README.md
├─ selene.toml
├─ stylua.toml
└─ src/
   └─ InputSystem.lua
```

## Public API

```lua
local InputSystem = require(ReplicatedStorage.InputSystem)

local system = InputSystem.new({
	ContextParent = Players.LocalPlayer:WaitForChild("PlayerScripts"),
	DefaultAnalogDeadZone = 0.12,
	MobileTouchZones = {
		PrimaryStick = {
			ZoneId = "TouchZone/PrimaryStick",
			LinkedActionName = "Move",
			Notes = "Manual UI link: StarterGui.Controls.LeftStick -> Move InputAction",
		},
	},
})

system:PushContext("Gameplay", InputSystem.Priority.Gameplay)
system:SetContextActive("Menu", false)
local popped = system:PopContext()

local snapshot = system:GetVRSnapshot()
local state = system:GetContextStack()
system:Destroy()
```

## CI Notes

Suggested checks for a GitHub Actions pipeline:

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]

jobs:
  luau:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ok-nick/setup-aftman@v0.4.2
      - run: rojo sourcemap default.project.json --output sourcemap.json
      - run: selene src
      - run: stylua --check src
```

## Repository Access On GitHub

1. Push this folder to a GitHub repository.
2. Open the repository on GitHub.
3. Go to `Settings` -> `Collaborators and teams`.
4. Select `Add people` or add a team if the repo belongs to an organization.
5. Choose the correct role:
   - `Read` for testers and reviewers.
   - `Triage` for issue management.
   - `Write` for contributors who need branch pushes.
   - `Maintain` for release managers.
   - `Admin` only for trusted maintainers who can change repo settings.
6. For open source, also add a `LICENSE`, branch protection on `main`, and required CI checks before merge.
