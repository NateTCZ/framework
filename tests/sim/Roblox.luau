--[[
	A small simulation of the Roblox engine for running Framework end to end
	under Lune. It is not a general Roblox emulator; it models exactly what
	Framework and the example place touch:

	- One server DataModel and one client DataModel per player, each with its
	  own module cache, as in Roblox.
	- ReplicatedStorage replication from server to clients. Subtrees arrive
	  whole, and all network traffic for a client is delivered in order.
	- RemoteEvent, UnreliableRemoteEvent, and RemoteFunction. Arguments are
	  deep-copied (functions dropped, frozen tables arrive unfrozen), client
	  events wait in a queue until a listener connects, and invocations are
	  real round trips that yield.
	- Players joining and leaving, with deferred PlayerAdded/PlayerRemoving.
	- Instance member lookups that error like Roblox for unknown members.

	Timeouts passed to WaitForChild are scaled down so timeout paths run quickly.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local builtinTypeof = typeof

local TIMEOUT_SCALE = 0.05

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local Event = {}
Event.__index = Event

local function newEvent(world, onConnect)
	return setmetatable({ _connections = {}, _world = world, _onConnect = onConnect }, Event)
end

function Event:Connect(callback)
	local event = self
	local connection = { Connected = true, _callback = callback }
	function connection:Disconnect()
		self.Connected = false
		local index = table.find(event._connections, self)
		if index then
			table.remove(event._connections, index)
		end
	end
	table.insert(self._connections, connection)
	if self._onConnect then
		self._onConnect()
	end
	return connection
end

function Event:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Event:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

-- Runs every handler now, each on its own thread. Errors are logged like
-- Roblox's output rather than crashing the simulation.
function Event:_fire(...)
	local world = self._world
	for _, connection in table.clone(self._connections) do
		if connection.Connected then
			task.spawn(function(...)
				local ok, message = xpcall(connection._callback, debug.traceback, ...)
				if not ok then
					world:log("error", tostring(message))
				end
			end, ...)
		end
	end
end

-- Roblox's default (deferred) signal behavior: handlers connected by the time
-- the deferral runs are invoked.
function Event:_fireDeferred(...)
	local args = table.pack(...)
	task.defer(function()
		self:_fire(table.unpack(args, 1, args.n))
	end)
end

---------------------------------------------------------------------------
-- Instances
---------------------------------------------------------------------------

local SUPERCLASS = {
	RemoteEvent = "BaseRemoteEvent",
	UnreliableRemoteEvent = "BaseRemoteEvent",
	BaseRemoteEvent = "Instance",
	RemoteFunction = "Instance",
	Folder = "Instance",
	BoolValue = "ValueBase",
	ValueBase = "Instance",
	ModuleScript = "LuaSourceContainer",
	LocalScript = "Script",
	Script = "LuaSourceContainer",
	LuaSourceContainer = "Instance",
	Player = "Instance",
	DataModel = "Instance",
	ReplicatedStorage = "Instance",
	ServerScriptService = "Instance",
	Players = "Instance",
	RunService = "Instance",
	StarterPlayer = "Instance",
	StarterPlayerScripts = "Instance",
}

local CREATABLE = {
	RemoteEvent = true,
	UnreliableRemoteEvent = true,
	RemoteFunction = true,
	Folder = true,
	BoolValue = true,
	ModuleScript = true,
	Script = true,
	LocalScript = true,
}

local Methods = {}
local InstanceMT = {}

local function isInstance(value)
	return type(value) == "table" and getmetatable(value) == InstanceMT
end

InstanceMT.__index = function(self, key)
	local method = Methods[key]
	if method then
		return method
	end
	if key == "Parent" then
		return rawget(self, "_parent")
	end
	for _, child in rawget(self, "_children") do
		if rawget(child, "Name") == key then
			return child
		end
	end
	error(
		string.format(
			"%s is not a valid member of %s %q",
			tostring(key),
			rawget(self, "ClassName"),
			Methods.GetFullName(self)
		),
		2
	)
end

InstanceMT.__tostring = function(self)
	return rawget(self, "Name")
end

local function isDescendantOf(instance, ancestor)
	local current = rawget(instance, "_parent")
	while current do
		if current == ancestor then
			return true
		end
		current = rawget(current, "_parent")
	end
	return false
end

local function setParent(instance, parent)
	assert(parent == nil or isInstance(parent), "Parent must be an Instance or nil")
	local old = rawget(instance, "_parent")
	if old then
		local siblings = rawget(old, "_children")
		table.remove(siblings, table.find(siblings, instance))
	end
	rawset(instance, "_parent", parent)
	if parent then
		table.insert(rawget(parent, "_children"), instance)
		rawget(parent, "_childAdded"):_fire(instance)
		local world = rawget(instance, "_world")
		if world.isServer and isDescendantOf(instance, world.game.ReplicatedStorage) then
			world.sim:_replicate(instance)
		end
	end
end

InstanceMT.__newindex = function(self, key, value)
	if key == "Parent" then
		setParent(self, value)
	else
		rawset(self, key, value)
	end
end

local function newInstance(world, className, name)
	local fields = {
		ClassName = className,
		Name = name or className,
		_world = world,
		_children = {},
		_attributes = {},
		_twins = {}, -- server instance -> { [Player] = client instance }
		_childAdded = newEvent(world),
	}
	if className == "RemoteEvent" or className == "UnreliableRemoteEvent" then
		fields.OnServerEvent = newEvent(world)
		fields._queue = {}
		fields.OnClientEvent = newEvent(world, function()
			-- Events that arrived before any listener are delivered once one connects.
			local queue = fields._queue
			if #queue > 0 then
				fields._queue = {}
				task.defer(function()
					for _, args in queue do
						fields.OnClientEvent:_fire(table.unpack(args, 1, args.n))
					end
				end)
			end
		end)
	elseif className == "BoolValue" then
		fields.Value = false
	elseif className == "Players" then
		fields.PlayerAdded = newEvent(world)
		fields.PlayerRemoving = newEvent(world)
	end
	return setmetatable(fields, InstanceMT)
end

function Methods:IsA(className)
	local current = rawget(self, "ClassName")
	while current do
		if current == className then
			return true
		end
		current = SUPERCLASS[current]
	end
	return false
end

function Methods:FindFirstChild(name)
	for _, child in rawget(self, "_children") do
		if rawget(child, "Name") == name then
			return child
		end
	end
	return nil
end

function Methods:WaitForChild(name, timeout)
	local existing = Methods.FindFirstChild(self, name)
	if existing then
		return existing
	end
	local thread = coroutine.running()
	local done = false
	local connection
	connection = rawget(self, "_childAdded"):Connect(function(child)
		if not done and rawget(child, "Name") == name then
			done = true
			connection:Disconnect()
			task.spawn(thread, child)
		end
	end)
	if timeout then
		task.delay(timeout * TIMEOUT_SCALE, function()
			if not done then
				done = true
				connection:Disconnect()
				task.spawn(thread, nil)
			end
		end)
	end
	return coroutine.yield()
end

function Methods:GetChildren()
	return table.clone(rawget(self, "_children"))
end

function Methods:GetDescendants()
	local result = {}
	local function visit(instance)
		for _, child in rawget(instance, "_children") do
			table.insert(result, child)
			visit(child)
		end
	end
	visit(self)
	return result
end

function Methods:GetFullName()
	local names = {}
	local current = self
	while current and rawget(current, "ClassName") ~= "DataModel" do
		table.insert(names, 1, rawget(current, "Name"))
		current = rawget(current, "_parent")
	end
	return table.concat(names, ".")
end

function Methods:SetAttribute(name, value)
	rawget(self, "_attributes")[name] = value
end

function Methods:GetAttribute(name)
	return rawget(self, "_attributes")[name]
end

function Methods:GetService(name)
	local service = Methods.FindFirstChild(self, name)
	if not service then
		error(string.format("%s is not a valid Service name", tostring(name)), 2)
	end
	return service
end

function Methods:IsServer()
	return rawget(self, "_world").isServer
end

function Methods:IsClient()
	return not rawget(self, "_world").isServer
end

function Methods:GetPlayers()
	local players = {}
	for _, child in rawget(self, "_children") do
		if rawget(child, "ClassName") == "Player" then
			table.insert(players, child)
		end
	end
	return players
end

---------------------------------------------------------------------------
-- Networking
---------------------------------------------------------------------------

-- Copies values the way Roblox serializes remote arguments. Instances are
-- mapped to their counterpart on the receiving side (nil if absent there).
local function transfer(value, toPlayer)
	if isInstance(value) then
		if toPlayer then
			return rawget(value, "_twins")[toPlayer]
		end
		return rawget(value, "_twin")
	end
	local kind = type(value)
	if kind == "table" then
		local copy = {}
		for key, item in value do
			local copiedKey = transfer(key, toPlayer)
			if copiedKey ~= nil then
				copy[copiedKey] = transfer(item, toPlayer)
			end
		end
		return copy
	elseif kind == "function" or kind == "thread" or kind == "userdata" then
		return nil
	end
	return value
end

local function deliverToClient(remote, args)
	local event = rawget(remote, "OnClientEvent")
	if #event._connections > 0 then
		event:_fire(table.unpack(args, 1, args.n))
	else
		table.insert(rawget(remote, "_queue"), args)
	end
end

function Methods:FireServer(...)
	local world = rawget(self, "_world")
	assert(not world.isServer, "FireServer can only be called from the client")
	local serverRemote = rawget(self, "_twin")
	local player = world.player
	local args = transfer(table.pack(...), nil)
	world.sim:_send(function()
		rawget(serverRemote, "OnServerEvent"):_fire(player, table.unpack(args, 1, args.n))
	end)
end

function Methods:FireClient(player, ...)
	local world = rawget(self, "_world")
	assert(world.isServer, "FireClient can only be called from the server")
	if not (isInstance(player) and rawget(player, "ClassName") == "Player") then
		error("FireClient: player argument must be a Player object", 2)
	end
	local args = transfer(table.pack(...), player)
	world.sim:_send(function()
		local clientRemote = rawget(self, "_twins")[player]
		if clientRemote then
			deliverToClient(clientRemote, args)
		end
	end)
end

function Methods:FireAllClients(...)
	for _, player in rawget(self, "_world").game.Players:GetPlayers() do
		Methods.FireClient(self, player, ...)
	end
end

function Methods:InvokeServer(...)
	local world = rawget(self, "_world")
	assert(not world.isServer, "InvokeServer can only be called from the client")
	local serverRemote = rawget(self, "_twin")
	local player = world.player
	local sim = world.sim
	local args = transfer(table.pack(...), nil)
	local thread = coroutine.running()
	sim:_send(function()
		task.spawn(function()
			-- Roblox holds invocations until a callback is assigned.
			while rawget(serverRemote, "OnServerInvoke") == nil do
				sim.taskLib.wait()
			end
			local results =
				table.pack(pcall(rawget(serverRemote, "OnServerInvoke"), player, table.unpack(args, 1, args.n)))
			local reply = transfer(results, player)
			sim:_send(function()
				task.spawn(thread, reply)
			end)
		end)
	end)
	local reply = coroutine.yield()
	if not reply[1] then
		error(reply[2], 0)
	end
	return table.unpack(reply, 2, reply.n)
end

---------------------------------------------------------------------------
-- Worlds (one DataModel each)
---------------------------------------------------------------------------

local World = {}
World.__index = World

local function newWorld(sim, isServer, name)
	local world = setmetatable({
		sim = sim,
		isServer = isServer,
		name = name,
		modules = {},
	}, World)
	local game = newInstance(world, "DataModel", "game")
	world.game = game
	local services = { "ReplicatedStorage", "Players", "RunService" }
	if isServer then
		table.insert(services, "ServerScriptService")
		table.insert(services, "StarterPlayer")
	end
	for _, service in services do
		newInstance(world, service, service).Parent = game
	end
	if isServer then
		newInstance(world, "StarterPlayerScripts", "StarterPlayerScripts").Parent = game.StarterPlayer
	end
	world.InstanceLib = table.freeze({
		new = function(className, parent)
			if not CREATABLE[className] then
				error(string.format('Unable to create an Instance of type "%s"', tostring(className)), 2)
			end
			local instance = newInstance(world, className)
			if parent then
				instance.Parent = parent
			end
			return instance
		end,
	})
	return world
end

function World:log(kind, ...)
	local parts = table.pack(...)
	for i = 1, parts.n do
		parts[i] = tostring(parts[i])
	end
	local message = table.concat(parts, " ", 1, parts.n)
	table.insert(self.sim.logs, { peer = self.name, kind = kind, message = message })
	if self.sim.verbose then
		print(string.format("[%s] %s: %s", self.name, kind, message))
	end
end

function World:environment(scriptInstance)
	local world = self
	return {
		script = scriptInstance,
		game = world.game,
		Instance = world.InstanceLib,
		task = world.sim.taskLib,
		shared = world.sim.shared,
		typeof = function(value)
			if isInstance(value) then
				return "Instance"
			end
			return builtinTypeof(value)
		end,
		require = function(module)
			return world:require(module)
		end,
		print = function(...)
			world:log("print", ...)
		end,
		warn = function(...)
			world:log("warn", ...)
		end,
	}
end

function World:compile(scriptInstance)
	local source = rawget(scriptInstance, "Source")
	assert(type(source) == "string", "script has no source: " .. Methods.GetFullName(scriptInstance))
	return luau.load(source, {
		debugName = Methods.GetFullName(scriptInstance),
		environment = self:environment(scriptInstance),
	})
end

function World:require(module)
	if not (isInstance(module) and rawget(module, "ClassName") == "ModuleScript") then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local entry = self.modules[module]
	if entry then
		if entry.state == "loading" then
			error("Requested module was required recursively", 2)
		elseif entry.state == "failed" then
			error("Requested module experienced an error while loading", 2)
		end
		return entry.value
	end
	entry = { state = "loading" }
	self.modules[module] = entry
	local results = table.pack(pcall(self:compile(module)))
	if not results[1] then
		entry.state = "failed"
		error(results[2], 0)
	end
	if results.n ~= 2 then
		entry.state = "failed"
		error("Module code did not return exactly one value", 2)
	end
	entry.state = "loaded"
	entry.value = results[2]
	return entry.value
end

function World:run(scriptInstance)
	local chunk = self:compile(scriptInstance)
	task.spawn(function()
		local ok, message = xpcall(chunk, debug.traceback)
		if not ok then
			self:log("error", tostring(message))
		end
	end)
end

---------------------------------------------------------------------------
-- Loading source trees (Rojo conventions)
---------------------------------------------------------------------------

local function scriptClassFor(fileName)
	if string.match(fileName, "%.server%.luau?$") then
		return "Script", (string.gsub(fileName, "%.server%.luau?$", ""))
	elseif string.match(fileName, "%.client%.luau?$") then
		return "LocalScript", (string.gsub(fileName, "%.client%.luau?$", ""))
	elseif string.match(fileName, "%.luau?$") then
		return "ModuleScript", (string.gsub(fileName, "%.luau?$", ""))
	end
	return nil
end

local function loadTree(world, path, name)
	if fs.isDir(path) then
		name = name or string.match(path, "[^/\\]+$")
		local entries = fs.readDir(path)
		table.sort(entries)
		local instance
		for _, entry in entries do
			local className = scriptClassFor(entry)
			if className and string.match(entry, "^init%.") then
				instance = newInstance(world, className, name)
				instance.Source = fs.readFile(path .. "/" .. entry)
			end
		end
		instance = instance or newInstance(world, "Folder", name)
		for _, entry in entries do
			if not string.match(entry, "^init%.") then
				local child = loadTree(world, path .. "/" .. entry, nil)
				if child then
					child.Parent = instance
				end
			end
		end
		return instance
	end
	local fileName = string.match(path, "[^/\\]+$")
	local className, baseName = scriptClassFor(fileName)
	if not className then
		return nil
	end
	local instance = newInstance(world, className, name or baseName)
	instance.Source = fs.readFile(path)
	return instance
end

---------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------

local Sim = {}
Sim.__index = Sim

export type Sim = typeof(setmetatable({} :: any, Sim))

function Sim.new(options: { verbose: boolean? }?)
	local sim = setmetatable({
		logs = {},
		shared = {},
		clients = {},
		players = {},
		stopped = false,
		verbose = options and options.verbose or false,
		nextUserId = 1,
	}, Sim)
	local function checkStopped()
		if sim.stopped then
			error("simulation stopped", 0)
		end
	end
	-- Scripts get a task library whose waits end once the simulation stops, so
	-- infinite loops (like the example's Start) do not outlive their test.
	sim.taskLib = table.freeze({
		spawn = task.spawn,
		defer = task.defer,
		delay = task.delay,
		cancel = task.cancel,
		wait = function(seconds)
			checkStopped()
			local elapsed = task.wait(seconds)
			checkStopped()
			return elapsed
		end,
	})
	sim.server = newWorld(sim, true, "server")
	return sim
end

function Sim:_send(callback)
	if self.stopped then
		return
	end
	task.defer(function()
		if not self.stopped then
			callback()
		end
	end)
end

local function cloneLinked(serverInstance, clientParent, player, clientWorld)
	local twins = rawget(serverInstance, "_twins")
	if twins[player] then
		return
	end
	local copy = newInstance(clientWorld, rawget(serverInstance, "ClassName"), rawget(serverInstance, "Name"))
	for _, field in { "Source", "Value", "UserId" } do
		rawset(copy, field, rawget(serverInstance, field))
	end
	rawset(copy, "_attributes", table.clone(rawget(serverInstance, "_attributes")))
	twins[player] = copy
	rawset(copy, "_twin", serverInstance)
	-- Children first, so the subtree appears to the client all at once.
	for _, child in rawget(serverInstance, "_children") do
		cloneLinked(child, copy, player, clientWorld)
	end
	copy.Parent = clientParent
end

function Sim:_replicate(instance)
	for player, client in self.clients do
		self:_send(function()
			local parent = rawget(instance, "_parent")
			local parentTwin = parent and rawget(parent, "_twins")[player]
			if parentTwin and self.clients[player] then
				cloneLinked(instance, parentTwin, player, client)
			end
		end)
	end
end

-- Loads a file or directory into the server DataModel using Rojo conventions.
function Sim:mount(parent, path: string, name: string?)
	local instance = loadTree(self.server, path, name)
	instance.Parent = parent
	return instance
end

function Sim:module(parent, name: string, source: string)
	local instance = newInstance(self.server, "ModuleScript", name)
	instance.Source = source
	instance.Parent = parent
	return instance
end

function Sim:script(parent, name: string, source: string, className: string?)
	local instance = newInstance(self.server, className or "Script", name)
	instance.Source = source
	instance.Parent = parent
	return instance
end

function Sim:folder(parent, name: string)
	local existing = Methods.FindFirstChild(parent, name)
	if existing then
		return existing
	end
	local instance = newInstance(self.server, "Folder", name)
	instance.Parent = parent
	return instance
end

function Sim:runServerScripts()
	for _, descendant in Methods.GetDescendants(self.server.game.ServerScriptService) do
		if rawget(descendant, "ClassName") == "Script" then
			self.server:run(descendant)
		end
	end
end

function Sim:addPlayer(name: string)
	local server = self.server
	local player = newInstance(server, "Player", name)
	player.UserId = self.nextUserId
	self.nextUserId += 1

	local client = newWorld(self, false, name)
	client.player = player
	self.clients[player] = client
	table.insert(self.players, player)

	-- Initial replication: the client sees ReplicatedStorage before any of its
	-- scripts run.
	rawget(server.game.ReplicatedStorage, "_twins")[player] = client.game.ReplicatedStorage
	for _, child in rawget(server.game.ReplicatedStorage, "_children") do
		cloneLinked(child, client.game.ReplicatedStorage, player, client)
	end

	-- The joining client sees everyone already in the game.
	for _, other in server.game.Players:GetPlayers() do
		cloneLinked(other, client.game.Players, player, client)
	end
	local localPlayer = newInstance(client, "Player", name)
	localPlayer.UserId = player.UserId
	rawset(localPlayer, "_twin", player)
	rawget(player, "_twins")[player] = localPlayer
	rawset(client.game.Players, "LocalPlayer", localPlayer)
	localPlayer.Parent = client.game.Players

	player.Parent = server.game.Players
	server.game.Players.PlayerAdded:_fireDeferred(player)

	-- Existing clients see the new player join.
	for otherPlayer, otherClient in self.clients do
		if otherPlayer ~= player then
			self:_send(function()
				cloneLinked(player, otherClient.game.Players, otherPlayer, otherClient)
				otherClient.game.Players.PlayerAdded:_fire(rawget(player, "_twins")[otherPlayer])
			end)
		end
	end

	-- StarterPlayerScripts are copied into the player's PlayerScripts and run.
	local playerScripts = newInstance(client, "Folder", "PlayerScripts")
	playerScripts.Parent = localPlayer
	for _, child in rawget(server.game.StarterPlayer.StarterPlayerScripts, "_children") do
		cloneLinked(child, playerScripts, player, client)
	end
	self:_send(function()
		for _, descendant in Methods.GetDescendants(playerScripts) do
			if rawget(descendant, "ClassName") == "LocalScript" then
				client:run(descendant)
			end
		end
	end)
	return player
end

function Sim:removePlayer(player)
	local server = self.server
	server.game.Players.PlayerRemoving:_fireDeferred(player)
	for otherPlayer, otherClient in self.clients do
		if otherPlayer ~= player then
			self:_send(function()
				local twin = rawget(player, "_twins")[otherPlayer]
				if twin then
					otherClient.game.Players.PlayerRemoving:_fire(twin)
				end
			end)
		end
	end
	task.defer(function()
		player.Parent = nil
		self.clients[player] = nil
		table.remove(self.players, table.find(self.players, player))
	end)
end

function Sim:client(player)
	return self.clients[player]
end

-- The client DataModel's copy of a server instance.
function Sim:twin(instance, player)
	return rawget(instance, "_twins")[player]
end

function Sim:wait(seconds: number?)
	task.wait(seconds or 0.1)
end

function Sim:stop()
	self.stopped = true
end

-- Log entries matching a peer ("server", a player name, or nil for any), a
-- kind ("print", "warn", "error", or nil for any), and a plain-text substring.
function Sim:logsMatching(peer: string?, kind: string?, text: string?)
	local matches = {}
	for _, entry in self.logs do
		if
			(peer == nil or entry.peer == peer)
			and (kind == nil or entry.kind == kind)
			and (text == nil or string.find(entry.message, text, 1, true))
		then
			table.insert(matches, entry)
		end
	end
	return matches
end

function Sim:dumpLogs()
	for _, entry in self.logs do
		print(string.format("  [%s] %s: %s", entry.peer, entry.kind, entry.message))
	end
end

return Sim
