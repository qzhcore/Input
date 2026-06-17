--!strict

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)

local KeyboardMouse = {}

function KeyboardMouse.isPreferred(): boolean
	return UserInputService.KeyboardEnabled or UserInputService.MouseEnabled
end

function KeyboardMouse.getDeviceKind(): Types.DeviceKind
	if KeyboardMouse.isPreferred() then
		return "KeyboardMouse"
	end

	return "Unknown"
end

return table.freeze(KeyboardMouse)
