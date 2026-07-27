# KNOWN GOOD — tunneld

Behaviors that must keep working after the redesign. A change breaking any entry is a FAILED change.

## Tests
- `bash .ai/run-capture.sh mix test` => exit 0, 12 tests 0 failures
- `bash .ai/run-capture.sh mix test` => no `Mesh` or `Wireguard` GenServer crash logs in output (currently present — target after Phase 0: gone)

## App boots (mock mode)
- `bash .ai/run-capture.sh mix phx.server` (background, then curl localhost) => Phoenix serves the dashboard (HTTP 200)
- `curl /api/health` => `{"status":"ok",...}`
- `curl /api/v1/machines` => `{"machines":[]}` (empty before enrollment)

## Machines (M2)
- `Tunneld.Machines.enroll(%{"name"=>_, "address"=>_})` => `{:ok, %{"id"=>_, "public_key"=>pub, "machine"=>_}}` with `pub` starting `ssh-ed25519 `
- `Tunneld.Machines.probe(id)` in mock => capabilities populated, status "ready"
- `Tunneld.Machines.list_containers(id)` in mock => returns mock-app + mock-vm
- `Tunneld.Machines.remove(id)` => record gone, key deleted
- POST /api/v1/machines without admin session => 401

## Compile
- `bash .ai/run-capture.sh mix compile` => exit 0, no warnings about undefined modules

## Existing features that survive the cull
- `Tunneld.Persistence` atomic JSON writes round-trip (covered by smoke test if absent, add one)
- `Tunneld.NetLink` operstate read returns `:up`/`:down` (covered by net_link_test.exs)
- Resources/nginx config generation produces a valid server block (covered if test exists; if not, add)
- Expose controller pattern: `POST /expose` with allowlist gating (covered if test exists; if not, add)
- Dashboard LiveView renders (covered by feature test if exists; if not, add smoke)