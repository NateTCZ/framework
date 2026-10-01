--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Packages.Framework)

local TestService = Framework.CreateService({
	Name = "TestService",
	Client = {
		Updated = Framework.Signal(),
		-- High-frequency data that is fine to drop uses an UnreliableRemoteEvent.
		Pulse = Framework.Signal({ Unreliable = true }),
		Submit = Framework.ClientSignal({
			RateLimit = 5,
			Window = 1,
			Validate = function(_player: Player, value: any)
				return type(value) == "string" and #value <= 100, "expected a short string"
			end,
		}),
		GetData = Framework.Method({ Cooldown = 0.1 }),
		Score = Framework.Property(0),
	},
})

function TestService:Init()
	self.SecondaryService = Framework.GetService("SecondaryService")
end

function TestService:Start()
	print("TestService started after every service finished Init")
	-- A yielding loop in Start no longer blocks other services' Start.
	while true do
		self.Client.Pulse:FireAll(os.clock())
		task.wait(0.1)
	end
end

-- Runs for players already in the game when Start happens and for every
-- player who joins afterward.
function TestService:PlayerAdded(player: Player)
	self.Client.Score:SetFor(player, 0)
end

function TestService:PlayerRemoving(player: Player)
	print(player.Name, "left")
end

function TestService:ServerOnlyMethod(): string
	return "This method is never exposed to clients"
end

function TestService.Client:GetData(player: Player)
	return {
		UserId = player.UserId,
		Message = self.Server.SecondaryService:GetMessage(),
	}
end

function TestService.Client:Submit(player: Player, value: string)
	print(player.Name, value)
	self.Updated:Fire(player, value)
	self.Score:SetFor(player, self.Score:GetFor(player) + 1)
end

return TestService
