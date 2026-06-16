--!strict

--[[
	InputSystem

	Placeholder namespace for a production-grade wrapper around Roblox's Input Action System.

	Core systems in this module:
	1. Context stack controller for InputContext activation and priority management.
	2. VR spatial hardware translation layer for controllers and HMD telemetry.

	Architecture notes for open-source maintainers:
	- Hardcoded priorities below are documented defaults, not game rules. Keep project-specific
	  override decisions close to the InputContext definitions that depend on them.
	- Manual UI links, including custom mobile touch zones, must be declared in Config.MobileTouchZones.
	  These assets live outside this raw script and cannot be inferred safely at runtime.
	- Safety logs are emitted through Config.Logger when math transformations normalize Direction1D,
	  Direction2D, or Direction3D values before character-controller handoff.
	- TODO(runtime-rebinding): When Roblox exposes custom player-facing runtime key rebinding for IAS,
	  add a user binding profile layer between InputAction lookup and InputBinding mutation.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

export type InputPayload = {
	State: Enum.InputActionState,
	Value: any,
	Delta: Vector3?,
}

export type LogLevel = "Debug" | "Info" | "Warning" | "Error"
export type Logger = (level: LogLevel, message: string, data: { [string]: any }?) -> ()

export type TouchZoneLink = {
	ZoneId: string,
	LinkedActionName: string,
	Notes: string,
}

export type AnalogThresholds = {
	TriggerPressed: number?,
	TriggerReleased: number?,
	ThumbstickDeadZone: number?,
	TrackpadDeadZone: number?,
	HandDeltaEpsilon: number?,
}

export type ContextRecord = {
	Name: string,
	Priority: number,
	Active: boolean,
	Context: Instance?,
	CreatedByInputSystem: boolean,
}

export type VRHandTelemetry = {
	Hand: Enum.UserCFrame,
	CFrame: CFrame,
	PreviousCFrame: CFrame?,
	Position: Vector3,
	Delta: Vector3,
	Trigger: InputPayload,
	Thumbstick: InputPayload,
	LastUpdated: number,
}

export type VRSnapshot = {
	Enabled: boolean,
	HMD: InputPayload,
	LeftHand: VRHandTelemetry,
	RightHand: VRHandTelemetry,
}

export type Config = {
	ContextParent: Instance?,
	CreateMissingContexts: boolean?,
	DeactivateMissingContexts: boolean?,
	DefaultAnalogDeadZone: number?,
	DefaultTrackpadDeadZone: number?,
	Thresholds: AnalogThresholds?,
	Logger: Logger?,
	MobileTouchZones: { [string]: TouchZoneLink }?,
	ContextPriorityNotes: { [string]: string }?,
	ManualActionLinks: { [string]: string }?,
}

type StackEntry = {
	Name: string,
	Priority: number,
	Token: number,
}

type ConnectionMap = {
	InputBegan: RBXScriptConnection?,
	InputChanged: RBXScriptConnection?,
	InputEnded: RBXScriptConnection?,
}

type InputSystemPrivate = {
	_config: Config,
	_contexts: { [string]: ContextRecord },
	_stack: { StackEntry },
	_nextToken: number,
	_connections: ConnectionMap,
	_vrEnabled: boolean,
	_hmd: InputPayload,
	_leftHand: VRHandTelemetry,
	_rightHand: VRHandTelemetry,
	_lastHmdCFrame: CFrame?,
	_destroyed: boolean,
}

export type InputSystem = typeof(setmetatable({} :: InputSystemPrivate, {} :: any)) & {
	PushContext: (self: InputSystem, contextName: string, priority: number) -> ContextRecord,
	PopContext: (self: InputSystem) -> ContextRecord?,
	SetContextActive: (self: InputSystem, contextName: string, active: boolean) -> ContextRecord,
	RegisterContext: (
		self: InputSystem,
		contextName: string,
		context: Instance,
		priority: number?
	) -> ContextRecord,
	GetContext: (self: InputSystem, contextName: string) -> ContextRecord?,
	GetContextStack: (self: InputSystem) -> { ContextRecord },
	GetVRSnapshot: (self: InputSystem) -> VRSnapshot,
	NormalizeActionValue: (
		self: InputSystem,
		actionKind: "Direction1D" | "Direction2D" | "Direction3D",
		value: any,
		deadZone: number?
	) -> InputPayload,
	Destroy: (self: InputSystem) -> (),
}

local InputSystem = {}
InputSystem.__index = InputSystem

InputSystem.Priority = table.freeze({
	-- NOTE(priority): Gameplay is intentionally low. It should yield to overlays and modals.
	Gameplay = 100,
	-- NOTE(priority): Vehicle overrides Gameplay so movement and camera actions sink cleanly.
	Vehicle = 200,
	-- NOTE(priority): Menu overrides world controls and prevents accidental character movement.
	Menu = 500,
	-- NOTE(priority): Modal is reserved for blocking dialogs and critical confirmation flows.
	Modal = 900,
	-- NOTE(priority): Debug is highest so internal tools can inspect or capture inputs safely.
	Debug = 1000,
})

local DEFAULT_TRIGGER_PRESSED = 0.55
local DEFAULT_TRIGGER_RELEASED = 0.35
local DEFAULT_ANALOG_DEAD_ZONE = 0.12
local DEFAULT_TRACKPAD_DEAD_ZONE = 0.18
local DEFAULT_HAND_DELTA_EPSILON = 0.0001

local function defaultLogger(level: LogLevel, message: string, data: { [string]: any }?): ()
	if level == "Warning" or level == "Error" then
		warn(string.format("[InputSystem/%s] %s", level, message), data)
	end
end

local function clonePayload(payload: InputPayload): InputPayload
	return {
		State = payload.State,
		Value = payload.Value,
		Delta = payload.Delta,
	}
end

local function makePayload(
	state: Enum.InputActionState,
	value: any,
	delta: Vector3?
): InputPayload
	return {
		State = state,
		Value = value,
		Delta = delta,
	}
end

local function getStateFromMagnitude(magnitude: number, pressedThreshold: number): Enum.InputActionState
	if magnitude >= pressedThreshold then
		return Enum.InputActionState.Begin
	end

	return Enum.InputActionState.End
end

local function applyDeadZone(value: Vector2, deadZone: number): Vector2
	local magnitude = value.Magnitude

	-- EDGE CASE(dead-zone): Analog sticks and trackpads can report tiny non-zero values while idle.
	-- We clamp them to zero to prevent camera drift and unintended character movement.
	if magnitude <= deadZone then
		return Vector2.zero
	end

	local scaledMagnitude = math.clamp((magnitude - deadZone) / (1 - deadZone), 0, 1)
	return value.Unit * scaledMagnitude
end

local function applyVector3DeadZone(value: Vector3, deadZone: number): Vector3
	local magnitude = value.Magnitude

	if magnitude <= deadZone then
		return Vector3.zero
	end

	local scaledMagnitude = math.clamp((magnitude - deadZone) / (1 - deadZone), 0, 1)
	return value.Unit * scaledMagnitude
end

local function setNativeContextEnabled(context: Instance, active: boolean): ()
	local native = context :: any
	local okEnabled = pcall(function()
		native.Enabled = active
	end)

	if okEnabled then
		return
	end

	local okActive = pcall(function()
		native.Active = active
	end)

	if okActive then
		return
	end

	context:SetAttribute("InputSystemActive", active)
end

local function setNativeContextPriority(context: Instance, priority: number): ()
	local native = context :: any
	local okPriority = pcall(function()
		native.Priority = priority
	end)

	if okPriority then
		return
	end

	context:SetAttribute("InputSystemPriority", priority)
end

local function getContextParent(config: Config): Instance
	if config.ContextParent ~= nil then
		return config.ContextParent
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer ~= nil then
		return localPlayer:WaitForChild("PlayerScripts")
	end

	return game:GetService("ReplicatedStorage")
end

local function createInputContext(contextName: string, parent: Instance, priority: number): Instance?
	local ok, created = pcall(function()
		local context = Instance.new("InputContext")
		context.Name = contextName
		context.Parent = parent
		return context
	end)

	if not ok then
		return nil
	end

	local context = created :: Instance
	setNativeContextPriority(context, priority)
	setNativeContextEnabled(context, false)
	return context
end

local function findContext(contextName: string, parent: Instance): Instance?
	local directChild = parent:FindFirstChild(contextName)
	if directChild ~= nil and directChild.ClassName == "InputContext" then
		return directChild
	end

	for _, descendant in parent:GetDescendants() do
		if descendant.Name == contextName and descendant.ClassName == "InputContext" then
			return descendant
		end
	end

	return nil
end

local function makeHandTelemetry(hand: Enum.UserCFrame): VRHandTelemetry
	local identity = CFrame.identity
	return {
		Hand = hand,
		CFrame = identity,
		PreviousCFrame = nil,
		Position = identity.Position,
		Delta = Vector3.zero,
		Trigger = makePayload(Enum.InputActionState.End, 0, nil),
		Thumbstick = makePayload(Enum.InputActionState.End, Vector2.zero, nil),
		LastUpdated = 0,
	}
end

function InputSystem.new(config: Config?): InputSystem
	local resolvedConfig = config or {}
	local self = setmetatable({
		_config = resolvedConfig,
		_contexts = {},
		_stack = {},
		_nextToken = 0,
		_connections = {},
		_vrEnabled = UserInputService.VREnabled,
		_hmd = makePayload(Enum.InputActionState.End, CFrame.identity, Vector3.zero),
		_leftHand = makeHandTelemetry(Enum.UserCFrame.LeftHand),
		_rightHand = makeHandTelemetry(Enum.UserCFrame.RightHand),
		_lastHmdCFrame = nil,
		_destroyed = false,
	}, InputSystem) :: any

	self:_log("Info", "InputSystem initialized", {
		VREnabled = self._vrEnabled,
		TouchZoneCount = self:_countTouchZones(),
	})
	self:_validateManualLinks()
	self:_connectVRInputs()
	self:_refreshVRTelemetry()

	return self :: InputSystem
end

function InputSystem:_countTouchZones(): number
	local touchZones = self._config.MobileTouchZones
	if touchZones == nil then
		return 0
	end

	local count = 0
	for _ in touchZones do
		count += 1
	end

	return count
end

function InputSystem:_log(level: LogLevel, message: string, data: { [string]: any }?): ()
	local logger = self._config.Logger or defaultLogger
	logger(level, message, data)
end

function InputSystem:_validateManualLinks(): ()
	local touchZones = self._config.MobileTouchZones
	if touchZones ~= nil then
		for key, link in touchZones do
			self:_log("Info", "Manual mobile touch zone linked to InputAction", {
				Key = key,
				ZoneId = link.ZoneId,
				LinkedActionName = link.LinkedActionName,
				Notes = link.Notes,
			})
		end
	end

	local actionLinks = self._config.ManualActionLinks
	if actionLinks ~= nil then
		for actionName, designAssetPath in actionLinks do
			self:_log("Info", "Manual UI component linked to InputAction", {
				ActionName = actionName,
				DesignAssetPath = designAssetPath,
			})
		end
	end
end

function InputSystem:_getThresholds(): AnalogThresholds
	return self._config.Thresholds or {}
end

function InputSystem:_getThumbstickDeadZone(): number
	local thresholds = self:_getThresholds()
	return thresholds.ThumbstickDeadZone
		or self._config.DefaultAnalogDeadZone
		or DEFAULT_ANALOG_DEAD_ZONE
end

function InputSystem:_getTrackpadDeadZone(): number
	local thresholds = self:_getThresholds()
	return thresholds.TrackpadDeadZone
		or self._config.DefaultTrackpadDeadZone
		or DEFAULT_TRACKPAD_DEAD_ZONE
end

function InputSystem:_getTriggerPressedThreshold(): number
	return self:_getThresholds().TriggerPressed or DEFAULT_TRIGGER_PRESSED
end

function InputSystem:_getTriggerReleasedThreshold(): number
	return self:_getThresholds().TriggerReleased or DEFAULT_TRIGGER_RELEASED
end

function InputSystem:_getHandDeltaEpsilon(): number
	return self:_getThresholds().HandDeltaEpsilon or DEFAULT_HAND_DELTA_EPSILON
end

function InputSystem:_resolveContext(contextName: string, priority: number?): ContextRecord
	local existing = self._contexts[contextName]
	if existing ~= nil then
		if priority ~= nil then
			existing.Priority = priority
			if existing.Context ~= nil then
				setNativeContextPriority(existing.Context, priority)
			end
		end
		return existing
	end

	local parent = getContextParent(self._config)
	local context = findContext(contextName, parent)
	local createdByInputSystem = false
	local resolvedPriority = priority or 0

	if context == nil and self._config.CreateMissingContexts ~= false then
		context = createInputContext(contextName, parent, resolvedPriority)
		createdByInputSystem = context ~= nil
	end

	local record: ContextRecord = {
		Name = contextName,
		Priority = resolvedPriority,
		Active = false,
		Context = context,
		CreatedByInputSystem = createdByInputSystem,
	}

	self._contexts[contextName] = record

	if context == nil then
		self:_log("Warning", "InputContext could not be resolved", {
			ContextName = contextName,
			Priority = resolvedPriority,
		})
	else
		setNativeContextPriority(context, resolvedPriority)
		setNativeContextEnabled(context, false)
	end

	local notes = self._config.ContextPriorityNotes
	if notes ~= nil and notes[contextName] ~= nil then
		self:_log("Info", "Context priority note", {
			ContextName = contextName,
			Priority = resolvedPriority,
			Notes = notes[contextName],
		})
	end

	return record
end

function InputSystem:_sortStack(): ()
	table.sort(self._stack, function(left: StackEntry, right: StackEntry): boolean
		if left.Priority == right.Priority then
			return left.Token > right.Token
		end

		return left.Priority > right.Priority
	end)
end

function InputSystem:_topStackEntry(): StackEntry?
	self:_sortStack()
	return self._stack[1]
end

function InputSystem:_syncContextActivation(): ()
	local topEntry = self:_topStackEntry()
	local topName = if topEntry ~= nil then topEntry.Name else nil

	for name, record in self._contexts do
		local shouldBeActive = record.Active and name == topName
		if record.Context ~= nil then
			setNativeContextEnabled(record.Context, shouldBeActive)
		elseif self._config.DeactivateMissingContexts ~= false then
			self:_log("Warning", "Cannot sync missing native InputContext", {
				ContextName = name,
				ShouldBeActive = shouldBeActive,
			})
		end
	end

	self:_log("Debug", "Context activation synchronized", {
		TopContext = topName,
		StackSize = #self._stack,
	})
end

function InputSystem:RegisterContext(
	contextName: string,
	context: Instance,
	priority: number?
): ContextRecord
	assert(not self._destroyed, "InputSystem has been destroyed")
	assert(context.ClassName == "InputContext", "RegisterContext expects an InputContext instance")

	local resolvedPriority = priority or (context:GetAttribute("InputSystemPriority") :: number?) or 0
	local record: ContextRecord = {
		Name = contextName,
		Priority = resolvedPriority,
		Active = false,
		Context = context,
		CreatedByInputSystem = false,
	}

	self._contexts[contextName] = record
	setNativeContextPriority(context, resolvedPriority)
	setNativeContextEnabled(context, false)
	self:_syncContextActivation()

	return record
end

function InputSystem:PushContext(contextName: string, priority: number): ContextRecord
	assert(not self._destroyed, "InputSystem has been destroyed")

	self._nextToken += 1
	local record = self:_resolveContext(contextName, priority)
	record.Active = true

	table.insert(self._stack, {
		Name = contextName,
		Priority = priority,
		Token = self._nextToken,
	})

	self:_syncContextActivation()
	return record
end

function InputSystem:PopContext(): ContextRecord?
	assert(not self._destroyed, "InputSystem has been destroyed")

	local topEntry = self:_topStackEntry()
	if topEntry == nil then
		return nil
	end

	for index, entry in self._stack do
		if entry.Token == topEntry.Token then
			table.remove(self._stack, index)
			break
		end
	end

	local stillStacked = false
	for _, entry in self._stack do
		if entry.Name == topEntry.Name then
			stillStacked = true
			break
		end
	end

	local record = self._contexts[topEntry.Name]
	if record ~= nil and not stillStacked then
		record.Active = false
	end

	self:_syncContextActivation()
	return record
end

function InputSystem:SetContextActive(contextName: string, active: boolean): ContextRecord
	assert(not self._destroyed, "InputSystem has been destroyed")

	local record = self:_resolveContext(contextName, nil)
	record.Active = active

	if active then
		local found = false
		for _, entry in self._stack do
			if entry.Name == contextName then
				found = true
				break
			end
		end

		if not found then
			self._nextToken += 1
			table.insert(self._stack, {
				Name = contextName,
				Priority = record.Priority,
				Token = self._nextToken,
			})
		end
	else
		local index = #self._stack
		while index >= 1 do
			if self._stack[index].Name == contextName then
				table.remove(self._stack, index)
			end
			index -= 1
		end
	end

	self:_syncContextActivation()
	return record
end

function InputSystem:GetContext(contextName: string): ContextRecord?
	return self._contexts[contextName]
end

function InputSystem:GetContextStack(): { ContextRecord }
	self:_sortStack()

	local records: { ContextRecord } = {}
	for _, entry in self._stack do
		local record = self._contexts[entry.Name]
		if record ~= nil then
			table.insert(records, {
				Name = record.Name,
				Priority = record.Priority,
				Active = record.Active,
				Context = record.Context,
				CreatedByInputSystem = record.CreatedByInputSystem,
			})
		end
	end

	return records
end

function InputSystem:NormalizeActionValue(
	actionKind: "Direction1D" | "Direction2D" | "Direction3D",
	value: any,
	deadZone: number?
): InputPayload
	local resolvedDeadZone = deadZone or self:_getThumbstickDeadZone()

	if actionKind == "Direction1D" then
		local raw = if typeof(value) == "number" then value else 0
		local normalized = if math.abs(raw) <= resolvedDeadZone then 0 else math.clamp(raw, -1, 1)

		-- SAFETY LOG(math-transform): Direction1D is clamped after threshold filtering before
		-- character-controller handoff, preventing analog trigger noise from acting as movement.
		self:_log("Debug", "Normalized Direction1D action value", {
			Raw = raw,
			Normalized = normalized,
			DeadZone = resolvedDeadZone,
		})

		return makePayload(getStateFromMagnitude(math.abs(normalized), resolvedDeadZone), normalized, nil)
	end

	if actionKind == "Direction2D" then
		local raw = if typeof(value) == "Vector2" then value else Vector2.zero
		local normalized = applyDeadZone(raw, resolvedDeadZone)

		-- SAFETY LOG(math-transform): Direction2D radial dead-zone processing prevents camera drift
		-- on thumbsticks and trackpads while preserving full-range movement beyond the threshold.
		self:_log("Debug", "Normalized Direction2D action value", {
			Raw = raw,
			Normalized = normalized,
			DeadZone = resolvedDeadZone,
		})

		return makePayload(
			getStateFromMagnitude(normalized.Magnitude, resolvedDeadZone),
			normalized,
			Vector3.new(normalized.X - raw.X, normalized.Y - raw.Y, 0)
		)
	end

	local raw = if typeof(value) == "Vector3" then value else Vector3.zero
	local normalized = applyVector3DeadZone(raw, resolvedDeadZone)

	-- SAFETY LOG(math-transform): Direction3D is normalized with a spherical dead zone before
	-- being passed to spatial character or camera controllers.
	self:_log("Debug", "Normalized Direction3D action value", {
		Raw = raw,
		Normalized = normalized,
		DeadZone = resolvedDeadZone,
	})

	return makePayload(getStateFromMagnitude(normalized.Magnitude, resolvedDeadZone), normalized, normalized - raw)
end

function InputSystem:_connectVRInputs(): ()
	self._connections.InputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end

		self:_handleVRInput(input, Enum.InputActionState.Begin)
	end)

	self._connections.InputChanged = UserInputService.InputChanged:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end

		self:_handleVRInput(input, Enum.InputActionState.Change)
	end)

	self._connections.InputEnded = UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end

		self:_handleVRInput(input, Enum.InputActionState.End)
	end)
end

function InputSystem:_getHandFromInput(input: InputObject): VRHandTelemetry?
	if input.UserInputType == Enum.UserInputType.Gamepad1 then
		return self._rightHand
	end

	if input.UserInputType == Enum.UserInputType.Gamepad2 then
		return self._leftHand
	end

	return nil
end

function InputSystem:_handleVRInput(input: InputObject, state: Enum.InputActionState): ()
	if not self._vrEnabled and not UserInputService.VREnabled then
		return
	end

	local hand = self:_getHandFromInput(input)
	if hand == nil then
		return
	end

	if input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		self:_updateTrigger(hand, input, state)
	elseif input.KeyCode == Enum.KeyCode.Thumbstick1 or input.KeyCode == Enum.KeyCode.Thumbstick2 then
		self:_updateThumbstick(hand, input, state)
	end

	self:_refreshVRTelemetry()
end

function InputSystem:_updateTrigger(
	hand: VRHandTelemetry,
	input: InputObject,
	state: Enum.InputActionState
): ()
	local triggerValue = math.clamp(input.Position.Z, 0, 1)
	local pressedThreshold = self:_getTriggerPressedThreshold()
	local releasedThreshold = self:_getTriggerReleasedThreshold()
	local payloadState = state

	-- EDGE CASE(threshold): Trigger release uses a lower threshold than press to avoid flicker when
	-- a user's finger rests around the actuation point.
	if state == Enum.InputActionState.Change then
		if triggerValue >= pressedThreshold then
			payloadState = Enum.InputActionState.Begin
		elseif triggerValue <= releasedThreshold then
			payloadState = Enum.InputActionState.End
		end
	end

	hand.Trigger = makePayload(payloadState, triggerValue, nil)
end

function InputSystem:_updateThumbstick(
	hand: VRHandTelemetry,
	input: InputObject,
	state: Enum.InputActionState
): ()
	local raw = Vector2.new(input.Position.X, input.Position.Y)
	local normalized = applyDeadZone(raw, self:_getThumbstickDeadZone())
	local payloadState = if normalized.Magnitude > 0 then state else Enum.InputActionState.End

	-- EDGE CASE(dead-zone): Trackpads and thumbsticks share payload shape, but trackpads should
	-- generally use Config.Thresholds.TrackpadDeadZone when manually forwarded through
	-- NormalizeActionValue("Direction2D", value, system:_getTrackpadDeadZone()).
	hand.Thumbstick = makePayload(
		payloadState,
		normalized,
		Vector3.new(normalized.X - raw.X, normalized.Y - raw.Y, 0)
	)
end

function InputSystem:_refreshVRTelemetry(): ()
	self._vrEnabled = UserInputService.VREnabled
	if not self._vrEnabled then
		return
	end

	self:_updateHeadsetTelemetry()
	self:_updateHandCFrame(self._leftHand)
	self:_updateHandCFrame(self._rightHand)
end

function InputSystem:_updateHeadsetTelemetry(): ()
	local camera = workspace.CurrentCamera
	local rawHeadCFrame = VRService:GetUserCFrame(Enum.UserCFrame.Head)
	local worldHeadCFrame = if camera ~= nil then camera.CFrame * rawHeadCFrame else rawHeadCFrame
	local previous = self._lastHmdCFrame
	local delta = if previous ~= nil then worldHeadCFrame.Position - previous.Position else Vector3.zero

	self._lastHmdCFrame = worldHeadCFrame
	self._hmd = makePayload(Enum.InputActionState.Change, worldHeadCFrame, delta)
end

function InputSystem:_updateHandCFrame(hand: VRHandTelemetry): ()
	local camera = workspace.CurrentCamera
	local rawCFrame = VRService:GetUserCFrame(hand.Hand)
	local worldCFrame = if camera ~= nil then camera.CFrame * rawCFrame else rawCFrame
	local previous = hand.CFrame
	local delta = worldCFrame.Position - previous.Position

	if delta.Magnitude <= self:_getHandDeltaEpsilon() then
		delta = Vector3.zero
	end

	hand.PreviousCFrame = previous
	hand.CFrame = worldCFrame
	hand.Position = worldCFrame.Position
	hand.Delta = delta
	hand.LastUpdated = os.clock()
end

function InputSystem:GetVRSnapshot(): VRSnapshot
	self:_refreshVRTelemetry()

	return {
		Enabled = self._vrEnabled,
		HMD = clonePayload(self._hmd),
		LeftHand = {
			Hand = self._leftHand.Hand,
			CFrame = self._leftHand.CFrame,
			PreviousCFrame = self._leftHand.PreviousCFrame,
			Position = self._leftHand.Position,
			Delta = self._leftHand.Delta,
			Trigger = clonePayload(self._leftHand.Trigger),
			Thumbstick = clonePayload(self._leftHand.Thumbstick),
			LastUpdated = self._leftHand.LastUpdated,
		},
		RightHand = {
			Hand = self._rightHand.Hand,
			CFrame = self._rightHand.CFrame,
			PreviousCFrame = self._rightHand.PreviousCFrame,
			Position = self._rightHand.Position,
			Delta = self._rightHand.Delta,
			Trigger = clonePayload(self._rightHand.Trigger),
			Thumbstick = clonePayload(self._rightHand.Thumbstick),
			LastUpdated = self._rightHand.LastUpdated,
		},
	}
end

function InputSystem:Destroy(): ()
	if self._destroyed then
		return
	end

	for _, connection in self._connections do
		if connection ~= nil then
			connection:Disconnect()
		end
	end

	for _, record in self._contexts do
		if record.Context ~= nil then
			setNativeContextEnabled(record.Context, false)
			if record.CreatedByInputSystem then
				record.Context:Destroy()
			end
		end
	end

	table.clear(self._connections)
	table.clear(self._contexts)
	table.clear(self._stack)
	self._destroyed = true
end

return table.freeze(InputSystem)
