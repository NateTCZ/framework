--!strict

export type EndpointOptions = {
	RateLimit: number?,
	Window: number?,
	Cooldown: number?,
	Validate: ((Player, ...any) -> (boolean, string?))?,
}

export type Service = {
	Name: string,
	Client: { [string]: any }?,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	[string]: any,
}

export type Controller = {
	Name: string,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	[string]: any,
}

return table.freeze({})
