--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Packages.Framework)
local Types = require(ReplicatedStorage.FrameworkExample.Types)

local TestController = Framework.CreateController({
	Name = "TestController",
})

function TestController:Init()
	self.SecondaryController = Framework.GetController("SecondaryController")
	-- The cast gives autocomplete and type checking for the service's endpoints.
	self.TestService = Framework.GetService("TestService") :: Types.TestService
	self.TestService.Updated:Connect(function(value: string)
		print("Server update:", value)
	end)
	self.TestService.Score:Observe(function(score: number)
		print("Score:", score)
	end)
	self.TestService.Pulse:Connect(function(_serverTime: number)
		-- Unreliable: some pulses may be dropped, which is fine for this data.
	end)
end

function TestController:Start()
	local data = self.TestService:GetData()
	print(data.Message)
	self.TestService.Submit:Fire("Hello from the client")
	-- self.TestService:ServerOnlyMethod() -- nil: private methods are absent.
end

return TestController
