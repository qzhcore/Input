--!strict

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

export type DeviceKind = "KeyboardMouse" | "Mobile" | "Console" | "VR" | "Unknown"

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

return table.freeze({})
