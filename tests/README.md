# Tests

Run every test with [Lune](https://lune-org.github.io/docs) from the repository root:

```powershell
lune run tests/run
```

`scripts/verify.ps1` runs these along with formatting, linting, and the model build.

## Unit tests

`Gate`, `WarnThrottle`, and `Endpoint` have no Roblox dependencies and are tested
directly, with a fake clock for the rate limiter and warning throttle.

## End-to-end tests

`Integration.spec.luau` runs the real `src` code, and the example place, on a
simulated Roblox server with simulated players (`sim/Roblox.luau`). The
simulation gives each peer its own DataModel and module cache, replicates
ReplicatedStorage to clients, delivers remote traffic in order with copied
arguments, queues client events until a listener connects, and makes
`InvokeServer` a real yielding round trip.

Covered:

- The example place with two players: every endpoint type, the property, the
  unreliable signal, and `PlayerRemoving`.
- Registration and misuse errors on both server and client.
- Lifecycle: `Init` ordering with yields, `Start` isolation (loops and errors),
  `Init` failures, rejected non-function hooks, `OnStart`.
- `PlayerAdded` running exactly once for players present before `Start`.
- Rate limits, validation, and throttled warnings on a `ClientSignal`.
- `Method` return values, hidden server errors, cooldown rejection, and the
  colon-call check.
- Properties: snapshot on connect, `Set` before networking, per-player
  overrides, `ClearFor`, and table updates.
- Unreliable endpoints in both directions.
- Client proxies hiding server-only members, being frozen and cached, and
  `self.Server` in handlers.
- `Start` rejecting missing handlers and replaced properties.
- The Wally layout, where GoodSignal is a sibling package.

## Not covered by the simulation

These need real Roblox and are worth a quick check in Studio before a large
release. Sync `dev.project.json` with Rojo and run a two-player local server:

1. Unreliable events really are dropped under load without errors.
2. Payloads over Roblox's size limits (about 900 bytes for unreliable events).
3. Studio's type checker shows autocomplete through the example `Types` cast.
