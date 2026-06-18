--!strict

local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

local Types = require(script.Parent.Parent.Types)
local InputStates = require(script.Parent.Parent.InputStates)
local ValueNormalizer = require(script.Parent.Parent.ValueNormalizer)

export type VRHandTelemetry = {
	Hand: Enum.UserCFrame,
	CFrame: CFrame,
	PreviousCFrame: CFrame?,
	Position: Vector3,
	Delta: Vector3,
	Trigger: Types.InputPayload,
	Thumbstick: Types.InputPayload,
	LastUpdated: number,
}

export type VRSnapshot = {
	Enabled: boolean,
	HMD: Types.InputPayload,
	LeftHand: VRHandTelemetry,
	RightHand: VRHandTelemetry,
}

type Connections = {
	InputBegan: RBXScriptConnection?,
	InputChanged: RBXScriptConnection?,
	InputEnded: RBXScriptConnection?,
}

type VRLayerPrivate = {
	_config: Types.Config,
	_leftHand: VRHandTelemetry,
	_rightHand: VRHandTelemetry,
	_hmd: Types.InputPayload,
	_lastHmdCFrame: CFrame?,
	_connections: Connections,
}

export type VRLayer = typeof(setmetatable({} :: VRLayerPrivate, {} :: any)) & {
	GetSnapshot: (self: VRLayer) -> VRSnapshot,
	Destroy: (self: VRLayer) -> (),
}

local VRLayer = {}
VRLayer.__index = VRLayer

local DEFAULT_TRIGGER_PRESSED = 0.55
local DEFAULT_TRIGGER_RELEASED = 0.35
local DEFAULT_ANALOG_DEAD_ZONE = 0.12
local DEFAULT_HAND_DELTA_EPSILON = 0.0001

local function makePayload(
	state: Enum.InputActionState,
	value: any,
	delta: Vector3?
): Types.InputPayload
	return {
		State = state,
		Value = value,
		Delta = delta,
	}
end

local function clonePayload(payload: Types.InputPayload): Types.InputPayload
	return {
		State = payload.State,
		Value = payload.Value,
		Delta = payload.Delta,
	}
end

local function makeHandTelemetry(hand: Enum.UserCFrame): VRHandTelemetry
	return {
		Hand = hand,
		CFrame = CFrame.identity,
		PreviousCFrame = nil,
		Position = Vector3.zero,
		Delta = Vector3.zero,
		Trigger = makePayload(InputStates.End, 0, nil),
		Thumbstick = makePayload(InputStates.End, Vector2.zero, nil),
		LastUpdated = 0,
	}
end

function VRLayer.new(config: Types.Config): VRLayer
	local self = setmetatable({
		_config = config,
		_leftHand = makeHandTelemetry(Enum.UserCFrame.LeftHand),
		_rightHand = makeHandTelemetry(Enum.UserCFrame.RightHand),
		_hmd = makePayload(InputStates.End, CFrame.identity, Vector3.zero),
		_lastHmdCFrame = nil,
		_connections = {},
	}, VRLayer) :: any

	self:_connect()
	self:_refresh()

	return self :: VRLayer
end

function VRLayer:_thresholds(): Types.AnalogThresholds
	return self._config.Thresholds or {}
end

function VRLayer:_thumbstickDeadZone(): number
	return self:_thresholds().ThumbstickDeadZone
		or self._config.DefaultAnalogDeadZone
		or DEFAULT_ANALOG_DEAD_ZONE
end

function VRLayer:_triggerPressedThreshold(): number
	return self:_thresholds().TriggerPressed or DEFAULT_TRIGGER_PRESSED
end

function VRLayer:_triggerReleasedThreshold(): number
	return self:_thresholds().TriggerReleased or DEFAULT_TRIGGER_RELEASED
end

function VRLayer:_handDeltaEpsilon(): number
	return self:_thresholds().HandDeltaEpsilon or DEFAULT_HAND_DELTA_EPSILON
end

function VRLayer:_connect(): ()
	self._connections.InputBegan = UserInputService.InputBegan:Connect(
		function(input, gameProcessedEvent)
			if not gameProcessedEvent then
				self:_handleInput(input, InputStates.Begin)
			end
		end
	)

	self._connections.InputChanged = UserInputService.InputChanged:Connect(
		function(input, gameProcessedEvent)
			if not gameProcessedEvent then
				self:_handleInput(input, InputStates.Change)
			end
		end
	)

	self._connections.InputEnded = UserInputService.InputEnded:Connect(
		function(input, gameProcessedEvent)
			if not gameProcessedEvent then
				self:_handleInput(input, InputStates.End)
			end
		end
	)
end

function VRLayer:_handFromInput(input: InputObject): VRHandTelemetry?
	if input.UserInputType == Enum.UserInputType.Gamepad1 then
		return self._rightHand
	elseif input.UserInputType == Enum.UserInputType.Gamepad2 then
		return self._leftHand
	end

	return nil
end

function VRLayer:_handleInput(input: InputObject, state: Enum.InputActionState): ()
	if not UserInputService.VREnabled then
		return
	end

	local hand = self:_handFromInput(input)
	if hand == nil then
		return
	end

	if input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		self:_updateTrigger(hand, input, state)
	elseif
		input.KeyCode == Enum.KeyCode.Thumbstick1 or input.KeyCode == Enum.KeyCode.Thumbstick2
	then
		self:_updateThumbstick(hand, input, state)
	end

	self:_refresh()
end

function VRLayer:_updateTrigger(
	hand: VRHandTelemetry,
	input: InputObject,
	state: Enum.InputActionState
): ()
	local triggerValue = math.clamp(input.Position.Z, 0, 1)
	local payloadState = state

	-- EDGE CASE(threshold): Trigger release uses a lower threshold than press to prevent flicker
	-- around the actuation point.
	if state == InputStates.Change then
		if triggerValue >= self:_triggerPressedThreshold() then
			payloadState = InputStates.Begin
		elseif triggerValue <= self:_triggerReleasedThreshold() then
			payloadState = InputStates.End
		end
	end

	hand.Trigger = makePayload(payloadState, triggerValue, nil)
end

function VRLayer:_updateThumbstick(
	hand: VRHandTelemetry,
	input: InputObject,
	state: Enum.InputActionState
): ()
	local raw = Vector2.new(input.Position.X, input.Position.Y)
	local normalized = ValueNormalizer.applyVector2DeadZone(raw, self:_thumbstickDeadZone())
	local payloadState = if normalized.Magnitude > 0 then state else InputStates.End

	hand.Thumbstick = makePayload(
		payloadState,
		normalized,
		Vector3.new(normalized.X - raw.X, normalized.Y - raw.Y, 0)
	)
end

function VRLayer:_refresh(): ()
	if not UserInputService.VREnabled then
		return
	end

	self:_updateHeadsetTelemetry()
	self:_updateHandCFrame(self._leftHand)
	self:_updateHandCFrame(self._rightHand)
end

function VRLayer:_updateHeadsetTelemetry(): ()
	local camera = workspace.CurrentCamera
	local rawHeadCFrame = VRService:GetUserCFrame(Enum.UserCFrame.Head)
	local worldHeadCFrame = if camera ~= nil then camera.CFrame * rawHeadCFrame else rawHeadCFrame
	local previous = self._lastHmdCFrame
	local delta = if previous ~= nil
		then worldHeadCFrame.Position - previous.Position
		else Vector3.zero

	self._lastHmdCFrame = worldHeadCFrame
	self._hmd = makePayload(InputStates.Change, worldHeadCFrame, delta)
end

function VRLayer:_updateHandCFrame(hand: VRHandTelemetry): ()
	local camera = workspace.CurrentCamera
	local rawCFrame = VRService:GetUserCFrame(hand.Hand)
	local worldCFrame = if camera ~= nil then camera.CFrame * rawCFrame else rawCFrame
	local previous = hand.CFrame
	local delta = worldCFrame.Position - previous.Position

	if delta.Magnitude <= self:_handDeltaEpsilon() then
		delta = Vector3.zero
	end

	hand.PreviousCFrame = previous
	hand.CFrame = worldCFrame
	hand.Position = worldCFrame.Position
	hand.Delta = delta
	hand.LastUpdated = os.clock()
end

function VRLayer:GetSnapshot(): VRSnapshot
	self:_refresh()

	return {
		Enabled = UserInputService.VREnabled,
		HMD = clonePayload(self._hmd),
		LeftHand = table.clone(self._leftHand),
		RightHand = table.clone(self._rightHand),
	}
end

function VRLayer:Destroy(): ()
	for _, connection in pairs(self._connections) do
		if connection ~= nil then
			connection:Disconnect()
		end
	end

	table.clear(self._connections)
end

return VRLayer
