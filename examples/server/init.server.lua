--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Packages.Framework)

Framework.AddServices(script.Services)
Framework.Start()
