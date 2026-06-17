--!strict

local Types = require(script.Parent.Types)

local Logger = {}

function Logger.default(level: Types.LogLevel, message: string, data: { [string]: any }?): ()
	if level == "Warning" or level == "Error" then
		warn(string.format("[InputSystem/%s] %s", level, message), data)
	end
end

return table.freeze(Logger)
