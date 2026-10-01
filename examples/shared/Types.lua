--!strict
-- Client-side types for services. Framework.GetService returns `any` on the
-- client; casting it to one of these gives autocomplete and type checking.
-- Keep each type in step with the service's Client table.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Packages.Framework)

export type TestService = {
	Updated: Framework.RemoteSignal<string>,
	Pulse: Framework.RemoteSignal<number>,
	Submit: Framework.RemoteClientSignal<string>,
	GetData: (self: TestService) -> { UserId: number, Message: string },
	Score: Framework.RemoteProperty<number>,
}

return {}
