---
sidebar_position: 2
---

# Networking

Services declare everything the client can see in their `Client` table. Only
declared endpoints create remotes, and clients receive a frozen proxy that holds
nothing else, so server-only methods never replicate.

```lua
local ShopService = Framework.CreateService({
	Name = "ShopService",
	Client = {
		PurchaseCompleted = Framework.Signal(),
		PurchaseItem = Framework.ClientSignal(),
		GetShopData = Framework.Method(),
		Coins = Framework.Property(0),
	},
})
```

Inside `Client` handlers, `self` is the `Client` table and `self.Server` is the
service. `Server` is a reserved name.

## Signal (server to client)

```lua
-- Server
self.Client.PurchaseCompleted:Fire(player, itemId)
self.Client.PurchaseCompleted:FireAll(itemId)
self.Client.PurchaseCompleted:FireExcept(player, itemId)
self.Client.PurchaseCompleted:FireFor({ playerA, playerB }, itemId)

-- Client
ShopService.PurchaseCompleted:Connect(function(itemId) end)
```

## ClientSignal (client to server)

```lua
-- Server
function ShopService.Client:PurchaseItem(player, itemId)
	self.Server:Purchase(player, itemId)
end

-- Client
ShopService.PurchaseItem:Fire("sword")
```

Roblox supplies `player`, so a client cannot pretend to be someone else.

## Method (client to server, with a reply)

```lua
-- Server
function ShopService.Client:GetShopData(player)
	return { Coins = 100 }
end

-- Client
local data = ShopService:GetShopData()
```

If the handler errors, the details are logged on the server and the client only
receives a generic "Request failed" error.

## Property (replicated value)

```lua
-- Server (usable from Init onward)
self.Client.Coins:Set(100) -- everyone
self.Client.Coins:SetFor(player, 250) -- one player
self.Client.Coins:ClearFor(player) -- back to the shared value

-- Client
print(ShopService.Coins:Get())
ShopService.Coins:Observe(function(coins)
	-- Runs now, and again on every change
end)
```

Tables always replicate when set, so call `Set` again after changing one.

## Unreliable signals

For frequent data where a missed update doesn't matter, like positions, aim
direction, or effects, add `Unreliable = true` to a `Signal` or `ClientSignal`.
It uses Roblox's `UnreliableRemoteEvent`, which has less overhead but can drop
or reorder events, and each event is limited to about 900 bytes.

```lua
AimDirection = Framework.ClientSignal({ Unreliable = true, RateLimit = 30, Window = 1 }),
```

## Validation, rate limits, and cooldowns

`ClientSignal` and `Method` accept security options:

```lua
PurchaseItem = Framework.ClientSignal({
	RateLimit = 5, -- calls allowed per Window, per player
	Window = 1, -- seconds
	Cooldown = 0.1, -- minimum seconds between calls
	Validate = function(player, itemId)
		return type(itemId) == "string" and #itemId <= 50, "invalid item"
	end,
})
```

- The rate limit refills smoothly over the window, so a client can't send a
  full window's worth at the end of one window and again at the start of the next.
- Limits are checked before `Validate`, so spam can't force validators to run.
- Rejected calls are dropped (signals) or get a generic error (methods). The
  warning is printed at most once every 5 seconds per player and endpoint, so
  spam can't flood your server output.

Validation only checks the shape of the arguments. Handlers must still check
ownership, prices, distance, and other game rules on the server.
