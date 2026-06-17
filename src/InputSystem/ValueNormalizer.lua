--!strict

local Types = require(script.Parent.Types)

local ValueNormalizer = {}

local DEFAULT_ANALOG_DEAD_ZONE = 0.12

local function stateFromMagnitude(magnitude: number, deadZone: number): Enum.InputActionState
	if magnitude > deadZone then
		return Enum.InputActionState.Change
	end

	return Enum.InputActionState.End
end

local function payload(state: Enum.InputActionState, value: any, delta: Vector3?): Types.InputPayload
	return {
		State = state,
		Value = value,
		Delta = delta,
	}
end

function ValueNormalizer.applyVector2DeadZone(value: Vector2, deadZone: number): Vector2
	local magnitude = value.Magnitude

	-- EDGE CASE(dead-zone): Small idle values from sticks and trackpads are clamped to prevent
	-- unintended camera drift or character movement.
	if magnitude <= deadZone then
		return Vector2.zero
	end

	local scaledMagnitude = math.clamp((magnitude - deadZone) / (1 - deadZone), 0, 1)
	return value.Unit * scaledMagnitude
end

function ValueNormalizer.applyVector3DeadZone(value: Vector3, deadZone: number): Vector3
	local magnitude = value.Magnitude

	if magnitude <= deadZone then
		return Vector3.zero
	end

	local scaledMagnitude = math.clamp((magnitude - deadZone) / (1 - deadZone), 0, 1)
	return value.Unit * scaledMagnitude
end

function ValueNormalizer.normalizeActionValue(
	actionKind: "Direction1D" | "Direction2D" | "Direction3D",
	value: any,
	deadZone: number?,
	logger: Types.Logger?
): Types.InputPayload
	local resolvedDeadZone = deadZone or DEFAULT_ANALOG_DEAD_ZONE

	if actionKind == "Direction1D" then
		local raw = if typeof(value) == "number" then value else 0
		local normalized = if math.abs(raw) <= resolvedDeadZone then 0 else math.clamp(raw, -1, 1)

		-- SAFETY LOG(math-transform): Direction1D values are thresholded and clamped before
		-- handoff to gameplay code so analog noise cannot become movement.
		if logger ~= nil then
			logger("Debug", "Normalized Direction1D action value", {
				Raw = raw,
				Normalized = normalized,
				DeadZone = resolvedDeadZone,
			})
		end

		return payload(stateFromMagnitude(math.abs(normalized), resolvedDeadZone), normalized, nil)
	end

	if actionKind == "Direction2D" then
		local raw = if typeof(value) == "Vector2" then value else Vector2.zero
		local normalized = ValueNormalizer.applyVector2DeadZone(raw, resolvedDeadZone)

		-- SAFETY LOG(math-transform): Direction2D uses radial dead-zone scaling for sticks and
		-- trackpads before character or camera controller handoff.
		if logger ~= nil then
			logger("Debug", "Normalized Direction2D action value", {
				Raw = raw,
				Normalized = normalized,
				DeadZone = resolvedDeadZone,
			})
		end

		return payload(
			stateFromMagnitude(normalized.Magnitude, resolvedDeadZone),
			normalized,
			Vector3.new(normalized.X - raw.X, normalized.Y - raw.Y, 0)
		)
	end

	local raw = if typeof(value) == "Vector3" then value else Vector3.zero
	local normalized = ValueNormalizer.applyVector3DeadZone(raw, resolvedDeadZone)

	-- SAFETY LOG(math-transform): Direction3D uses a spherical dead zone before spatial
	-- character, vehicle, or camera controller handoff.
	if logger ~= nil then
		logger("Debug", "Normalized Direction3D action value", {
			Raw = raw,
			Normalized = normalized,
			DeadZone = resolvedDeadZone,
		})
	end

	return payload(stateFromMagnitude(normalized.Magnitude, resolvedDeadZone), normalized, normalized - raw)
end

return table.freeze(ValueNormalizer)
