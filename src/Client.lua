--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(script.Parent.Shared.Constants)
local Lifecycle = require(script.Parent.Shared.Lifecycle)
local Loader = require(script.Parent.Shared.Loader)
local Signal = require(script.Parent.Shared.Signal)

local Client = {}
local controllers: { [string]: any } = {}
local controllerOrder: { any } = {}
local serviceProxies: { [string]: any } = {}
local started = false
local finished = false
local startCompleted = Signal.new()

local function registrationOpen()
	if started then
		error("[Framework] Cannot register controllers after Framework.Start().", 3)
	end
end

function Client.CreateController(definition: any): any
	registrationOpen()
	assert(
		type(definition) == "table" and type(definition.Name) == "string" and definition.Name ~= "",
		"[Framework] CreateController requires a table with a non-empty Name."
	)
	if controllers[definition.Name] then
		error(string.format('[Framework] Controller "%s" is already registered.', definition.Name), 2)
	end
	controllers[definition.Name] = definition
	table.insert(controllerOrder, definition)
	return definition
end

function Client.GetController(name: string): any
	local controller = controllers[name]
	if not controller then
		error(
			string.format(
				'[Framework] Could not find controller "%s". Was it registered before Framework.Start()?',
				tostring(name)
			),
			2
		)
	end
	return controller
end

local function waitFor(parent: Instance, name: string): Instance
	local child = parent:WaitForChild(name, Constants.REMOTE_TIMEOUT)
	if not child then
		error(string.format('[Framework] Timed out waiting for network member "%s".', name), 3)
	end
	return child
end

-- Read-only view of anything with Connect/Once/Wait (RBXScriptSignal or GoodSignal).
local function listenOnly(event: any)
	return table.freeze({
		Connect = function(_, callback)
			return event:Connect(callback)
		end,
		Once = function(_, callback)
			return event:Once(callback)
		end,
		Wait = function(_)
			return event:Wait()
		end,
	})
end

local function bindProperties(proxy: { [string]: any }, serviceFolder: Instance)
	local remotes = waitFor(serviceFolder, Constants.PROPERTIES):GetChildren()
	if #remotes == 0 then
		return
	end

	local states = {}
	for _, remote in remotes do
		if remote:IsA("RemoteEvent") then
			local state = { value = nil :: any, changed = Signal.new() }
			states[remote.Name] = state
			-- Listen before requesting the snapshot. Remotes are ordered, so a change
			-- that arrives before the snapshot reply is older than the snapshot.
			remote.OnClientEvent:Connect(function(value)
				state.value = value
				state.changed:Fire(value)
			end)
			proxy[remote.Name] = table.freeze({
				Get = function(_)
					return state.value
				end,
				Observe = function(_, callback)
					task.spawn(callback, state.value)
					return state.changed:Connect(callback)
				end,
				Changed = listenOnly(state.changed),
			})
		end
	end

	local snapshot = (waitFor(serviceFolder, Constants.PROPERTY_SNAPSHOT) :: RemoteFunction):InvokeServer()
	for name, state in states do
		state.value = snapshot[name]
	end
end

function Client.GetService(name: string): any
	if serviceProxies[name] then
		return serviceProxies[name]
	end
	local root = waitFor(ReplicatedStorage, Constants.NETWORK_ROOT)
	waitFor(root, Constants.READY)
	local serviceFolder = root:WaitForChild(name, Constants.REMOTE_TIMEOUT)
	if not serviceFolder then
		error(
			string.format(
				'[Framework] Could not find service "%s". Did the server register and start it?',
				tostring(name)
			),
			2
		)
	end

	local proxy: { [string]: any } = {}
	local signals = waitFor(serviceFolder, Constants.SIGNALS)
	local clientSignals = waitFor(serviceFolder, Constants.CLIENT_SIGNALS)
	local methods = waitFor(serviceFolder, Constants.METHODS)
	for _, remote in signals:GetChildren() do
		-- BaseRemoteEvent covers both RemoteEvent and UnreliableRemoteEvent.
		if remote:IsA("BaseRemoteEvent") then
			proxy[remote.Name] = listenOnly((remote :: RemoteEvent).OnClientEvent)
		end
	end
	for _, remote in clientSignals:GetChildren() do
		if remote:IsA("BaseRemoteEvent") then
			local event = remote :: RemoteEvent
			proxy[remote.Name] = table.freeze({
				Fire = function(_, ...)
					event:FireServer(...)
				end,
			})
		end
	end
	for _, remote in methods:GetChildren() do
		if remote:IsA("RemoteFunction") then
			proxy[remote.Name] = function(self, ...)
				if self ~= proxy then
					error(string.format("[Framework] Call %s:%s(...) with a colon.", name, remote.Name), 2)
				end
				return remote:InvokeServer(...)
			end
		end
	end
	bindProperties(proxy, serviceFolder)

	-- Another thread may have built this proxy while the snapshot was in flight.
	if serviceProxies[name] then
		return serviceProxies[name]
	end
	serviceProxies[name] = table.freeze(proxy)
	return serviceProxies[name]
end

function Client.CreateService(_definition: any): never
	error("[Framework] CreateService() is server-only.", 2)
end

function Client.AddControllers(folder: Instance): { any }
	registrationOpen()
	return Loader.requireDescendants(folder)
end

function Client.AddServices(_folder: Instance): never
	error("[Framework] AddServices() is server-only.", 2)
end

function Client.OnStart()
	if not finished then
		startCompleted:Wait()
	end
end

function Client.Start()
	if started then
		error("[Framework] Framework.Start() has already been called.", 2)
	end
	started = true

	Lifecycle.validate(controllerOrder)
	Lifecycle.init(controllerOrder)
	Lifecycle.start(controllerOrder)
	finished = true
	startCompleted:Fire()
end

return Client
