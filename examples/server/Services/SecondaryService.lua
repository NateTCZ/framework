--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Packages.Framework)

local SecondaryService = Framework.CreateService({
	Name = "SecondaryService",
})

function SecondaryService:GetMessage(): string
	return "Hello from SecondaryService"
end

return SecondaryService
