--!strict
-- Resolves GoodSignal. Wally installs declared dependencies beside this
-- package; standalone model builds use the vendored fallback so
-- Framework.rbxm stays self-contained.

local root = script.Parent.Parent
local vendor = root:FindFirstChild("Vendor")
local module = (root.Parent and root.Parent:FindFirstChild("GoodSignal"))
	or (vendor and vendor:FindFirstChild("GoodSignal"))
assert(module, "[Framework] GoodSignal dependency is missing. Run wally install or use Framework.rbxm.")

return require(module :: ModuleScript) :: any
