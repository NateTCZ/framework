--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(script.Parent.Shared.Constants)
local Endpoint = require(script.Parent.Shared.Endpoint)
local Loader = require(script.Parent.Shared.Loader)

type Descriptor = Endpoint.Descriptor

local Server = {}
local services: { [string]: any } = {}
local serviceOrder: { any } = {}
local specifications: { [any]: { [string]: Descriptor } } = {}
local started = false

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
			if type(name) ~= "string" or not Endpoint.is(endpoint) then
				error(
					string.format(
						"[Framework] %s.Client.%s must use Framework.Method(), Framework.Signal(), or Framework.ClientSignal().",
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

function Server.AddControllers(_folder: Instance): never
	error("[Framework] AddControllers() is client-only.", 2)
end

local function makeGate(serviceName: string, endpointName: string, options: any)
	if next(options) == nil then
		return nil
	end

	local states = setmetatable({}, { __mode = "k" })
	return function(player: Player, ...): (boolean, string?)
		local now = os.clock()
		local state = states[player]
		if not state then
			state = { windowStart = now, count = 0, last = -math.huge }
			states[player] = state
		end

		if options.Cooldown and now - state.last < options.Cooldown then
			return false, "cooldown"
		end
		if options.RateLimit then
			if now - state.windowStart >= options.Window then
				state.windowStart = now
				state.count = 0
			end
			if state.count >= options.RateLimit then
				return false, "rate limit"
			end
		end
		-- Consume abuse-control budget before validation so malformed traffic is
		-- not able to run validators without being throttled.
		state.last = now
		state.count += 1

		if options.Validate then
			local ok, accepted, reason = pcall(options.Validate, player, ...)
			if not ok then
				warn(
					string.format(
						"[Framework] Validator for %s.%s errored: %s",
						serviceName,
						endpointName,
						tostring(accepted)
					)
				)
				return false, "validation failed"
			end
			if accepted ~= true then
				return false, if type(reason) == "string" then reason else "validation failed"
			end
		end

		return true
	end
end

local function validateHandlers()
	for _, service in serviceOrder do
		for endpointName, descriptor in specifications[service] do
			if descriptor._kind ~= "Signal" and type(service.Client[endpointName]) ~= "function" then
				error(
					string.format(
						"[Framework] %s.Client:%s(Player, ...) must be implemented before Start().",
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

local function bindService(root: Folder, service: any)
	local serviceFolder = createFolder(root, service.Name)
	local signalFolder = createFolder(serviceFolder, Constants.SIGNALS)
	local clientSignalFolder = createFolder(serviceFolder, Constants.CLIENT_SIGNALS)
	local methodFolder = createFolder(serviceFolder, Constants.METHODS)

	for endpointName, descriptor in specifications[service] do
		local kind = descriptor._kind
		if kind == "Signal" then
			local remote = Instance.new("RemoteEvent")
			remote.Name = endpointName
			remote.Parent = signalFolder
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
		elseif kind == "ClientSignal" then
			local handler = service.Client[endpointName]
			if type(handler) ~= "function" then
				error(
					string.format(
						"[Framework] %s.Client:%s(Player, ...) must be implemented before Start().",
						service.Name,
						endpointName
					),
					3
				)
			end
			local gate = makeGate(service.Name, endpointName, descriptor._options)
			local remote = Instance.new("RemoteEvent")
			remote.Name = endpointName
			remote.Parent = clientSignalFolder
			remote.OnServerEvent:Connect(function(player, ...)
				if gate then
					local allowed, reason = gate(player, ...)
					if not allowed then
						warn(
							string.format(
								"[Framework] Rejected %s.%s from %s (%s).",
								service.Name,
								endpointName,
								player.Name,
								reason or "rejected"
							)
						)
						return
					end
				end
				local ok, message = pcall(handler, service.Client, player, ...)
				if not ok then
					warn(
						string.format(
							"[Framework] %s.%s handler failed: %s",
							service.Name,
							endpointName,
							tostring(message)
						)
					)
				end
			end)
		elseif kind == "Method" then
			local handler = service.Client[endpointName]
			if type(handler) ~= "function" then
				error(
					string.format(
						"[Framework] %s.Client:%s(Player, ...) must be implemented before Start().",
						service.Name,
						endpointName
					),
					3
				)
			end
			local gate = makeGate(service.Name, endpointName, descriptor._options)
			local remote = Instance.new("RemoteFunction")
			remote.Name = endpointName
			remote.Parent = methodFolder
			remote.OnServerInvoke = function(player, ...)
				if gate then
					local allowed = gate(player, ...)
					if not allowed then
						error("[Framework] Request rejected.", 0)
					end
				end
				local results = table.pack(pcall(handler, service.Client, player, ...))
				if not results[1] then
					warn(
						string.format(
							"[Framework] %s.%s request failed: %s",
							service.Name,
							endpointName,
							tostring(results[2])
						)
					)
					error("[Framework] Request failed.", 0)
				end
				return table.unpack(results, 2, results.n)
			end
		end
	end
end

function Server.Start()
	if started then
		error("[Framework] Framework.Start() has already been called.", 2)
	end
	started = true

	for _, service in serviceOrder do
		if service.Init ~= nil then
			if type(service.Init) ~= "function" then
				error(string.format("[Framework] %s.Init must be a function.", service.Name), 2)
			end
			local ok, message = pcall(service.Init, service)
			if not ok then
				error(string.format("[Framework] %s:Init() failed: %s", service.Name, tostring(message)), 2)
			end
		end
	end
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

	for _, service in serviceOrder do
		if service.Start ~= nil then
			if type(service.Start) ~= "function" then
				error(string.format("[Framework] %s.Start must be a function.", service.Name), 2)
			end
			local ok, message = pcall(service.Start, service)
			if not ok then
				error(string.format("[Framework] %s:Start() failed: %s", service.Name, tostring(message)), 2)
			end
		end
	end
end

return Server
