--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(script.Parent.Shared.Constants)
local Loader = require(script.Parent.Shared.Loader)

local Client = {}
local controllers: { [string]: any } = {}
local controllerOrder: { any } = {}
local serviceProxies: { [string]: any } = {}
local started = false

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

	local proxy = {}
	local signals = waitFor(serviceFolder, Constants.SIGNALS)
	local clientSignals = waitFor(serviceFolder, Constants.CLIENT_SIGNALS)
	local methods = waitFor(serviceFolder, Constants.METHODS)
	for _, remote in signals:GetChildren() do
		if remote:IsA("RemoteEvent") then
			proxy[remote.Name] = table.freeze({
				Connect = function(_, callback)
					return remote.OnClientEvent:Connect(callback)
				end,
				Once = function(_, callback)
					return remote.OnClientEvent:Once(callback)
				end,
				Wait = function(_)
					return remote.OnClientEvent:Wait()
				end,
			})
		end
	end
	for _, remote in clientSignals:GetChildren() do
		if remote:IsA("RemoteEvent") then
			proxy[remote.Name] = table.freeze({
				Fire = function(_, ...)
					remote:FireServer(...)
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

function Client.Start()
	if started then
		error("[Framework] Framework.Start() has already been called.", 2)
	end
	started = true
	for _, controller in controllerOrder do
		if controller.Init ~= nil then
			local ok, message = pcall(controller.Init, controller)
			if not ok then
				error(string.format("[Framework] %s:Init() failed: %s", controller.Name, tostring(message)), 2)
			end
		end
	end
	for _, controller in controllerOrder do
		if controller.Start ~= nil then
			local ok, message = pcall(controller.Start, controller)
			if not ok then
				error(string.format("[Framework] %s:Start() failed: %s", controller.Name, tostring(message)), 2)
			end
		end
	end
end

return Client
