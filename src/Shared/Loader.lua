--!strict

local Loader = {}

function Loader.requireDescendants(root: Instance): { any }
	assert(typeof(root) == "Instance", "Expected an Instance folder")
	local modules = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			table.insert(modules, descendant)
		end
	end
	table.sort(modules, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)

	local results = {}
	for _, module in modules do
		local ok, result = pcall(require, module)
		if not ok then
			error(string.format('[Framework] Failed to load "%s": %s', module:GetFullName(), tostring(result)), 3)
		end
		table.insert(results, result)
	end
	return results
end

return Loader
