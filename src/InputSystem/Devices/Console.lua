--!strict

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)

local Console = {}

function Console.isPreferred(): boolean
	return UserInputService.GamepadEnabled
end

function Console.getDeviceKind(): Types.DeviceKind
	if Console.isPreferred() then
		return "Console"
	end

	return "Unknown"
end

return table.freeze(Console)
