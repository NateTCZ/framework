--!strict
-- Server half of a replicated property. A property holds one value for every
-- player, plus optional per-player overrides, and pushes changes to clients
-- over a single RemoteEvent once Framework.Start() publishes networking.

local Players = game:GetService("Players")

local Property = {}

local ServerProperty = {}
ServerProperty.__index = ServerProperty

function Property.new(initial: any): any
	return setmetatable({
		_value = initial,
		-- Overrides are boxed so a player can be overridden to nil.
		_overrides = setmetatable({}, { __mode = "k" }),
		_remote = nil,
	}, ServerProperty)
end

function Property.is(value: any): boolean
	return type(value) == "table" and getmetatable(value) == ServerProperty
end

function ServerProperty:Get(): any
	return self._value
end

function ServerProperty:GetFor(player: Player): any
	local box = self._overrides[player]
	if box then
		return box.value
	end
	return self._value
end

-- Sets the value for every player without an override. Setting an identical
-- non-table value does nothing; tables always replicate, so set a table again
-- after mutating it.
function ServerProperty:Set(value: any)
	if value == self._value and type(value) ~= "table" then
		return
	end
	self._value = value
	local remote = self._remote
	if not remote then
		return
	end
	if next(self._overrides) == nil then
		remote:FireAllClients(value)
		return
	end
	for _, player in Players:GetPlayers() do
		if self._overrides[player] == nil then
			remote:FireClient(player, value)
		end
	end
end

function ServerProperty:SetFor(player: Player, value: any)
	self._overrides[player] = { value = value }
	if self._remote then
		self._remote:FireClient(player, value)
	end
end

function ServerProperty:ClearFor(player: Player)
	if self._overrides[player] == nil then
		return
	end
	self._overrides[player] = nil
	if self._remote then
		self._remote:FireClient(player, self._value)
	end
end

function ServerProperty:_bind(remote: RemoteEvent)
	self._remote = remote
end

return Property
