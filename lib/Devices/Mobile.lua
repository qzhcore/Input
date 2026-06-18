--!strict

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)

local Mobile = {}

function Mobile.isPreferred(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Mobile.getTouchZones(config: Types.Config): { [string]: Types.TouchZoneLink }
	return config.MobileTouchZones or {}
end

function Mobile.getDeviceKind(): Types.DeviceKind
	if Mobile.isPreferred() then
		return "Mobile"
	end

	return "Unknown"
end

return table.freeze(Mobile)
