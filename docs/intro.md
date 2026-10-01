---
sidebar_position: 1
---

# Getting Started

## Install

With Wally:

```toml
[dependencies]
Framework = "natetcz/framework@0.2.1"
```

Or import `Framework.rbxm` from the GitHub repository into
`ReplicatedStorage.Packages` in Studio. The model is self-contained.

## Recommended structure

```text
ReplicatedStorage/Packages/Framework
ServerScriptService/App/Services/*.lua
ServerScriptService/App/init.server.lua
StarterPlayerScripts/App/Controllers/*.lua
StarterPlayerScripts/App/init.client.lua
```

## Bootstrap

Server:

```lua
local Framework = require(game.ReplicatedStorage.Packages.Framework)

Framework.AddServices(script.Services)
Framework.Start()
```

Client:

```lua
local Framework = require(game.ReplicatedStorage.Packages.Framework)

Framework.AddControllers(script.Controllers)
Framework.Start()
```

Other scripts can wait for startup with `Framework.OnStart()`.

## Lifecycle

Services and controllers can define any of these methods:

| Method | When it runs |
| --- | --- |
| `Init()` | Once, in registration order. Each `Init` finishes before the next one begins. |
| `Start()` | After every `Init` (and, on the server, after networking is published). Each runs on its own thread, so a loop in one `Start` does not block the others. |
| `PlayerAdded(player)` | For every player already in the game when `Start` happens, then for each player who joins. |
| `PlayerRemoving(player)` | When a player leaves. |

Use `Init` to look up other services and controllers, and `Start` to begin work.
An error in `Init` stops `Framework.Start()`. An error in `Start` or a player
hook is shown as a warning and does not affect the others.

```lua
local Framework = require(game.ReplicatedStorage.Packages.Framework)

local DataService = Framework.CreateService({ Name = "DataService" })

function DataService:Init()
	self.ShopService = Framework.GetService("ShopService")
end

function DataService:PlayerAdded(player)
	-- Load data
end

function DataService:PlayerRemoving(player)
	-- Save data
end

return DataService
```

## Coming from Knit

| Knit | Framework |
| --- | --- |
| `Knit.CreateService()` | `Framework.CreateService()` |
| `Knit.CreateController()` | `Framework.CreateController()` |
| `Knit.GetService()` | `Framework.GetService()` |
| `Knit.GetController()` | `Framework.GetController()` |
| `Knit.AddServices()` | `Framework.AddServices()` |
| `Knit.AddControllers()` | `Framework.AddControllers()` |
| `:KnitInit()` | `:Init()` |
| `:KnitStart()` | `:Start()` |
| `Knit.Start()` | `Framework.Start()` (returns nothing, not a Promise) |
| `Knit.OnStart()` | `Framework.OnStart()` (yields, not a Promise) |
| `Knit.CreateSignal()` | `Framework.Signal()` |
| `Knit.CreateProperty()` | `Framework.Property()` |
| `self.Server` in `Client` handlers | `self.Server` (same) |

Differences to know about:

- Client-callable functions must be declared with `Framework.Method()` or
  `Framework.ClientSignal()`. Plain functions in `Client` are not exposed.
- Client methods return values directly instead of Promises.
- There is no middleware. Use the `Validate`, `RateLimit`, and `Cooldown`
  options instead.
