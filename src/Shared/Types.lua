--!strict

export type EndpointOptions = {
	RateLimit: number?,
	Window: number?,
	Cooldown: number?,
	Validate: ((Player, ...any) -> (boolean, string?))?,
	Unreliable: boolean?,
}

export type Service = {
	Name: string,
	-- Client.Server is set by CreateService and refers back to this service.
	Client: { [string]: any }?,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	PlayerAdded: ((self: any, player: Player) -> ())?,
	PlayerRemoving: ((self: any, player: Player) -> ())?,
	[string]: any,
}

export type Controller = {
	Name: string,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	PlayerAdded: ((self: any, player: Player) -> ())?,
	PlayerRemoving: ((self: any, player: Player) -> ())?,
	[string]: any,
}

export type Connection = {
	Disconnect: (self: any) -> (),
}

-- Client-side shapes of a service's endpoints. Framework.GetService returns
-- `any` on the client; cast it to a type built from these for autocomplete.

-- Client view of Framework.Signal(): listen for events from the server.
export type RemoteSignal<T...> = {
	Connect: (self: any, callback: (T...) -> ()) -> Connection,
	Once: (self: any, callback: (T...) -> ()) -> Connection,
	Wait: (self: any) -> T...,
}

-- Client view of Framework.ClientSignal(): send events to the server.
export type RemoteClientSignal<T...> = {
	Fire: (self: any, T...) -> (),
}

-- Client view of Framework.Property(): read and watch a replicated value.
export type RemoteProperty<T> = {
	Get: (self: any) -> T,
	Observe: (self: any, callback: (T) -> ()) -> Connection,
	Changed: RemoteSignal<T>,
}

-- Server view of Framework.Signal() after Framework.Start().
export type ServerSignal<T...> = {
	Fire: (self: any, player: Player, T...) -> (),
	FireAll: (self: any, T...) -> (),
	FireExcept: (self: any, player: Player, T...) -> (),
	FireFor: (self: any, players: { Player }, T...) -> (),
}

-- Server view of Framework.Property().
export type ServerProperty<T> = {
	Get: (self: any) -> T,
	Set: (self: any, value: T) -> (),
	GetFor: (self: any, player: Player) -> T,
	SetFor: (self: any, player: Player, value: T) -> (),
	ClearFor: (self: any, player: Player) -> (),
}

return table.freeze({})
