# Framework

Framework is a small, typed Luau Service/Controller framework for Roblox. It keeps
the development shape that makes Knit pleasant while using an independent,
explicit networking layer, a deterministic two-phase lifecycle, and safe client
proxies.

The server stores ordinary service tables in a direct name lookup. The client
receives a new proxy containing only declared `Client` endpoints; the actual
service table and its private methods never replicate.

## Installation

### Wally

After publishing under your Wally scope, add:

```toml
[dependencies]
Framework = "natetcz/framework@0.1.2"
```

Then run `wally install` and map the generated Packages directory in Rojo. The
package has no transitive Wally dependencies because its one utility dependency
is bundled.

### Rojo

Copy this repository or consume it as a Git submodule, then map `src` to a
ModuleScript named `Framework`:

```json
"ReplicatedStorage": {
  "Packages": {
    "Framework": { "$path": "path/to/Framework/src" }
  }
}
```

`default.project.json` describes the package consumers receive. The complete
example development place is mapped by `dev.project.json`.

### Roblox Studio model

Import `dist/Framework.rbxm`, then place the resulting `Framework` ModuleScript
at `ReplicatedStorage.Packages.Framework`. The model is self-contained: users do
not need Rojo, Wally, or a separate Signal package.

## Recommended structure

```text
ReplicatedStorage/Packages/Framework
ServerScriptService/App/Services/*.lua
ServerScriptService/App/init.server.lua
StarterPlayerScripts/App/Controllers/*.lua
StarterPlayerScripts/App/init.client.lua
```

## Services and lifecycle

```lua
local Framework = require(game.ReplicatedStorage.Packages.Framework)

local ShopService = Framework.CreateService({
    Name = "ShopService",
    Client = {
        PurchaseCompleted = Framework.Signal(),
        PurchaseItem = Framework.ClientSignal(),
        GetShopData = Framework.Method(),
    },
})

function ShopService:Init()
    self.DataService = Framework.GetService("DataService")
end

function ShopService:Start()
end

function ShopService.Client:GetShopData(player)
    return { Coins = 100 }
end

function ShopService.Client:PurchaseItem(player, itemId)
    ShopService:Purchase(player, itemId)
end

function ShopService:Purchase(player, itemId)
    -- Validate ownership and mutate authoritative server state here.
end

return ShopService
```

The descriptor is captured by `CreateService`; defining the endpoint handler
afterward intentionally replaces that entry in the server's `Client` table.

Load and start on the server:

```lua
Framework.AddServices(script.Parent.Services)
Framework.Start()
```

Registration closes as soon as `Start` is called. Services initialize in their
registration order. Every yielding `Init` completes before the next one begins,
and all `Init` calls complete before networking is published or any `Start`
runs. `Start` is single-use. Recursive module loading is sorted by full Instance
name for deterministic registration.

## Controllers

```lua
local Framework = require(game.ReplicatedStorage.Packages.Framework)

local ShopController = Framework.CreateController({ Name = "ShopController" })

function ShopController:Init()
    self.UIController = Framework.GetController("UIController")
    self.ShopService = Framework.GetService("ShopService")
end

function ShopController:Start()
end

return ShopController
```

Client bootstrap:

```lua
Framework.AddControllers(script.Parent.Controllers)
Framework.Start()
```

Services communicate with services and controllers with controllers through
direct table lookups—no dependency injection or networking is involved.

## Networking

### Server to client signal

Declare `Updated = Framework.Signal()`.

```lua
-- Server
self.Client.Updated:Fire(player, data)
self.Client.Updated:FireAll(data)
self.Client.Updated:FireExcept(player, data)
self.Client.Updated:FireFor(players, data)

-- Client
ShopService.Updated:Connect(function(data) end)
```

### Client to server signal

Declare `Submit = Framework.ClientSignal()` and implement
`function Service.Client:Submit(player, ...)`. Fire it with
`Service.Submit:Fire(...)` on the client. Roblox supplies `player`; a client
cannot select or impersonate that argument.

### Client to server method

Declare `GetData = Framework.Method()` and implement
`function Service.Client:GetData(player, ...)`. Call it as
`Service:GetData(...)` on the client. Handler failures are logged with detail on
the server while the client receives only a generic request failure, preventing
server stack-trace disclosure.

Each endpoint maps to exactly one cached `RemoteEvent` or `RemoteFunction`, made
once at startup. Remote type folders are protocol metadata, not a security
mechanism; explicit declarations, server handlers, and validation are the
security boundary.

## Validation, rate limiting, and cooldowns

Security work is opt-in per client-to-server endpoint:

```lua
Submit = Framework.ClientSignal({
    RateLimit = 5,
    Window = 1,
    Cooldown = 0.1,
    Validate = function(player, itemId, quantity)
        return type(itemId) == "string"
            and #itemId <= 50
            and type(quantity) == "number"
            and quantity % 1 == 0
            and quantity >= 1
            and quantity <= 10,
            "invalid purchase"
    end,
})
```

`RateLimit` is the maximum accepted calls per `Window` seconds. `Cooldown` is the
minimum gap between accepted calls. State is held in weak-keyed per-player
tables, so departed players do not require a cleanup loop. Validation runs in a
protected call. Rejected events are warned and dropped; rejected methods return
a generic error.

Validation is a shape/abuse guard, not business authorization. Endpoint code
must still check inventory, permissions, prices, distance, ownership, and other
server-authoritative rules. Never trust values merely because their Luau types
look correct.

## Local signals

The bundled GoodSignal package is available as `Framework.LocalSignal` for
in-process events:

```lua
local changed = Framework.LocalSignal.new()
local connection = changed:Connect(function(value) end)
changed:Fire("value")
connection:Disconnect()
```

GoodSignal is an explicit Wally dependency (`stravant/goodsignal@0.2.1`). The
standalone `.rbxm` distribution bundles the same MIT-licensed implementation so
Studio-only users do not need Wally. Attribution is preserved in
`THIRD_PARTY_LICENSES.md` and the model source. No cleanup or Promise package is
included because neither is needed by the framework runtime.

## Performance

Framework performs no polling, per-frame work, Heartbeat work, or periodic tree
scans. Startup recursively scans only folders explicitly passed to `AddServices`
or `AddControllers`. Server `GetService` and client `GetController` are direct
table lookups. Client service proxies are built once and cached.

Runtime overhead exists only when networking is used: Roblox remote dispatch, a
thin endpoint closure, a protected handler call, and—only when configured—a
per-player gate lookup plus validation. `FireExcept` and `FireFor` iterate their
target player sets when called. Lifecycle execution is sequential by design,
which removes coroutine/Promise allocation and gives simple completion rules.

## Security model

- The client gets a frozen allow-list proxy, never a server service table.
- Only `Signal`, `ClientSignal`, and `Method` declarations create remotes.
- Client-supplied arguments are always placed after Roblox's authentic `Player`.
- Endpoint handlers and validators are protected; Method internals are sanitized.
- Remote names are considered public and provide no security.
- Server code remains responsible for authorization and semantic validation.

Roblox cannot prevent exploiters from discovering or manually firing replicated
remotes. Framework makes those manual calls go through the same rate, validation,
and handler path as normal calls.

## Building and verification

Install the pinned Aftman tools, then run:

```powershell
aftman install
./scripts/build.ps1
./scripts/verify.ps1
rojo serve dev.project.json
```

`build.ps1` invokes Rojo against `model.project.json` and generates both
`dist/Framework.rbxm` and the inspectable `dist/Framework.rbxmx` from the same
`src` source tree. `verify.ps1` runs StyLua and Selene checks, rebuilds both
models, checks the binary is nontrivial, and checks the XML model contains the
server, client, endpoint, and bundled Signal modules.

`build-wally.ps1` creates a clean, flat Wally publication directory at
`build/wally`. It copies the runtime from `src` without duplicating source
maintenance. Publish from that directory with
`wally publish --project-path build/wally`.

The examples directory contains `TestService`, `SecondaryService`,
`TestController`, and `SecondaryController`. It demonstrates both networking
directions, a method, direct service/controller access, lifecycle ordering,
validation, rate limiting, cooldowns, and an absent private client method.

## Migration from Knit

The mapping is intentionally small:

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
| `Knit.Start()` | `Framework.Start()` |
| `Knit.CreateSignal()` | `Framework.Signal()` |

```lua
-- Knit
local TestService = Knit.CreateService({
    Name = "TestService",
    Client = { Updated = Knit.CreateSignal() },
})
function TestService:KnitInit() end
function TestService:KnitStart() end

-- Framework
local TestService = Framework.CreateService({
    Name = "TestService",
    Client = { Updated = Framework.Signal() },
})
function TestService:Init() end
function TestService:Start() end
```

Framework deliberately does not emulate Knit internals, middleware, Promises,
or arbitrary client-callable functions. Client-to-server APIs must be explicitly
typed as `ClientSignal` or `Method`, making exposure visible during review.
