--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(script.Parent.Shared.Constants)
local Endpoint = require(script.Parent.Shared.Endpoint)
local Gate = require(script.Parent.Shared.Gate)
local Lifecycle = require(script.Parent.Shared.Lifecycle)
local Loader = require(script.Parent.Shared.Loader)
local Property = require(script.Parent.Shared.Property)
local Signal = require(script.Parent.Shared.Signal)
local WarnThrottle = require(script.Parent.Shared.WarnThrottle)

type Descriptor = Endpoint.Descriptor

local Server = {}
local services: { [string]: any } = {}
local serviceOrder: { any } = {}
local specifications: { [any]: { [string]: Descriptor } } = {}
local started = false
local finished = false
local startCompleted = Signal.new()

-- Rejections and handler failures can be triggered by any client at will, so
-- their warnings are throttled per player and endpoint.
local throttledWarn = WarnThrottle.new(Constants.WARN_INTERVAL, warn)

local function registrationOpen()
	if started then
		error("[Framework] Cannot register services after Framework.Start().", 3)
	end
end

local function validDefinition(definition: any): boolean
	return type(definition) == "table" and type(definition.Name) == "string" and definition.Name ~= ""
end

function Server.CreateService(definition: any): any
	registrationOpen()
	assert(validDefinition(definition), "[Framework] CreateService requires a table with a non-empty Name.")
	if services[definition.Name] then
		error(string.format('[Framework] Service "%s" is already registered.', definition.Name), 2)
	end

	local client = definition.Client
	local specs = {}
	if client ~= nil then
		if type(client) ~= "table" then
			error(string.format("[Framework] %s.Client must be a table.", definition.Name), 2)
		end
		for name, endpoint in client do
			if name == "Server" then
				error(
					string.format(
						"[Framework] %s.Client.Server is reserved; it refers back to the service table.",
						definition.Name
					),
					2
				)
			end
			if type(name) ~= "string" or not Endpoint.is(endpoint) then
				error(
					string.format(
						"[Framework] %s.Client.%s must use Framework.Method(), Framework.Signal(), "
							.. "Framework.ClientSignal(), or Framework.Property().",
						definition.Name,
						tostring(name)
					),
					2
				)
			end
			specs[name] = endpoint
		end
	else
		definition.Client = {}
	end
	-- Properties are usable immediately (e.g. Set in Init); they start
	-- replicating once Start publishes networking.
	for name, descriptor in specs do
		if descriptor._kind == "Property" then
			definition.Client[name] = Property.new(descriptor._initial)
		end
	end
	-- Knit-compatible back-reference so Client handlers can reach server-only
	-- methods via self.Server. Never replicated: only declared specs create remotes.
	definition.Client.Server = definition

	services[definition.Name] = definition
	table.insert(serviceOrder, definition)
	specifications[definition] = specs
	return definition
end

function Server.GetService(name: string): any
	local service = services[name]
	if not service then
		error(
			string.format(
				'[Framework] Could not find service "%s". Was it registered before Framework.Start()?',
				tostring(name)
			),
			2
		)
	end
	return service
end

function Server.GetController(name: string): never
	error(
		string.format(
			'[Framework] Controllers are client-only; cannot get controller "%s" on the server.',
			tostring(name)
		),
		2
	)
end

function Server.AddServices(folder: Instance): { any }
	registrationOpen()
	return Loader.requireDescendants(folder)
end

function Server.CreateController(_definition: any): never
	error("[Framework] CreateController() is client-only.", 2)
end

function Server.AddControllers(_folder: Instance): never
	error("[Framework] AddControllers() is client-only.", 2)
end

function Server.OnStart()
	if not finished then
		startCompleted:Wait()
	end
end

local function validateHandlers()
	for _, service in serviceOrder do
		for endpointName, descriptor in specifications[service] do
			local kind = descriptor._kind
			local value = service.Client[endpointName]
			if (kind == "ClientSignal" or kind == "Method") and type(value) ~= "function" then
				error(
					string.format(
						"[Framework] %s.Client:%s(Player, ...) must be implemented before Start().",
						service.Name,
						endpointName
					),
					3
				)
			elseif kind == "Property" and not Property.is(value) then
				error(
					string.format(
						"[Framework] %s.Client.%s is a Property and must not be replaced.",
						service.Name,
						endpointName
					),
					3
				)
			end
		end
	end
end

local function createFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function newRemoteEvent(name: string, unreliable: boolean?, parent: Instance): RemoteEvent
	-- UnreliableRemoteEvent shares RemoteEvent's API but may drop or reorder
	-- events, and each payload is limited to roughly 900 bytes.
	local remote = Instance.new(if unreliable then "UnreliableRemoteEvent" else "RemoteEvent") :: any
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function bindSignal(service: any, endpointName: string, remote: RemoteEvent)
	local wrapper = {}
	function wrapper:Fire(player: Player, ...)
		remote:FireClient(player, ...)
	end
	function wrapper:FireAll(...)
		remote:FireAllClients(...)
	end
	function wrapper:FireExcept(excludedPlayer: Player, ...)
		for _, player in Players:GetPlayers() do
			if player ~= excludedPlayer then
				remote:FireClient(player, ...)
			end
		end
	end
	function wrapper:FireFor(targetPlayers: { Player }, ...)
		for _, player in targetPlayers do
			remote:FireClient(player, ...)
		end
	end
	service.Client[endpointName] = table.freeze(wrapper)
end

local function bindClientSignal(service: any, endpointName: string, descriptor: Descriptor, remote: RemoteEvent)
	local handler = service.Client[endpointName]
	local gate = Gate.new(descriptor._options)
	local topic = service.Name .. "." .. endpointName
	remote.OnServerEvent:Connect(function(player, ...)
		if gate then
			local allowed, reason = gate(player, ...)
			if not allowed then
				throttledWarn(
					player,
					topic .. ":rejected",
					string.format("[Framework] Rejected %s from %s (%s).", topic, player.Name, reason or "rejected")
				)
				return
			end
		end
		local ok, message = pcall(handler, service.Client, player, ...)
		if not ok then
			throttledWarn(
				player,
				topic .. ":failed",
				string.format("[Framework] %s handler failed: %s", topic, tostring(message))
			)
		end
	end)
end

local function bindMethod(service: any, endpointName: string, descriptor: Descriptor, remote: RemoteFunction)
	local handler = service.Client[endpointName]
	local gate = Gate.new(descriptor._options)
	local topic = service.Name .. "." .. endpointName
	remote.OnServerInvoke = function(player, ...)
		if gate then
			local allowed, reason = gate(player, ...)
			if not allowed then
				throttledWarn(
					player,
					topic .. ":rejected",
					string.format("[Framework] Rejected %s from %s (%s).", topic, player.Name, reason or "rejected")
				)
				error("[Framework] Request rejected.", 0)
			end
		end
		local results = table.pack(pcall(handler, service.Client, player, ...))
		if not results[1] then
			-- Details stay on the server; the client only sees a generic failure.
			throttledWarn(
				player,
				topic .. ":failed",
				string.format("[Framework] %s request failed: %s", topic, tostring(results[2]))
			)
			error("[Framework] Request failed.", 0)
		end
		return table.unpack(results, 2, results.n)
	end
end

local function bindPropertySnapshot(service: any, serviceFolder: Folder, names: { string })
	-- One round trip gives a client every property's current value for it.
	-- Clients request this once per service, so a small fixed limit suffices.
	local gate = Gate.new({ RateLimit = 5, Window = 1 }) :: Gate.Check
	local remote = Instance.new("RemoteFunction")
	remote.Name = Constants.PROPERTY_SNAPSHOT
	remote.OnServerInvoke = function(player)
		if not gate(player) then
			error("[Framework] Request rejected.", 0)
		end
		local snapshot = {}
		for _, name in names do
			snapshot[name] = service.Client[name]:GetFor(player)
		end
		return snapshot
	end
	remote.Parent = serviceFolder
end

local function bindService(root: Folder, service: any)
	local serviceFolder = createFolder(root, service.Name)
	local signalFolder = createFolder(serviceFolder, Constants.SIGNALS)
	local clientSignalFolder = createFolder(serviceFolder, Constants.CLIENT_SIGNALS)
	local methodFolder = createFolder(serviceFolder, Constants.METHODS)
	local propertyFolder = createFolder(serviceFolder, Constants.PROPERTIES)
	local propertyNames = {}

	for endpointName, descriptor in specifications[service] do
		local kind = descriptor._kind
		if kind == "Signal" then
			local remote = newRemoteEvent(endpointName, descriptor._options.Unreliable, signalFolder)
			bindSignal(service, endpointName, remote)
		elseif kind == "ClientSignal" then
			local remote = newRemoteEvent(endpointName, descriptor._options.Unreliable, clientSignalFolder)
			bindClientSignal(service, endpointName, descriptor, remote)
		elseif kind == "Method" then
			local remote = Instance.new("RemoteFunction")
			remote.Name = endpointName
			bindMethod(service, endpointName, descriptor, remote)
			remote.Parent = methodFolder
		elseif kind == "Property" then
			local remote = newRemoteEvent(endpointName, false, propertyFolder)
			service.Client[endpointName]:_bind(remote)
			table.insert(propertyNames, endpointName)
		end
	end
	-- Created even with no properties so clients can wait for it unconditionally.
	bindPropertySnapshot(service, serviceFolder, propertyNames)
end

function Server.Start()
	if started then
		error("[Framework] Framework.Start() has already been called.", 2)
	end
	started = true

	Lifecycle.validate(serviceOrder)
	Lifecycle.init(serviceOrder)
	validateHandlers()

	local existing = ReplicatedStorage:FindFirstChild(Constants.NETWORK_ROOT)
	if existing then
		error(string.format('[Framework] ReplicatedStorage already contains "%s".', Constants.NETWORK_ROOT), 2)
	end
	local root = createFolder(ReplicatedStorage, Constants.NETWORK_ROOT)
	root:SetAttribute("Owner", Constants.NAME)
	for _, service in serviceOrder do
		bindService(root, service)
	end
	local ready = Instance.new("BoolValue")
	ready.Name = Constants.READY
	ready.Value = true
	ready.Parent = root

	Lifecycle.start(serviceOrder)
	finished = true
	startCompleted:Fire()
end

return Server
