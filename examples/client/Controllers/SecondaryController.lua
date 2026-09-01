--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Packages.Framework)

return Framework.CreateController({
	Name = "SecondaryController",
})
