--!strict
-- Per-sender abuse gate for client-to-server endpoints: cooldown, token-bucket
-- rate limit, then validation. Has no Roblox dependencies and takes an
-- injectable clock so it can be unit tested outside Roblox.

export type Options = {
	RateLimit: number?,
	Window: number?,
	Cooldown: number?,
	Validate: ((any, ...any) -> (boolean, string?))?,
}
export type Check = (sender: any, ...any) -> (boolean, string?)

local Gate = {}

function Gate.new(options: Options, clock: (() -> number)?): Check?
	if options.RateLimit == nil and options.Cooldown == nil and options.Validate == nil then
		return nil
	end

	local now = clock or os.clock
	local cooldown = options.Cooldown
	local validate = options.Validate
	-- A token bucket refills continuously, so a client cannot fire a full
	-- window's budget at the end of one window and again at the start of the next.
	-- Capacity is at least one so fractional limits (e.g. 0.5 per second) work.
	local capacity = if options.RateLimit then math.max(options.RateLimit, 1) else nil
	local refillRate = if options.RateLimit then options.RateLimit / (options.Window :: number) else 0
	local states = setmetatable({}, { __mode = "k" }) :: any

	return function(sender: any, ...: any): (boolean, string?)
		local time = now()
		local state = states[sender]
		if not state then
			state = { tokens = capacity or 0, updated = time, last = -math.huge }
			states[sender] = state
		end

		if cooldown and time - state.last < cooldown then
			return false, "cooldown"
		end
		if capacity then
			state.tokens = math.min(capacity, state.tokens + (time - state.updated) * refillRate)
			state.updated = time
			if state.tokens < 1 then
				return false, "rate limit"
			end
			state.tokens -= 1
		end
		-- Budget is consumed before validation so malformed traffic cannot run
		-- validators without being throttled.
		state.last = time

		if validate then
			local ok, accepted, reason = pcall(validate, sender, ...)
			if not ok then
				return false, "validator errored: " .. tostring(accepted)
			end
			if accepted ~= true then
				return false, if type(reason) == "string" then reason else "validation failed"
			end
		end

		return true
	end
end

return Gate
