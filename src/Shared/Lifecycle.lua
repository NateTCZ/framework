--!strict
-- Lifecycle shared by services (server) and controllers (client).

local Players = game:GetService("Players")

local Lifecycle = {}

local HOOKS = { "Init", "Start", "PlayerAdded", "PlayerRemoving" }

-- Rejects non-function lifecycle members before anything runs, so a
-- misconfigured object fails Framework.Start() synchronously. Errors are
-- reported at the caller of Framework.Start().
function Lifecycle.validate(order: { any })
	for _, object in order do
		for _, hook in HOOKS do
			if object[hook] ~= nil and type(object[hook]) ~= "function" then
				error(string.format("[Framework] %s.%s must be a function.", object.Name, hook), 3)
			end
		end
	end
end

-- Every Init runs to completion, in registration order, before the next begins.
function Lifecycle.init(order: { any })
	for _, object in order do
		if object.Init then
			local ok, message = pcall(object.Init, object)
			if not ok then
				error(string.format("[Framework] %s:Init() failed: %s", object.Name, tostring(message)), 3)
			end
		end
	end
end

local function spawnHook(object: any, hook: string, ...: any)
	task.spawn(function(...)
		local ok, message = xpcall(object[hook], debug.traceback, object, ...)
		if not ok then
			warn(string.format("[Framework] %s:%s() failed: %s", object.Name, hook, tostring(message)))
		end
	end, ...)
end

-- Each Start runs on its own thread (in registration order) so a long-running
-- or yielding Start cannot block the objects registered after it. PlayerAdded
-- then runs for every player already in the game and for each one who joins.
function Lifecycle.start(order: { any })
	local added, removing = {}, {}
	for _, object in order do
		if object.Start then
			spawnHook(object, "Start")
		end
		if object.PlayerAdded then
			table.insert(added, object)
		end
		if object.PlayerRemoving then
			table.insert(removing, object)
		end
	end

	if #added > 0 then
		-- A player can appear both in GetPlayers() and in a pending PlayerAdded
		-- event; track who was handled so each hook runs once per player.
		local handled = setmetatable({}, { __mode = "k" }) :: any
		local function onPlayerAdded(player: Player)
			if handled[player] then
				return
			end
			handled[player] = true
			for _, object in added do
				spawnHook(object, "PlayerAdded", player)
			end
		end
		Players.PlayerAdded:Connect(onPlayerAdded)
		for _, player in Players:GetPlayers() do
			onPlayerAdded(player)
		end
	end
	if #removing > 0 then
		Players.PlayerRemoving:Connect(function(player: Player)
			for _, object in removing do
				spawnHook(object, "PlayerRemoving", player)
			end
		end)
	end
end

return Lifecycle
