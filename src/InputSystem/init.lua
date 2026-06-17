--!strict

--[[
	InputSystem

	

	Architecture notes for open-source maintainers:
	- Device-specific code lives under Devices so mobile, desktop, console, and VR behavior can evolve
	  independently without turning the public API into a large monolith.
	- Hardcoded priorities below are documented defaults, not game rules. Keep project-specific
	  override decisions close to the InputContext definitions that depend on them.
	- Manual UI links, including custom mobile touch zones, must be declared in Config.MobileTouchZones.
	  These assets live outside this raw script and cannot be inferred safely at runtime.
	- Safety logs are emitted through Config.Logger when math transformations normalize Direction1D,
	  Direction2D, or Direction3D values before character-controller handoff.
	- TODO(runtime-rebinding): When Roblox exposes custom player-facing runtime key rebinding for IAS,
	  add a user binding profile layer between InputAction lookup and InputBinding mutation.
]]

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Types)
local Logger = require(script.Logger)
local ContextStack = require(script.ContextStack)
local ValueNormalizer = require(script.ValueNormalizer)

local Console = require(script.Devices.Console)
local KeyboardMouse = require(script.Devices.KeyboardMouse)
local Mobile = require(script.Devices.Mobile)
local VRLayer = require(script.Devices.VR)

export type InputPayload = Types.InputPayload
export type Config = Types.Config
export type ContextRecord = Types.ContextRecord
export type DeviceKind = Types.DeviceKind
export type VRSnapshot = VRLayer.VRSnapshot

type InputSystemPrivate = {
	_config: Types.Config,
	_logger: Types.Logger,
	_contextStack: ContextStack.ContextStack,
	_vrLayer: VRLayer.VRLayer,
	_destroyed: boolean,
}

export type InputSystem = typeof(setmetatable({} :: InputSystemPrivate, {} :: any)) & {
	RegisterContext: (
		self: InputSystem,
		contextName: string,
		context: Instance,
		priority: number?
	) -> Types.ContextRecord,
	PushContext: (self: InputSystem, contextName: string, priority: number) -> Types.ContextRecord,
	PopContext: (self: InputSystem) -> Types.ContextRecord?,
	SetContextActive: (
		self: InputSystem,
		contextName: string,
		active: boolean
	) -> Types.ContextRecord,
	GetContext: (self: InputSystem, contextName: string) -> Types.ContextRecord?,
	GetContextStack: (self: InputSystem) -> { Types.ContextRecord },
	GetPreferredDevice: (self: InputSystem) -> Types.DeviceKind,
	GetVRSnapshot: (self: InputSystem) -> VRLayer.VRSnapshot,
	NormalizeActionValue: (
		self: InputSystem,
		actionKind: "Direction1D" | "Direction2D" | "Direction3D",
		value: any,
		deadZone: number?
	) -> Types.InputPayload,
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

function InputSystem.new(config: Types.Config?): InputSystem
	local resolvedConfig = config or {}
	local logger = resolvedConfig.Logger or Logger.default
	local self = setmetatable({
		_config = resolvedConfig,
		_logger = logger,
		_contextStack = ContextStack.new(resolvedConfig, logger),
		_vrLayer = VRLayer.new(resolvedConfig),
		_destroyed = false,
	}, InputSystem) :: any

	self:_logManualLinks()
	logger("Info", "InputSystem initialized", {
		PreferredDevice = self:GetPreferredDevice(),
		VREnabled = UserInputService.VREnabled,
	})

	return self :: InputSystem
end

function InputSystem:_assertAlive(): ()
	assert(not self._destroyed, "InputSystem has been destroyed")
end

function InputSystem:_logManualLinks(): ()
	local touchZones = self._config.MobileTouchZones
	if touchZones ~= nil then
		for key, link in pairs(touchZones) do
			self._logger("Info", "Manual mobile touch zone linked to InputAction", {
				Key = key,
				ZoneId = link.ZoneId,
				LinkedActionName = link.LinkedActionName,
				Notes = link.Notes,
			})
		end
	end

	local actionLinks = self._config.ManualActionLinks
	if actionLinks ~= nil then
		for actionName, designAssetPath in pairs(actionLinks) do
			self._logger("Info", "Manual UI component linked to InputAction", {
				ActionName = actionName,
				DesignAssetPath = designAssetPath,
			})
		end
	end
end

function InputSystem:RegisterContext(
	contextName: string,
	context: Instance,
	priority: number?
): Types.ContextRecord
	self:_assertAlive()
	return self._contextStack:RegisterContext(contextName, context, priority)
end

function InputSystem:PushContext(contextName: string, priority: number): Types.ContextRecord
	self:_assertAlive()
	return self._contextStack:PushContext(contextName, priority)
end

function InputSystem:PopContext(): Types.ContextRecord?
	self:_assertAlive()
	return self._contextStack:PopContext()
end

function InputSystem:SetContextActive(contextName: string, active: boolean): Types.ContextRecord
	self:_assertAlive()
	return self._contextStack:SetContextActive(contextName, active)
end

function InputSystem:GetContext(contextName: string): Types.ContextRecord?
	self:_assertAlive()
	return self._contextStack:GetContext(contextName)
end

function InputSystem:GetContextStack(): { Types.ContextRecord }
	self:_assertAlive()
	return self._contextStack:GetContextStack()
end

function InputSystem:GetPreferredDevice(): Types.DeviceKind
	if UserInputService.VREnabled then
		return "VR"
	elseif Mobile.isPreferred() then
		return "Mobile"
	elseif Console.isPreferred() then
		return "Console"
	elseif KeyboardMouse.isPreferred() then
		return "KeyboardMouse"
	end

	return "Unknown"
end

function InputSystem:GetVRSnapshot(): VRLayer.VRSnapshot
	self:_assertAlive()
	return self._vrLayer:GetSnapshot()
end

function InputSystem:NormalizeActionValue(
	actionKind: "Direction1D" | "Direction2D" | "Direction3D",
	value: any,
	deadZone: number?
): Types.InputPayload
	self:_assertAlive()
	return ValueNormalizer.normalizeActionValue(actionKind, value, deadZone, self._logger)
end

function InputSystem:Destroy(): ()
	if self._destroyed then
		return
	end

	self._contextStack:Destroy()
	self._vrLayer:Destroy()
	self._destroyed = true
end

InputSystem.Devices = table.freeze({
	Console = Console,
	KeyboardMouse = KeyboardMouse,
	Mobile = Mobile,
	VR = VRLayer,
})

return table.freeze(InputSystem)
