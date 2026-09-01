--!strict

local RunService = game:GetService("RunService")

local Endpoint = require(script.Shared.Endpoint)
local GoodSignal = require(script.Packages.GoodSignal)
local Types = require(script.Shared.Types)
local Runtime = if RunService:IsServer() then require(script.Server) else require(script.Client)

local Framework = {}

export type EndpointOptions = Endpoint.Options
export type EndpointDescriptor = Endpoint.Descriptor
export type Service = Types.Service
export type Controller = Types.Controller

Framework.CreateService = Runtime.CreateService
Framework.CreateController = Runtime.CreateController
Framework.GetService = Runtime.GetService
Framework.GetController = Runtime.GetController
Framework.AddServices = Runtime.AddServices
Framework.AddControllers = Runtime.AddControllers
Framework.Start = Runtime.Start

function Framework.Signal(options: Endpoint.Options?): Endpoint.Descriptor
	return Endpoint.new("Signal", options)
end

function Framework.ClientSignal(options: Endpoint.Options?): Endpoint.Descriptor
	return Endpoint.new("ClientSignal", options)
end

function Framework.Method(options: Endpoint.Options?): Endpoint.Descriptor
	return Endpoint.new("Method", options)
end

Framework.LocalSignal = GoodSignal

return table.freeze(Framework)
