--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Packages.Framework)

local TestController = Framework.CreateController({
	Name = "TestController",
})

function TestController:Init()
	self.SecondaryController = Framework.GetController("SecondaryController")
	self.TestService = Framework.GetService("TestService")
	self.TestService.Updated:Connect(function(value: string)
		print("Server update:", value)
	end)
end

function TestController:Start()
	local data = self.TestService:GetData()
	print(data.Message)
	self.TestService.Submit:Fire("Hello from the client")
	-- self.TestService:ServerOnlyMethod() -- nil: private methods are absent.
end

return TestController
