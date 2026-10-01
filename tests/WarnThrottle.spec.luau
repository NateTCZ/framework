local WarnThrottle = require("../src/Shared/WarnThrottle")

local function setup(interval: number)
	local clock = { now = 0 }
	local emitted = {}
	local throttled = WarnThrottle.new(interval, function(message)
		table.insert(emitted, message)
	end, function()
		return clock.now
	end)
	return throttled, emitted, clock
end

return {
	["emits the first warning"] = function(expect)
		local throttled, emitted = setup(5)
		throttled({}, "Shop.Buy", "rejected")
		expect.equal(#emitted, 1)
		expect.equal(emitted[1], "rejected")
	end,

	["suppresses repeats within the interval"] = function(expect)
		local throttled, emitted, clock = setup(5)
		local player = {}
		for i = 1, 100 do
			clock.now = i * 0.01
			throttled(player, "Shop.Buy", "rejected")
		end
		expect.equal(#emitted, 1)
	end,

	["reports the suppressed count with the next warning"] = function(expect)
		local throttled, emitted, clock = setup(5)
		local player = {}
		throttled(player, "Shop.Buy", "rejected")
		throttled(player, "Shop.Buy", "rejected")
		throttled(player, "Shop.Buy", "rejected")
		clock.now = 5
		throttled(player, "Shop.Buy", "rejected")
		expect.equal(#emitted, 2)
		expect.equal(emitted[2], "rejected (2 similar suppressed)")
	end,

	["throttles each player and topic independently"] = function(expect)
		local throttled, emitted = setup(5)
		local a, b = {}, {}
		throttled(a, "Shop.Buy", "1")
		throttled(b, "Shop.Buy", "2")
		throttled(a, "Shop.Sell", "3")
		throttled(a, "Shop.Buy", "4")
		expect.equal(#emitted, 3)
	end,
}
