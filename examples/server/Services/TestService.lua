--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Packages.Framework)

local TestService = Framework.CreateService({
	Name = "TestService",
	Client = {
		Updated = Framework.Signal(),
		Submit = Framework.ClientSignal({
			RateLimit = 5,
			Window = 1,
			Validate = function(_player: Player, value: any)
				return type(value) == "string" and #value <= 100, "expected a short string"
			end,
		}),
		GetData = Framework.Method({ Cooldown = 0.1 }),
	},
})

function TestService:Init()
	self.SecondaryService = Framework.GetService("SecondaryService")
end

function TestService:Start()
	print("TestService started after every service finished Init")
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
	TestService.Client.Updated:Fire(player, value)
end

return TestService
