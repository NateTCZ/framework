--!strict
-- Limits warnings to one per (sender, topic) per interval so a client spamming
-- rejected requests cannot flood server output. Suppressed warnings are counted
-- and reported with the next one that is let through.

export type Warn = (sender: any, topic: string, message: string) -> ()

local WarnThrottle = {}

function WarnThrottle.new(interval: number, emit: (string) -> (), clock: (() -> number)?): Warn
	local now = clock or os.clock
	local states = setmetatable({}, { __mode = "k" }) :: any

	return function(sender: any, topic: string, message: string)
		local time = now()
		local topics = states[sender]
		if not topics then
			topics = {}
			states[sender] = topics
		end

		local state = topics[topic]
		if state and time - state.last < interval then
			state.suppressed += 1
			return
		end

		local suppressed = if state then state.suppressed else 0
		topics[topic] = { last = time, suppressed = 0 }
		if suppressed > 0 then
			message ..= string.format(" (%d similar suppressed)", suppressed)
		end
		emit(message)
	end
end

return WarnThrottle
