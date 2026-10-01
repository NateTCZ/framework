--!strict

local Endpoint = {}

export type Kind = "Signal" | "ClientSignal" | "Method" | "Property"
export type Options = {
	RateLimit: number?,
	Window: number?,
	Cooldown: number?,
	Validate: ((Player, ...any) -> (boolean, string?))?,
	Unreliable: boolean?,
}
export type Descriptor = {
	_kind: Kind,
	_options: Options,
	_initial: any,
}

local KINDS = { Signal = true, ClientSignal = true, Method = true, Property = true }

local function validateOptions(kind: Kind, options: Options?)
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
	if options.Unreliable ~= nil then
		assert(type(options.Unreliable) == "boolean", "Unreliable must be a boolean")
		if kind == "Method" then
			error("Unreliable is only supported on Signal and ClientSignal", 3)
		end
	end
end

function Endpoint.new(kind: Kind, options: Options?): Descriptor
	validateOptions(kind, options)
	return table.freeze({
		_kind = kind,
		_options = if options then table.clone(options) else {},
	}) :: any
end

function Endpoint.property(initial: any): Descriptor
	return table.freeze({
		_kind = "Property",
		_options = {},
		_initial = initial,
	}) :: any
end

function Endpoint.is(value: any): boolean
	return type(value) == "table" and KINDS[value._kind] == true and type(value._options) == "table"
end

return Endpoint
