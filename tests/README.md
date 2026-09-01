# Test matrix

The example place is the runtime integration fixture. Sync `dev.project.json`
and run a two-player Studio server to cover networking. Static/model checks run
with `scripts/verify.ps1`.

Manual misuse cases should each be run in a fresh play session because Framework
is intentionally single-start:

1. Register the same service twice: expect the named duplicate-service error.
2. Register the same controller twice: expect the named duplicate-controller error.
3. Get an unknown service/controller: expect the registration hint.
4. Call `Start` twice: expect the single-start error.
5. Register after `Start`: expect the late-registration error.
6. Add yielding markers in both `Init` functions and assert every marker precedes
   every `Start` marker.
7. Run the examples and verify Method, Signal, and ClientSignal traffic.
8. Inspect the client proxy and assert `ServerOnlyMethod == nil`.
9. Spam `Submit` and verify excess calls are rejected by its rate limit.
10. Pass malformed `Submit` values and verify the handler is not reached.

The fixtures also exercise service-to-service and controller-to-controller
lookups in `Init`.
