# Framework

A small, typed Service/Controller framework for Roblox, written in Luau.

## What it does

Framework organizes your game into **Services** (server) and **Controllers**
(client), each with a simple lifecycle: `Init`, `Start`, and `PlayerAdded` /
`PlayerRemoving`. Services can expose signals, methods, and replicated
properties to the client, and Framework creates and wires up the remotes for you.

## Why

If you've used Knit, this will feel familiar, but it's smaller, stricter, and
built for current Roblox:

- **Secure by default.** Clients only see endpoints you explicitly declare.
  Server-only methods never replicate.
- **Built-in abuse protection.** Validation, rate limits, and cooldowns can be
  added to any client-to-server endpoint, and spam can't flood your server output.
- **Unreliable remotes.** Mark a signal `Unreliable` for frequent data like
  positions or effects.
- **Typed client access.** Cast services to built-in types for autocomplete.
- **No Promises, no polling.** Lifecycle order is predictable, and there's no
  per-frame overhead.
- **Easy to migrate.** It uses the same shape as Knit: `CreateService`,
  `GetService`, `self.Server`, `Property`, `OnStart`, and so on.

**Full documentation:** https://natetcz.github.io/framework/

## Installation

**Wally**

```toml
[dependencies]
Framework = "natetcz/framework@0.2.1"
```

**Roblox Studio:** import `dist/Framework.rbxm` into
`ReplicatedStorage.Packages`.

## Quick example

```lua
-- Server: ServerScriptService/App/Services/ShopService.lua
local Framework = require(game.ReplicatedStorage.Packages.Framework)

local ShopService = Framework.CreateService({
    Name = "ShopService",
    Client = {
        GetCoins = Framework.Method(),
    },
})

function ShopService.Client:GetCoins(player)
    return 100
end

return ShopService
```

```lua
-- Client: StarterPlayerScripts/App/Controllers/ShopController.lua
local Framework = require(game.ReplicatedStorage.Packages.Framework)

local ShopController = Framework.CreateController({ Name = "ShopController" })

function ShopController:Start()
    local ShopService = Framework.GetService("ShopService")
    print(ShopService:GetCoins())
end

return ShopController
```

```lua
-- Bootstrap (one script on each side)
Framework.AddServices(script.Parent.Services) -- or AddControllers on the client
Framework.Start()
```

More examples are in the [`examples`](examples) folder.

## License

MIT. See [LICENSE](LICENSE).
