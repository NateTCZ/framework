local Gate = require("../src/Shared/Gate")

-- A controllable clock so tests do not depend on real time.
local function fakeClock()
	local clock = { now = 0 }
	function clock.read()
		return clock.now
	end
	return clock
end

return {
	["returns nil when no security options are set"] = function(expect)
		expect.equal(Gate.new({}), nil)
	end,

	["allows up to RateLimit calls, then rejects"] = function(expect)
		local clock = fakeClock()
		local check = Gate.new({ RateLimit = 3, Window = 1 }, clock.read)
		local player = {}
		for i = 1, 3 do
			expect.truthy(check(player), "call " .. i)
		end
		local ok, reason = check(player)
		expect.equal(ok, false)
		expect.equal(reason, "rate limit")
	end,

	["refills continuously instead of resetting per window"] = function(expect)
		local clock = fakeClock()
		local check = Gate.new({ RateLimit = 4, Window = 1 }, clock.read)
		local player = {}
		for _ = 1, 4 do
			check(player)
		end
		-- A quarter window refills exactly one token, not a whole new budget.
		clock.now = 0.25
		expect.truthy(check(player), "one refilled call")
		expect.equal(check(player), false, "second call after quarter window")
	end,

	["cannot burst double the limit across a window boundary"] = function(expect)
		local clock = fakeClock()
		local check = Gate.new({ RateLimit = 10, Window = 1 }, clock.read)
		local player = {}
		local accepted = 0
		clock.now = 0.99
		for _ = 1, 20 do
			if check(player) then
				accepted += 1
			end
		end
		clock.now = 1.01
		for _ = 1, 20 do
			if check(player) then
				accepted += 1
			end
		end
		-- A fixed window would accept 20 here; the bucket refills 0.2 tokens.
		expect.equal(accepted, 10)
	end,

	["fractional RateLimit allows one call per refill"] = function(expect)
		local clock = fakeClock()
		local check = Gate.new({ RateLimit = 0.5, Window = 1 }, clock.read)
		local player = {}
		expect.truthy(check(player), "first call")
		expect.equal(check(player), false, "immediate second call")
		clock.now = 2
		expect.truthy(check(player), "after two seconds")
	end,

	["tracks players separately"] = function(expect)
		local check = Gate.new({ RateLimit = 1, Window = 10 }, fakeClock().read)
		local a, b = {}, {}
		expect.truthy(check(a))
		expect.truthy(check(b))
		expect.equal(check(a), false)
	end,

	["enforces Cooldown"] = function(expect)
		local clock = fakeClock()
		local check = Gate.new({ Cooldown = 0.5 }, clock.read)
		local player = {}
		expect.truthy(check(player))
		clock.now = 0.4
		local ok, reason = check(player)
		expect.equal(ok, false)
		expect.equal(reason, "cooldown")
		clock.now = 0.5
		expect.truthy(check(player))
	end,

	["passes arguments to Validate and reports its reason"] = function(expect)
		local check = Gate.new({
			Validate = function(_player, value)
				return type(value) == "string", "expected a string"
			end,
		}, fakeClock().read)
		local player = {}
		expect.truthy(check(player, "ok"))
		local ok, reason = check(player, 5)
		expect.equal(ok, false)
		expect.equal(reason, "expected a string")
	end,

	["treats a non-true Validate result as rejection"] = function(expect)
		local check = Gate.new({
			Validate = function()
				return 1 :: any
			end,
		}, fakeClock().read)
		local ok, reason = check({})
		expect.equal(ok, false)
		expect.equal(reason, "validation failed")
	end,

	["contains Validate errors"] = function(expect)
		local check = Gate.new({
			Validate = function()
				error("boom")
			end,
		}, fakeClock().read)
		local ok, reason = check({})
		expect.equal(ok, false)
		expect.truthy(string.find(reason :: string, "validator errored", 1, true), "reason mentions validator")
	end,

	["rate limits invalid traffic too"] = function(expect)
		local validated = 0
		local check = Gate.new({
			RateLimit = 2,
			Window = 1,
			Validate = function()
				validated += 1
				return false
			end,
		}, fakeClock().read)
		local player = {}
		for _ = 1, 10 do
			check(player)
		end
		expect.equal(validated, 2)
	end,
}
