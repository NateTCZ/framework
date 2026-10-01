-- End-to-end tests: the real Framework source (and the example place) running
-- on a simulated server with simulated players. See tests/sim/Roblox.luau.

local Sim = require("./sim/Roblox")

local HEADER = 'local Framework = require(game:GetService("ReplicatedStorage").Packages.Framework)\n'
	.. "local function err(fn, ...) local ok, message = pcall(fn, ...) "
	.. 'return if ok then "no error" else tostring(message) end\n'

local function newSim()
	local sim = Sim.new()
	local game = sim.server.game
	sim:mount(sim:folder(game.ReplicatedStorage, "Packages"), "src", "Framework")
	sim:folder(game.ServerScriptService, "Services")
	sim:folder(game.StarterPlayer.StarterPlayerScripts, "Controllers")
	return sim
end

local function service(sim, name: string, body: string)
	sim:module(sim.server.game.ServerScriptService.Services, name, HEADER .. body)
end

local function controller(sim, name: string, body: string)
	sim:module(sim.server.game.StarterPlayer.StarterPlayerScripts.Controllers, name, HEADER .. body)
end

-- Server bootstrap; `body` runs in the same script, by default AddServices + Start.
local function serverMain(sim, body: string?)
	sim:script(
		sim.server.game.ServerScriptService,
		"Main",
		HEADER .. (body or "Framework.AddServices(script.Parent.Services)\nFramework.Start()\n")
	)
	sim:runServerScripts()
end

-- Client bootstrap, copied to each player that joins afterward.
local function clientMain(sim, body: string?)
	sim:script(
		sim.server.game.StarterPlayer.StarterPlayerScripts,
		"Main",
		HEADER .. (body or "Framework.AddControllers(script.Parent.Controllers)\nFramework.Start()\n"),
		"LocalScript"
	)
end

local function contains(expect, actual: any, text: string, label: string?)
	expect.truthy(
		type(actual) == "string" and string.find(actual, text, 1, true) ~= nil,
		string.format('%s: expected text containing "%s", got "%s"', label or "text", text, tostring(actual))
	)
end

local function count(sim, peer: string?, kind: string?, text: string?): number
	return #sim:logsMatching(peer, kind, text)
end

-- Wraps a case so the simulation always stops (ending infinite loops) and its
-- log is printed when the case fails.
local function scenario(case: (expect: any, sim: any) -> ())
	return function(expect)
		local sim = newSim()
		local ok, message = pcall(case, expect, sim)
		sim:stop()
		if not ok then
			print("  Simulation log:")
			sim:dumpLogs()
			error(message, 0)
		end
	end
end

return {
	["example place runs end to end with two players"] = scenario(function(expect, sim)
		local game = sim.server.game
		sim:mount(game.ReplicatedStorage, "examples/shared", "FrameworkExample")
		sim:mount(game.ServerScriptService, "examples/server", "FrameworkExample")
		sim:mount(game.StarterPlayer.StarterPlayerScripts, "examples/client", "FrameworkExample")
		sim:runServerScripts()
		local player1 = sim:addPlayer("Player1")
		sim:addPlayer("Player2")
		sim:wait(0.5)

		expect.equal(count(sim, nil, "error"), 0, "errors")
		expect.equal(count(sim, nil, "warn"), 0, "warnings")
		expect.equal(count(sim, "server", "print", "TestService started after every service finished Init"), 1)
		for _, name in { "Player1", "Player2" } do
			expect.equal(count(sim, name, "print", "Hello from SecondaryService"), 1, name .. " Method")
			expect.equal(count(sim, name, "print", "Server update: Hello from the client"), 1, name .. " Signal")
			expect.equal(count(sim, "server", "print", name .. " Hello from the client"), 1, name .. " ClientSignal")
			expect.truthy(count(sim, name, "print", "Score: 0") >= 1, name .. " initial Property value")
			expect.equal(count(sim, name, "print", "Score: 1"), 1, name .. " Property update")
		end

		local network = game.ReplicatedStorage.__FrameworkNetwork.TestService
		expect.equal(network.Signals.Updated.ClassName, "RemoteEvent")
		expect.equal(network.Signals.Pulse.ClassName, "UnreliableRemoteEvent")
		expect.equal(sim:twin(network.Signals.Pulse, player1).ClassName, "UnreliableRemoteEvent", "client copy")

		sim:removePlayer(player1)
		sim:wait(0.1)
		expect.equal(count(sim, "server", "print", "Player1 left"), 1, "PlayerRemoving")
	end),

	["server registration and API misuse errors"] = scenario(function(expect, sim)
		serverMain(
			sim,
			[[
			Framework.CreateService({ Name = "A" })
			shared.duplicate = err(Framework.CreateService, { Name = "A" })
			shared.emptyName = err(Framework.CreateService, { Name = "" })
			shared.badEndpoint = err(Framework.CreateService, { Name = "B", Client = { Foo = function() end } })
			shared.reserved = err(Framework.CreateService, { Name = "C", Client = { Server = Framework.Signal() } })
			shared.unknown = err(Framework.GetService, "Nope")
			shared.getController = err(Framework.GetController, "X")
			shared.addControllers = err(Framework.AddControllers, script)
			shared.createController = err(Framework.CreateController, { Name = "X" })
			Framework.Start()
			shared.twice = err(Framework.Start)
			shared.late = err(Framework.CreateService, { Name = "D" })
		]]
		)
		sim:wait(0.1)
		local r = sim.shared
		contains(expect, r.duplicate, 'Service "A" is already registered', "duplicate")
		contains(expect, r.emptyName, "non-empty Name", "emptyName")
		contains(expect, r.badEndpoint, "Framework.Property()", "badEndpoint")
		contains(expect, r.reserved, "Client.Server is reserved", "reserved")
		contains(expect, r.unknown, 'Could not find service "Nope"', "unknown")
		contains(expect, r.getController, "client-only", "getController")
		contains(expect, r.addControllers, "client-only", "addControllers")
		contains(expect, r.createController, "client-only", "createController")
		contains(expect, r.twice, "already been called", "twice")
		contains(expect, r.late, "Cannot register services after Framework.Start()", "late")
	end),

	["client registration and API misuse errors"] = scenario(function(expect, sim)
		serverMain(sim)
		clientMain(
			sim,
			[[
			Framework.CreateController({ Name = "A" })
			shared.duplicate = err(Framework.CreateController, { Name = "A" })
			shared.unknownController = err(Framework.GetController, "Nope")
			shared.createService = err(Framework.CreateService, { Name = "S" })
			shared.addServices = err(Framework.AddServices, script)
			shared.unknownService = err(Framework.GetService, "Nope")
			Framework.Start()
			shared.late = err(Framework.CreateController, { Name = "B" })
		]]
		)
		sim:addPlayer("Player1")
		sim:wait(1)
		local r = sim.shared
		contains(expect, r.duplicate, 'Controller "A" is already registered', "duplicate")
		contains(expect, r.unknownController, 'Could not find controller "Nope"', "unknownController")
		contains(expect, r.createService, "server-only", "createService")
		contains(expect, r.addServices, "server-only", "addServices")
		contains(expect, r.unknownService, 'Could not find service "Nope"', "unknownService")
		contains(expect, r.late, "Cannot register controllers after Framework.Start()", "late")
	end),

	["every Init finishes, in order, before any Start"] = scenario(function(expect, sim)
		sim.shared.order = {}
		for _, name in { "A", "B" } do
			service(
				sim,
				name,
				string.format(
					[[
				local S = Framework.CreateService({ Name = "%s" })
				function S:Init()
					table.insert(shared.order, "%s.Init begin")
					task.wait(0.05)
					table.insert(shared.order, "%s.Init end")
				end
				function S:Start()
					table.insert(shared.order, "%s.Start")
				end
				return S
			]],
					name,
					name,
					name,
					name
				)
			)
		end
		serverMain(sim)
		sim:wait(0.3)
		expect.equal(
			table.concat(sim.shared.order, ", "),
			"A.Init begin, A.Init end, B.Init begin, B.Init end, A.Start, B.Start"
		)
	end),

	["a looping Start does not block others and a failing Start only warns"] = scenario(function(expect, sim)
		service(
			sim,
			"A",
			[[
			local S = Framework.CreateService({ Name = "A" })
			function S:Start() while true do task.wait(0.01) end end
			return S
		]]
		)
		service(
			sim,
			"B",
			[[
			local S = Framework.CreateService({ Name = "B" })
			function S:Start() error("B exploded") end
			return S
		]]
		)
		service(
			sim,
			"C",
			[[
			local S = Framework.CreateService({ Name = "C" })
			function S:Start() shared.cStarted = true end
			return S
		]]
		)
		serverMain(sim, "Framework.AddServices(script.Parent.Services)\nFramework.Start()\nshared.returned = true\n")
		sim:wait(0.2)
		expect.equal(sim.shared.returned, true, "Framework.Start() returned")
		expect.equal(sim.shared.cStarted, true, "C started")
		expect.equal(count(sim, "server", "warn", "B:Start() failed"), 1, "warning for B")
		expect.equal(count(sim, "server", "warn", "B exploded"), 1, "warning includes the error")
		expect.equal(count(sim, nil, "error"), 0, "uncaught errors")
	end),

	["an Init error stops Framework.Start()"] = scenario(function(expect, sim)
		service(
			sim,
			"A",
			[[
			local S = Framework.CreateService({ Name = "A" })
			function S:Init() error("bad init") end
			function S:Start() shared.started = true end
			return S
		]]
		)
		serverMain(sim, "Framework.AddServices(script.Parent.Services)\nshared.result = err(Framework.Start)\n")
		sim:wait(0.1)
		contains(expect, sim.shared.result, "A:Init() failed")
		contains(expect, sim.shared.result, "bad init")
		expect.equal(sim.shared.started, nil, "Start must not run")
	end),

	["non-function lifecycle members are rejected before any Init runs"] = scenario(function(expect, sim)
		service(
			sim,
			"A",
			[[
			local S = Framework.CreateService({ Name = "A" })
			S.PlayerAdded = 5
			return S
		]]
		)
		service(
			sim,
			"B",
			[[
			local S = Framework.CreateService({ Name = "B" })
			function S:Init() shared.bInit = true end
			return S
		]]
		)
		serverMain(sim, "Framework.AddServices(script.Parent.Services)\nshared.result = err(Framework.Start)\n")
		sim:wait(0.1)
		contains(expect, sim.shared.result, "A.PlayerAdded must be a function")
		expect.equal(sim.shared.bInit, nil, "B:Init must not run")
	end),

	["PlayerAdded runs once per player, including players present before Start"] = scenario(function(expect, sim)
		sim.shared.added = {}
		sim.shared.removed = {}
		sim.shared.clientSaw = {}
		service(
			sim,
			"Tracker",
			[[
			local S = Framework.CreateService({ Name = "Tracker" })
			function S:PlayerAdded(player)
				shared.added[player.Name] = (shared.added[player.Name] or 0) + 1
			end
			function S:PlayerRemoving(player)
				table.insert(shared.removed, player.Name)
			end
			return S
		]]
		)
		controller(
			sim,
			"Watcher",
			[[
			local C = Framework.CreateController({ Name = "Watcher" })
			function C:PlayerAdded(player)
				local key = game:GetService("Players").LocalPlayer.Name .. " saw " .. player.Name
				shared.clientSaw[key] = (shared.clientSaw[key] or 0) + 1
			end
			return C
		]]
		)
		clientMain(sim)
		-- Player1 joins in the same frame the server starts, so it is both in
		-- GetPlayers() and in a pending PlayerAdded event.
		local player1 = sim:addPlayer("Player1")
		serverMain(sim)
		sim:wait(0.1)
		sim:addPlayer("Player2")
		sim:wait(0.2)

		expect.equal(sim.shared.added.Player1, 1, "server saw Player1 once")
		expect.equal(sim.shared.added.Player2, 1, "server saw Player2 once")
		expect.equal(sim.shared.clientSaw["Player1 saw Player1"], 1)
		expect.equal(sim.shared.clientSaw["Player1 saw Player2"], 1)
		expect.equal(sim.shared.clientSaw["Player2 saw Player1"], 1)
		expect.equal(sim.shared.clientSaw["Player2 saw Player2"], 1)

		sim:removePlayer(player1)
		sim:wait(0.1)
		expect.equal(table.concat(sim.shared.removed, ","), "Player1", "PlayerRemoving")
	end),

	["OnStart yields until startup finishes"] = scenario(function(expect, sim)
		service(
			sim,
			"A",
			[[
			local S = Framework.CreateService({ Name = "A" })
			function S:Init() task.wait(0.05) shared.serverInit = true end
			return S
		]]
		)
		controller(
			sim,
			"C",
			[[
			local C = Framework.CreateController({ Name = "C" })
			function C:Init() task.wait(0.05) shared.clientInit = true end
			return C
		]]
		)
		local onStartCheck = [[
			task.spawn(function()
				Framework.OnStart()
				shared.%s = shared.%s == true
			end)
		]]
		serverMain(
			sim,
			string.format(onStartCheck, "serverWaited", "serverInit")
				.. "Framework.AddServices(script.Parent.Services)\nFramework.Start()\n"
				.. "Framework.OnStart()\nshared.serverImmediate = true\n"
		)
		clientMain(
			sim,
			string.format(onStartCheck, "clientWaited", "clientInit")
				.. "Framework.AddControllers(script.Parent.Controllers)\nFramework.Start()\n"
				.. "Framework.OnStart()\nshared.clientImmediate = true\n"
		)
		sim:addPlayer("Player1")
		sim:wait(0.3)
		expect.equal(sim.shared.serverWaited, true, "server OnStart waited for Init")
		expect.equal(sim.shared.serverImmediate, true, "server OnStart after Start returns")
		expect.equal(sim.shared.clientWaited, true, "client OnStart waited for Init")
		expect.equal(sim.shared.clientImmediate, true, "client OnStart after Start returns")
	end),

	["ClientSignal rate limits, validates, and throttles warnings"] = scenario(function(expect, sim)
		service(
			sim,
			"Shop",
			[[
			local Shop = Framework.CreateService({
				Name = "Shop",
				Client = {
					Spam = Framework.ClientSignal({ RateLimit = 5, Window = 1 }),
					Checked = Framework.ClientSignal({
						Validate = function(_player, value)
							return type(value) == "string", "expected a string"
						end,
					}),
				},
			})
			function Shop.Client:Spam(_player)
				shared.spam = (shared.spam or 0) + 1
			end
			function Shop.Client:Checked(_player, value)
				shared.checked = (shared.checked or 0) + 1
				shared.checkedValue = value
			end
			return Shop
		]]
		)
		serverMain(sim)
		clientMain(
			sim,
			[[
			local Shop = Framework.GetService("Shop")
			for _ = 1, 20 do
				Shop.Spam:Fire()
			end
			Shop.Checked:Fire(1)
			Shop.Checked:Fire({})
			Shop.Checked:Fire(nil)
			Shop.Checked:Fire("ok")
		]]
		)
		sim:addPlayer("Player1")
		sim:wait(0.3)
		expect.equal(sim.shared.spam, 5, "Spam calls accepted")
		expect.equal(count(sim, "server", "warn", "Rejected Shop.Spam from Player1 (rate limit)"), 1, "Spam warnings")
		expect.equal(sim.shared.checked, 1, "Checked calls accepted")
		expect.equal(sim.shared.checkedValue, "ok")
		expect.equal(count(sim, "server", "warn", "Rejected Shop.Checked"), 1, "Checked warnings")
		expect.equal(count(sim, "server", "warn", "expected a string"), 1, "warning includes the reason")
	end),

	["Method returns values, hides server errors, and enforces limits"] = scenario(function(expect, sim)
		service(
			sim,
			"Api",
			[[
			local Api = Framework.CreateService({
				Name = "Api",
				Client = {
					Echo = Framework.Method(),
					Fail = Framework.Method(),
					Slow = Framework.Method({ Cooldown = 10 }),
				},
			})
			function Api.Client:Echo(player, a, b)
				return a, b, player.Name
			end
			function Api.Client:Fail(_player)
				error("secret detail")
			end
			function Api.Client:Slow(_player)
				return "ok"
			end
			return Api
		]]
		)
		serverMain(sim)
		clientMain(
			sim,
			[[
			local Api = Framework.GetService("Api")
			shared.echo = table.pack(Api:Echo(1, { x = 2 }))
			shared.fail = err(Api.Fail, Api)
			shared.slow1 = Api:Slow()
			shared.slow2 = err(Api.Slow, Api)
			shared.dot = err(Api.Echo, nil)
			shared.functionArg = Api:Echo(function() end)
		]]
		)
		sim:addPlayer("Player1")
		sim:wait(0.3)
		local r = sim.shared
		expect.equal(r.echo[1], 1)
		expect.equal(r.echo[2].x, 2)
		expect.equal(r.echo[3], "Player1")
		expect.equal(r.fail, "[Framework] Request failed.", "client sees only a generic error")
		expect.equal(count(sim, "server", "warn", "secret detail"), 1, "server logs the detail")
		expect.equal(r.slow1, "ok")
		expect.equal(r.slow2, "[Framework] Request rejected.")
		contains(expect, r.dot, "with a colon")
		expect.equal(r.functionArg, nil, "functions do not cross the network")
	end),

	["Property replicates values, overrides, and table changes"] = scenario(function(expect, sim)
		sim.shared.initial = {}
		sim.shared.observed = {}
		sim.shared.rate = {}
		service(
			sim,
			"Bank",
			[[
			local Bank = Framework.CreateService({
				Name = "Bank",
				Client = {
					Coins = Framework.Property(10),
					Config = Framework.Property({ Rate = 1 }),
				},
			})
			function Bank:Init()
				self.Client.Coins:Set(20) -- before networking exists
			end
			function Bank:PlayerAdded(player)
				if player.Name == "Player2" then
					self.Client.Coins:SetFor(player, 99)
				end
			end
			function Bank:Start()
				task.wait(0.3)
				self.Client.Coins:Set(30)
				local config = self.Client.Config:Get()
				config.Rate = 2
				self.Client.Config:Set(config)
				task.wait(0.2)
				for _, player in game:GetService("Players"):GetPlayers() do
					self.Client.Coins:ClearFor(player)
				end
				shared.serverValue = self.Client.Coins:Get()
			end
			return Bank
		]]
		)
		controller(
			sim,
			"Wallet",
			[[
			local C = Framework.CreateController({ Name = "Wallet" })
			function C:Init()
				local Bank = Framework.GetService("Bank")
				local name = game:GetService("Players").LocalPlayer.Name
				shared.initial[name] = Bank.Coins:Get()
				shared.observed[name] = {}
				Bank.Coins:Observe(function(coins)
					table.insert(shared.observed[name], coins)
				end)
				Bank.Config.Changed:Connect(function(config)
					shared.rate[name] = config.Rate
				end)
			end
			return C
		]]
		)
		serverMain(sim)
		clientMain(sim)
		sim:addPlayer("Player1")
		sim:addPlayer("Player2")
		sim:wait(0.8)
		local r = sim.shared
		expect.equal(r.initial.Player1, 20, "Player1 initial")
		expect.equal(r.initial.Player2, 99, "Player2 initial (override)")
		expect.equal(table.concat(r.observed.Player1, ","), "20,30", "Player1 observed")
		expect.equal(table.concat(r.observed.Player2, ","), "99,30", "Player2 observed")
		expect.equal(r.rate.Player1, 2, "Player1 table update")
		expect.equal(r.rate.Player2, 2, "Player2 table update")
		expect.equal(r.serverValue, 30)
		expect.equal(count(sim, nil, "error"), 0, "errors")
	end),

	["Unreliable signals work in both directions"] = scenario(function(expect, sim)
		service(
			sim,
			"Fx",
			[[
			local Fx = Framework.CreateService({
				Name = "Fx",
				Client = {
					Ping = Framework.Signal({ Unreliable = true }),
					Aim = Framework.ClientSignal({ Unreliable = true }),
				},
			})
			function Fx.Client:Aim(player, value)
				shared.aim = value
				self.Ping:Fire(player, value * 2)
			end
			return Fx
		]]
		)
		serverMain(sim)
		clientMain(
			sim,
			[[
			local Fx = Framework.GetService("Fx")
			Fx.Ping:Connect(function(value)
				shared.ping = value
			end)
			Fx.Aim:Fire(21)
		]]
		)
		local player = sim:addPlayer("Player1")
		sim:wait(0.3)
		expect.equal(sim.shared.aim, 21)
		expect.equal(sim.shared.ping, 42)
		local network = sim.server.game.ReplicatedStorage.__FrameworkNetwork.Fx
		expect.equal(network.Signals.Ping.ClassName, "UnreliableRemoteEvent")
		expect.equal(network.ClientSignals.Aim.ClassName, "UnreliableRemoteEvent")
		expect.equal(sim:twin(network.ClientSignals.Aim, player).ClassName, "UnreliableRemoteEvent")
	end),

	["client proxies expose only declared endpoints and reach the server via self.Server"] = scenario(
		function(expect, sim)
			service(
				sim,
				"Vault",
				[[
			local Vault = Framework.CreateService({
				Name = "Vault",
				Client = { Open = Framework.Method() },
			})
			function Vault:Secret()
				return "server only"
			end
			function Vault.Client:Open(_player)
				return self.Server:Secret()
			end
			return Vault
		]]
			)
			serverMain(sim)
			clientMain(
				sim,
				[[
			local Vault = Framework.GetService("Vault")
			shared.hidden = Vault.Secret == nil and Vault.Server == nil
			shared.frozen = not pcall(function()
				(Vault :: any).Injected = true
			end)
			shared.open = Vault:Open()
			shared.cached = Framework.GetService("Vault") == Vault
		]]
			)
			sim:addPlayer("Player1")
			sim:wait(0.3)
			expect.equal(sim.shared.hidden, true, "server-only members are absent")
			expect.equal(sim.shared.frozen, true, "proxy is frozen")
			expect.equal(sim.shared.open, "server only", "self.Server reaches the service")
			expect.equal(sim.shared.cached, true, "proxy is cached")
		end
	),

	["Start rejects unimplemented client endpoints"] = scenario(function(expect, sim)
		service(
			sim,
			"A",
			[[
			return Framework.CreateService({ Name = "A", Client = { Submit = Framework.ClientSignal() } })
		]]
		)
		serverMain(sim, "Framework.AddServices(script.Parent.Services)\nshared.result = err(Framework.Start)\n")
		sim:wait(0.1)
		contains(expect, sim.shared.result, "A.Client:Submit(Player, ...) must be implemented before Start()")
	end),

	["Start rejects a replaced Property"] = scenario(function(expect, sim)
		service(
			sim,
			"A",
			[[
			local S = Framework.CreateService({ Name = "A", Client = { Coins = Framework.Property(0) } })
			function S.Client:Coins() end
			return S
		]]
		)
		serverMain(sim, "Framework.AddServices(script.Parent.Services)\nshared.result = err(Framework.Start)\n")
		sim:wait(0.1)
		contains(expect, sim.shared.result, "A.Client.Coins is a Property and must not be replaced")
	end),

	["Wally layout resolves GoodSignal from Packages"] = scenario(function(expect, sim)
		local packages = sim.server.game.ReplicatedStorage.Packages
		-- The Wally package has no Vendor folder; GoodSignal is a sibling package.
		packages.Framework.Vendor.Parent = nil
		sim:mount(packages, "src/Vendor/GoodSignal.lua", "GoodSignal")
		service(
			sim,
			"A",
			[[
			local S = Framework.CreateService({ Name = "A", Client = { Value = Framework.Property(7) } })
			function S:Start()
				shared.fromPackages = Framework.LocalSignal == require(game:GetService("ReplicatedStorage").Packages.GoodSignal)
				local signal = Framework.LocalSignal.new()
				signal:Connect(function(value)
					shared.localSignal = value
				end)
				signal:Fire(5)
			end
			return S
		]]
		)
		serverMain(sim)
		clientMain(
			sim,
			[[
			shared.clientValue = Framework.GetService("A").Value:Get()
		]]
		)
		sim:addPlayer("Player1")
		sim:wait(0.3)
		expect.equal(sim.shared.fromPackages, true, "LocalSignal comes from Packages.GoodSignal")
		expect.equal(sim.shared.localSignal, 5)
		expect.equal(sim.shared.clientValue, 7)
		expect.equal(count(sim, nil, "error"), 0, "errors")
	end),
}
