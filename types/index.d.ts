/// <reference types="@rbxts/types" />

declare namespace InputSystem {
	type LogLevel = "Debug" | "Info" | "Warning" | "Error";
	type DeviceKind = "KeyboardMouse" | "Mobile" | "Console" | "VR" | "Unknown";
	type ActionKind = "Direction1D" | "Direction2D" | "Direction3D";

	interface InputPayload<T = unknown> {
		State: Enum.InputActionState;
		Value: T;
		Delta?: Vector3;
	}

	interface TouchZoneLink {
		ZoneId: string;
		LinkedActionName: string;
		Notes: string;
	}

	interface AnalogThresholds {
		TriggerPressed?: number;
		TriggerReleased?: number;
		ThumbstickDeadZone?: number;
		TrackpadDeadZone?: number;
		HandDeltaEpsilon?: number;
	}

	interface ContextRecord {
		Name: string;
		Priority: number;
		Active: boolean;
		Context?: Instance;
		CreatedByInputSystem: boolean;
	}

	interface VRHandTelemetry {
		Hand: Enum.UserCFrame;
		CFrame: CFrame;
		PreviousCFrame?: CFrame;
		Position: Vector3;
		Delta: Vector3;
		Trigger: InputPayload<number>;
		Thumbstick: InputPayload<Vector2>;
		LastUpdated: number;
	}

	interface VRSnapshot {
		Enabled: boolean;
		HMD: InputPayload<CFrame>;
		LeftHand: VRHandTelemetry;
		RightHand: VRHandTelemetry;
	}

	interface Config {
		ContextParent?: Instance;
		CreateMissingContexts?: boolean;
		DeactivateMissingContexts?: boolean;
		DefaultAnalogDeadZone?: number;
		DefaultTrackpadDeadZone?: number;
		Thresholds?: AnalogThresholds;
		Logger?: (level: LogLevel, message: string, data?: Record<string, unknown>) => void;
		MobileTouchZones?: Record<string, TouchZoneLink>;
		ContextPriorityNotes?: Record<string, string>;
		ManualActionLinks?: Record<string, string>;
	}

	interface Controller {
		RegisterContext(contextName: string, context: Instance, priority?: number): ContextRecord;
		PushContext(contextName: string, priority: number): ContextRecord;
		PopContext(): ContextRecord | undefined;
		SetContextActive(contextName: string, active: boolean): ContextRecord;
		GetContext(contextName: string): ContextRecord | undefined;
		GetContextStack(): ContextRecord[];
		GetPreferredDevice(): DeviceKind;
		GetVRSnapshot(): VRSnapshot;
		NormalizeActionValue<T = unknown>(
			actionKind: ActionKind,
			value: T,
			deadZone?: number,
		): InputPayload<T>;
		Destroy(): void;
	}

	interface Static {
		Priority: Readonly<{
			Gameplay: 100;
			Vehicle: 200;
			Menu: 500;
			Modal: 900;
			Debug: 1000;
		}>;

		new(config?: Config): Controller;
	}
}

declare const InputSystem: InputSystem.Static;

export = InputSystem;
