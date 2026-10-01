-- Runs Framework's unit tests with Lune: `lune run tests/run`
-- These cover the modules with no Roblox dependencies. Networking and the
-- lifecycle are covered by the example place (see tests/README.md).

local process = require("@lune/process")

type Expect = {
	equal: (actual: any, expected: any, label: string?) -> (),
	truthy: (value: any, label: string?) -> (),
	errors: (fn: () -> (), pattern: string?) -> (),
}

local SUITES = {
	"Gate",
	"WarnThrottle",
	"Endpoint",
	"Integration",
}

local expect: Expect = {
	equal = function(actual, expected, label)
		if actual ~= expected then
			error(
				string.format(
					"%sexpected %s, got %s",
					if label then label .. ": " else "",
					tostring(expected),
					tostring(actual)
				),
				2
			)
		end
	end,
	truthy = function(value, label)
		if not value then
			error((label or "expected a truthy value") .. ", got " .. tostring(value), 2)
		end
	end,
	errors = function(fn, pattern)
		local ok, message = pcall(fn)
		if ok then
			error("expected an error", 2)
		end
		if pattern and not string.find(tostring(message), pattern, 1, true) then
			error(string.format('expected error containing "%s", got "%s"', pattern, tostring(message)), 2)
		end
	end,
}

local passed, failed = 0, 0
for _, suiteName in SUITES do
	local cases = (require :: any)("./" .. suiteName .. ".spec")
	for caseName, case in cases do
		local ok, message = pcall(case, expect)
		if ok then
			passed += 1
		else
			failed += 1
			print(string.format("FAIL  %s > %s\n      %s", suiteName, caseName, tostring(message)))
		end
	end
end

print(string.format("%d passed, %d failed", passed, failed))
process.exit(if failed == 0 then 0 else 1)
