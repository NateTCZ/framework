local Endpoint = require("../src/Shared/Endpoint")

return {
	["creates frozen descriptors"] = function(expect)
		local descriptor = Endpoint.new("Method", { Cooldown = 1 })
		expect.equal(descriptor._kind, "Method")
		expect.equal(descriptor._options.Cooldown, 1)
		expect.truthy(table.isfrozen(descriptor), "descriptor is frozen")
	end,

	["copies options so later edits have no effect"] = function(expect)
		local options = { Cooldown = 1 }
		local descriptor = Endpoint.new("ClientSignal", options)
		options.Cooldown = 99
		expect.equal(descriptor._options.Cooldown, 1)
	end,

	["recognizes every kind, including Property"] = function(expect)
		expect.truthy(Endpoint.is(Endpoint.new("Signal")))
		expect.truthy(Endpoint.is(Endpoint.new("ClientSignal")))
		expect.truthy(Endpoint.is(Endpoint.new("Method")))
		expect.truthy(Endpoint.is(Endpoint.property(0)))
		expect.equal(Endpoint.is({ _kind = "Other", _options = {} }), false)
		expect.equal(Endpoint.is(function() end), false)
	end,

	["stores a Property's initial value"] = function(expect)
		expect.equal(Endpoint.property(42)._initial, 42)
	end,

	["requires Window with RateLimit"] = function(expect)
		expect.errors(function()
			Endpoint.new("Method", { RateLimit = 5 })
		end, "Window")
		expect.errors(function()
			Endpoint.new("Method", { Window = 1 })
		end, "Window requires RateLimit")
	end,

	["rejects invalid numbers"] = function(expect)
		expect.errors(function()
			Endpoint.new("Method", { RateLimit = 0, Window = 1 })
		end, "RateLimit")
		expect.errors(function()
			Endpoint.new("Method", { Cooldown = -1 })
		end, "Cooldown")
	end,

	["allows Unreliable on signals only"] = function(expect)
		expect.equal(Endpoint.new("Signal", { Unreliable = true })._options.Unreliable, true)
		expect.equal(Endpoint.new("ClientSignal", { Unreliable = true })._options.Unreliable, true)
		expect.errors(function()
			Endpoint.new("Method", { Unreliable = true })
		end, "Unreliable")
		expect.errors(function()
			Endpoint.new("Signal", { Unreliable = "yes" :: any })
		end, "boolean")
	end,
}
