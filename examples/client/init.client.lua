--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Packages.Framework)

Framework.AddControllers(script.Controllers)
Framework.Start()
