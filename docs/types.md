---
sidebar_position: 3
---

# Typed Services

On the client, `Framework.GetService` returns `any`, because the client can't
see the server's modules. To get autocomplete and type errors, describe each
service's client view in a shared module and cast to it.

```lua
-- ReplicatedStorage/Shared/ServiceTypes.lua
local Framework = require(game.ReplicatedStorage.Packages.Framework)

export type ShopService = {
	PurchaseCompleted: Framework.RemoteSignal<string>,
	PurchaseItem: Framework.RemoteClientSignal<string>,
	GetShopData: (self: ShopService) -> { Coins: number },
	Coins: Framework.RemoteProperty<number>,
}

return {}
```

```lua
-- In a controller
local ServiceTypes = require(game.ReplicatedStorage.Shared.ServiceTypes)

local ShopService = Framework.GetService("ShopService") :: ServiceTypes.ShopService
ShopService.Coins:Observe(function(coins: number) end)
```

| Server declaration | Client type |
| --- | --- |
| `Framework.Signal()` | `Framework.RemoteSignal<T...>` |
| `Framework.ClientSignal()` | `Framework.RemoteClientSignal<T...>` |
| `Framework.Method()` | `(self: YourType, ...) -> ...` |
| `Framework.Property(value)` | `Framework.RemoteProperty<T>` |

On the server, `Framework.ServerSignal<T...>` and `Framework.ServerProperty<T>`
describe the same endpoints.

Keep these types in step with the service's `Client` table. The cast is not
checked at runtime.
