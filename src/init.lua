--!strict
-- Framework is licensed under the MIT License.
-- Copyright (c) 2026 NateTCZ
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local RunService = game:GetService("RunService")

local Endpoint = require(script.Shared.Endpoint)
local GoodSignal = require(script.Vendor.GoodSignal)
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
