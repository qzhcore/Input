--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Types)

type StackEntry = {
	Name: string,
	Priority: number,
	Token: number,
}

type ContextStackPrivate = {
	_config: Types.Config,
	_logger: Types.Logger,
	_contexts: { [string]: Types.ContextRecord },
	_stack: { StackEntry },
	_nextToken: number,
}

export type ContextStack = typeof(setmetatable({} :: ContextStackPrivate, {} :: any)) & {
	RegisterContext: (
		self: ContextStack,
		contextName: string,
		context: Instance,
		priority: number?
	) -> Types.ContextRecord,
	PushContext: (self: ContextStack, contextName: string, priority: number) -> Types.ContextRecord,
	PopContext: (self: ContextStack) -> Types.ContextRecord?,
	SetContextActive: (
		self: ContextStack,
		contextName: string,
		active: boolean
	) -> Types.ContextRecord,
	GetContext: (self: ContextStack, contextName: string) -> Types.ContextRecord?,
	GetContextStack: (self: ContextStack) -> { Types.ContextRecord },
	Destroy: (self: ContextStack) -> (),
}

local ContextStack = {}
ContextStack.__index = ContextStack

local function getContextParent(config: Types.Config): Instance
	if config.ContextParent ~= nil then
		return config.ContextParent
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer ~= nil then
		return localPlayer:WaitForChild("PlayerScripts")
	end

	return ReplicatedStorage
end

local function setNativeContextEnabled(context: Instance, active: boolean): ()
	local native = context :: any
	local okEnabled = pcall(function()
		native.Enabled = active
	end)

	if okEnabled then
		return
	end

	local okActive = pcall(function()
		native.Active = active
	end)

	if okActive then
		return
	end

	context:SetAttribute("InputSystemActive", active)
end

local function setNativeContextPriority(context: Instance, priority: number): ()
	local native = context :: any
	local okPriority = pcall(function()
		native.Priority = priority
	end)

	if okPriority then
		return
	end

	context:SetAttribute("InputSystemPriority", priority)
end

local function findContext(contextName: string, parent: Instance): Instance?
	local directChild = parent:FindFirstChild(contextName)
	if directChild ~= nil and directChild.ClassName == "InputContext" then
		return directChild
	end

	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant.Name == contextName and descendant.ClassName == "InputContext" then
			return descendant
		end
	end

	return nil
end

local function createInputContext(
	contextName: string,
	parent: Instance,
	priority: number
): Instance?
	local ok, created = pcall(function()
		local context = Instance.new("InputContext")
		context.Name = contextName
		context.Parent = parent
		return context
	end)

	if not ok then
		return nil
	end

	local context = created :: Instance
	setNativeContextPriority(context, priority)
	setNativeContextEnabled(context, false)
	return context
end

function ContextStack.new(config: Types.Config, logger: Types.Logger): ContextStack
	return setmetatable({
		_config = config,
		_logger = logger,
		_contexts = {},
		_stack = {},
		_nextToken = 0,
	}, ContextStack) :: any
end

function ContextStack:_resolveContext(contextName: string, priority: number?): Types.ContextRecord
	local existing = self._contexts[contextName]
	if existing ~= nil then
		if priority ~= nil then
			existing.Priority = priority
			if existing.Context ~= nil then
				setNativeContextPriority(existing.Context, priority)
			end
		end
		return existing
	end

	local parent = getContextParent(self._config)
	local context = findContext(contextName, parent)
	local resolvedPriority = priority or 0
	local createdByInputSystem = false

	if context == nil and self._config.CreateMissingContexts ~= false then
		context = createInputContext(contextName, parent, resolvedPriority)
		createdByInputSystem = context ~= nil
	end

	local record: Types.ContextRecord = {
		Name = contextName,
		Priority = resolvedPriority,
		Active = false,
		Context = context,
		CreatedByInputSystem = createdByInputSystem,
	}

	self._contexts[contextName] = record

	if context == nil then
		self._logger("Warning", "InputContext could not be resolved", {
			ContextName = contextName,
			Priority = resolvedPriority,
		})
	else
		setNativeContextPriority(context, resolvedPriority)
		setNativeContextEnabled(context, false)
	end

	local notes = self._config.ContextPriorityNotes
	if notes ~= nil and notes[contextName] ~= nil then
		self._logger("Info", "Context priority note", {
			ContextName = contextName,
			Priority = resolvedPriority,
			Notes = notes[contextName],
		})
	end

	return record
end

function ContextStack:_sortStack(): ()
	table.sort(self._stack, function(left: StackEntry, right: StackEntry): boolean
		if left.Priority == right.Priority then
			return left.Token > right.Token
		end

		return left.Priority > right.Priority
	end)
end

function ContextStack:_topStackEntry(): StackEntry?
	self:_sortStack()
	return self._stack[1]
end

function ContextStack:_syncContextActivation(): ()
	local topEntry = self:_topStackEntry()
	local topName = if topEntry ~= nil then topEntry.Name else nil

	for name, record in pairs(self._contexts) do
		local shouldBeActive = record.Active and name == topName
		if record.Context ~= nil then
			setNativeContextEnabled(record.Context, shouldBeActive)
		elseif self._config.DeactivateMissingContexts ~= false then
			self._logger("Warning", "Cannot sync missing native InputContext", {
				ContextName = name,
				ShouldBeActive = shouldBeActive,
			})
		end
	end
end

function ContextStack:RegisterContext(
	contextName: string,
	context: Instance,
	priority: number?
): Types.ContextRecord
	assert(context.ClassName == "InputContext", "RegisterContext expects an InputContext instance")

	local resolvedPriority = priority
		or (context:GetAttribute("InputSystemPriority") :: number?)
		or 0
	local record: Types.ContextRecord = {
		Name = contextName,
		Priority = resolvedPriority,
		Active = false,
		Context = context,
		CreatedByInputSystem = false,
	}

	self._contexts[contextName] = record
	setNativeContextPriority(context, resolvedPriority)
	setNativeContextEnabled(context, false)
	self:_syncContextActivation()

	return record
end

function ContextStack:PushContext(contextName: string, priority: number): Types.ContextRecord
	self._nextToken += 1
	local record = self:_resolveContext(contextName, priority)
	record.Active = true

	table.insert(self._stack, {
		Name = contextName,
		Priority = priority,
		Token = self._nextToken,
	})

	self:_syncContextActivation()
	return record
end

function ContextStack:PopContext(): Types.ContextRecord?
	local topEntry = self:_topStackEntry()
	if topEntry == nil then
		return nil
	end

	for index, entry in ipairs(self._stack) do
		if entry.Token == topEntry.Token then
			table.remove(self._stack, index)
			break
		end
	end

	local stillStacked = false
	for _, entry in ipairs(self._stack) do
		if entry.Name == topEntry.Name then
			stillStacked = true
			break
		end
	end

	local record = self._contexts[topEntry.Name]
	if record ~= nil and not stillStacked then
		record.Active = false
	end

	self:_syncContextActivation()
	return record
end

function ContextStack:SetContextActive(contextName: string, active: boolean): Types.ContextRecord
	local record = self:_resolveContext(contextName, nil)
	record.Active = active

	if active then
		local found = false
		for _, entry in ipairs(self._stack) do
			if entry.Name == contextName then
				found = true
				break
			end
		end

		if not found then
			self._nextToken += 1
			table.insert(self._stack, {
				Name = contextName,
				Priority = record.Priority,
				Token = self._nextToken,
			})
		end
	else
		local index = #self._stack
		while index >= 1 do
			if self._stack[index].Name == contextName then
				table.remove(self._stack, index)
			end
			index -= 1
		end
	end

	self:_syncContextActivation()
	return record
end

function ContextStack:GetContext(contextName: string): Types.ContextRecord?
	return self._contexts[contextName]
end

function ContextStack:GetContextStack(): { Types.ContextRecord }
	self:_sortStack()

	local records: { Types.ContextRecord } = {}
	for _, entry in ipairs(self._stack) do
		local record = self._contexts[entry.Name]
		if record ~= nil then
			table.insert(records, {
				Name = record.Name,
				Priority = record.Priority,
				Active = record.Active,
				Context = record.Context,
				CreatedByInputSystem = record.CreatedByInputSystem,
			})
		end
	end

	return records
end

function ContextStack:Destroy(): ()
	for _, record in pairs(self._contexts) do
		if record.Context ~= nil then
			setNativeContextEnabled(record.Context, false)
			if record.CreatedByInputSystem then
				record.Context:Destroy()
			end
		end
	end

	table.clear(self._contexts)
	table.clear(self._stack)
end

return ContextStack
