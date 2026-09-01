--!strict

local Endpoint = {}

export type Kind = "Signal" | "ClientSignal" | "Method"
export type Options = {
	RateLimit: number?,
	Window: number?,
	Cooldown: number?,
	Validate: ((Player, ...any) -> (boolean, string?))?,
}
export type Descriptor = {
	_kind: Kind,
	_options: Options,
}

local function validateOptions(options: Options?)
	if options == nil then
		return
	end
	if options.RateLimit ~= nil then
		assert(type(options.RateLimit) == "number" and options.RateLimit > 0, "RateLimit must be a positive number")
		assert(
			type(options.Window) == "number" and options.Window > 0,
			"Window must be a positive number when RateLimit is set"
		)
	elseif options.Window ~= nil then
		error("Window requires RateLimit", 3)
	end
	if options.Cooldown ~= nil then
		assert(type(options.Cooldown) == "number" and options.Cooldown >= 0, "Cooldown must be a non-negative number")
	end
	if options.Validate ~= nil then
		assert(type(options.Validate) == "function", "Validate must be a function")
	end
end

function Endpoint.new(kind: Kind, options: Options?): Descriptor
	validateOptions(options)
	return table.freeze({
		_kind = kind,
		_options = if options then table.clone(options) else {},
	}) :: any
end

function Endpoint.is(value: any): boolean
	return type(value) == "table"
		and (value._kind == "Signal" or value._kind == "ClientSignal" or value._kind == "Method")
		and type(value._options) == "table"
end

return Endpoint
