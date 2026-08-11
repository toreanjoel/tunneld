# Contributing to Tunneld

Thanks for your interest in contributing to Tunneld! This guide will help you get set up and understand the project conventions.

## Getting Started

### Prerequisites

- Elixir 1.18+ and Erlang/OTP 26 (`.tool-versions` pins `elixir 1.18.3-otp-26` / `erlang 26.2.5`; CI uses the same pair)
- Node.js (for asset compilation via esbuild/tailwind)

### Setup

```bash
git clone https://github.com/toreanjoel/tunneld.git
cd tunneld
mix deps.get
mix assets.setup
```

### Running Locally

```bash
PORT=4000 MOCK_DATA=true mix phx.server
```

The `MOCK_DATA=true` flag stubs all hardware/OS interactions (systemctl, iptables, dnsmasq, SSH, etc.) with fake data. This lets you develop and test on any machine - no SBC, no root access required.

Visit `http://localhost:4000` to see the dashboard. The default port is 80 (used in production), but that requires root - set `PORT=4000` (or any unprivileged port) for local development.

### Running Tests

```bash
MOCK_DATA=true mix test
```

All tests run against mock data. Before submitting a PR, also verify:

```bash
MOCK_DATA=true mix compile --warnings-as-errors
```

## Project Conventions

### Architecture

Tunneld follows a GenServer-per-concern pattern. Most servers in `lib/tunneld/servers/` manage one domain (devices, services, resources, DNS, etc.) and communicate with the LiveView dashboard through Phoenix PubSub. Not everything in that directory is a process (`expose_allowed.ex`, `device_tags.ex` and `fake_data.ex` are plain modules), and some GenServers live outside it (`Tunneld.AgentTokens`, `Tunneld.Jobs`, `Tunneld.Geolocation`). Machine management is a plain module at `lib/tunneld/machines.ex`, not a server.

Key patterns:
- **PubSub topics** follow `component:<name>` for UI updates and `notifications` for flash messages
- **Periodic polling** uses `:timer.send_after` in `handle_info` callbacks
- **JSON file persistence** - no database; state is stored in JSON files under a configurable root path
- **Mock mode** - modules check `Application.get_env(:tunneld, :mock_data, false)` and delegate to `FakeData` modules when true

### Code Style

- Use `mix format` before committing
- No warnings allowed - the CI runs `mix compile --warnings-as-errors`
- Avoid `String.to_atom/1` with user input - use allowlist lookups instead
- Prefer `File.read/1` and `File.write/2` over `System.cmd("cat", ...)` or `System.cmd("sed", ...)`
- Every public module should have a `@moduledoc`
- Every public function in server modules should have a `@doc`

### Commits

- Use conventional commit prefixes: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `security:`, `chore:`
- Keep commits focused - one concern per commit
- **One line. No body.** A commit message is a single subject line and nothing else
- The _why_ belongs in the code, as a comment next to the thing that needs explaining, where it stays next to the code as it changes. A commit body is read once and then never again
- If a change needs paragraphs to justify, that is usually a sign it should be more than one commit
- `.githooks/commit-msg` enforces this. Enable it once per clone with `git config core.hooksPath .githooks`. Bypass a single commit with `git commit --no-verify` (merges, reverts and cherry-picks are exempt automatically)

### Testing

- Tests live in `test/` mirroring the `lib/` structure
- Tests that interact with GenServers should handle the case where the supervised process is already running (don't stop/restart - use the existing instance or guard with `unless GenServer.whereis(...)`)
- Use `async: false` for tests that modify Application env or shared GenServer state

## What to Work On

Check the GitHub Issues for open items. Good first contributions:
- Adding tests for untested modules
- Improving error messages and user-facing text
- Documentation improvements
- Bug reports with reproduction steps

## Submitting Changes

1. Fork the repo and create a feature branch from `main`
2. Make your changes with tests
3. Ensure `mix test` and `mix compile --warnings-as-errors` pass
4. Open a PR against `main` with a clear description of what and why
