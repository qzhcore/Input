--!strict

local InputStates = {}
local inputActionStateEnum = (Enum :: any).InputActionState

local function fromName(name: string): Enum.InputActionState
	local enumItem = inputActionStateEnum:FromName(name)
	assert(enumItem ~= nil, string.format("Enum.InputActionState.%s is unavailable", name))

	return enumItem :: Enum.InputActionState
end

InputStates.Begin = fromName("Begin")
InputStates.Change = fromName("Change")
InputStates.End = fromName("End")

return table.freeze(InputStates)
