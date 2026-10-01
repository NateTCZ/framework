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
local Signal = require(script.Shared.Signal)
local Types = require(script.Shared.Types)
-- Typed as any: the server and client runtimes differ, and each public member
-- below declares the signature users see instead.
local Runtime: any = if RunService:IsServer() then require(script.Server) else require(script.Client)

--[=[
	@class Framework

	A small, typed Service/Controller framework for Roblox.

	Services run on the server and Controllers run on the client. Each has an
	optional lifecycle: `Init`, then `Start`, then `PlayerAdded` /
	`PlayerRemoving`. Services expose networking by declaring endpoints in their
	`Client` table.
]=]
local Framework = {}

export type EndpointOptions = Endpoint.Options
export type EndpointDescriptor = Endpoint.Descriptor
export type Service = Types.Service
export type Controller = Types.Controller
export type Connection = Types.Connection
export type RemoteSignal<T...> = Types.RemoteSignal<T...>
export type RemoteClientSignal<T...> = Types.RemoteClientSignal<T...>
export type RemoteProperty<T> = Types.RemoteProperty<T>
export type ServerSignal<T...> = Types.ServerSignal<T...>
export type ServerProperty<T> = Types.ServerProperty<T>

--[=[
	@interface EndpointOptions
	@within Framework
	.RateLimit number? -- Maximum accepted calls per `Window` seconds, per player.
	.Window number? -- Length of the rate-limit window in seconds. Required with `RateLimit`.
	.Cooldown number? -- Minimum seconds between accepted calls, per player.
	.Validate ((Player, ...any) -> (boolean, string?))? -- Return `true` to accept the call.
	.Unreliable boolean? -- Use an `UnreliableRemoteEvent`. Signals and ClientSignals only.

	Security options apply to client-to-server endpoints (`ClientSignal` and
	`Method`). Validation is a shape and abuse guard, not authorization: handlers
	must still check ownership, prices, distance, and other game rules.
]=]

--[=[
	@function CreateService
	@within Framework
	@server
	@param definition Service
	@return Service

	Registers a service. Declare client-facing endpoints in `definition.Client`.
	Inside `Client` handlers, `self.Server` refers back to the service.
]=]
Framework.CreateService = Runtime.CreateService :: (definition: Service) -> any

--[=[
	@function CreateController
	@within Framework
	@client
	@param definition Controller
	@return Controller

	Registers a controller.
]=]
Framework.CreateController = Runtime.CreateController :: (definition: Controller) -> any

--[=[
	@function GetService
	@within Framework
	@param name string
	@return any

	On the server, returns the service table. On the client, returns a cached,
	frozen proxy containing only the service's declared endpoints. Cast the
	result to a type built from [RemoteSignal], [RemoteClientSignal], and
	[RemoteProperty] for autocomplete.
]=]
Framework.GetService = Runtime.GetService :: (name: string) -> any

--[=[
	@function GetController
	@within Framework
	@client
	@param name string
	@return Controller
]=]
Framework.GetController = Runtime.GetController :: (name: string) -> any

--[=[
	@function AddServices
	@within Framework
	@server
	@param folder Instance
	@return {any}

	Requires every ModuleScript under `folder`, sorted by full name.
]=]
Framework.AddServices = Runtime.AddServices :: (folder: Instance) -> { any }

--[=[
	@function AddControllers
	@within Framework
	@client
	@param folder Instance
	@return {any}

	Requires every ModuleScript under `folder`, sorted by full name.
]=]
Framework.AddControllers = Runtime.AddControllers :: (folder: Instance) -> { any }

--[=[
	@function Start
	@within Framework

	Runs every `Init` in registration order, publishes networking (server), then
	spawns every `Start` on its own thread and begins `PlayerAdded` and
	`PlayerRemoving` hooks. Can only be called once; registration closes when it is.
]=]
Framework.Start = Runtime.Start :: () -> ()

--[=[
	@function OnStart
	@within Framework
	@yields

	Yields until `Framework.Start()` has finished, or returns immediately if it
	already has. Useful in scripts outside the framework.
]=]
Framework.OnStart = Runtime.OnStart :: () -> ()

--[=[
	@within Framework
	@param options EndpointOptions?
	@return EndpointDescriptor

	Declares a server-to-client event. After `Start`, it becomes a
	[ServerSignal] on the server and a [RemoteSignal] on the client.
]=]
function Framework.Signal(options: Endpoint.Options?): Endpoint.Descriptor
	return Endpoint.new("Signal", options)
end

--[=[
	@within Framework
	@param options EndpointOptions?
	@return EndpointDescriptor

	Declares a client-to-server event. Implement it as
	`function Service.Client:Name(player, ...)`. On the client it is a
	[RemoteClientSignal].
]=]
function Framework.ClientSignal(options: Endpoint.Options?): Endpoint.Descriptor
	return Endpoint.new("ClientSignal", options)
end

--[=[
	@within Framework
	@param options EndpointOptions?
	@return EndpointDescriptor

	Declares a client-to-server request. Implement it as
	`function Service.Client:Name(player, ...)` and call it on the client as
	`Service:Name(...)`. Handler errors are logged on the server; the client only
	receives a generic failure.
]=]
function Framework.Method(options: Endpoint.Options?): Endpoint.Descriptor
	return Endpoint.new("Method", options)
end

--[=[
	@within Framework
	@param initialValue any
	@return EndpointDescriptor

	Declares a replicated value. It becomes a [ServerProperty] on the server
	(usable from `Init` onward) and a [RemoteProperty] on the client.
]=]
function Framework.Property(initialValue: any): Endpoint.Descriptor
	return Endpoint.property(initialValue)
end

--[=[
	@prop LocalSignal GoodSignal
	@within Framework

	The bundled GoodSignal class, for in-process events:
	`Framework.LocalSignal.new()`.
]=]
Framework.LocalSignal = Signal

--[=[
	@interface RemoteSignal
	@within Framework
	.Connect (self, callback: (T...) -> ()) -> Connection
	.Once (self, callback: (T...) -> ()) -> Connection
	.Wait (self) -> T...

	Client view of a [Framework.Signal].
]=]

--[=[
	@interface RemoteClientSignal
	@within Framework
	.Fire (self, T...) -> ()

	Client view of a [Framework.ClientSignal].
]=]

--[=[
	@interface RemoteProperty
	@within Framework
	.Get (self) -> T -- The current value for this player.
	.Observe (self, callback: (T) -> ()) -> Connection -- Calls `callback` now and on every change.
	.Changed RemoteSignal -- Fires with the new value on every change.

	Client view of a [Framework.Property].
]=]

--[=[
	@interface ServerSignal
	@within Framework
	.Fire (self, player: Player, T...) -> ()
	.FireAll (self, T...) -> ()
	.FireExcept (self, player: Player, T...) -> ()
	.FireFor (self, players: {Player}, T...) -> ()

	Server view of a [Framework.Signal], available from `Start` onward.
]=]

--[=[
	@interface ServerProperty
	@within Framework
	.Get (self) -> T
	.Set (self, value: T) -> () -- Sets the value for every player without an override.
	.GetFor (self, player: Player) -> T
	.SetFor (self, player: Player, value: T) -> () -- Overrides the value for one player.
	.ClearFor (self, player: Player) -> () -- Removes a player's override.

	Server view of a [Framework.Property]. Tables always replicate when set, so
	set a table again after mutating it.
]=]

return table.freeze(Framework)
