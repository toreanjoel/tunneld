# Contributing to Tunneld

Thanks for your interest in contributing to Tunneld! This guide will help you get set up and understand the project conventions.

## Getting Started

### Prerequisites

- Elixir 1.18+ and Erlang/OTP 27+
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
MOCK_DATA=true mix phx.server
```

The `MOCK_DATA=true` flag stubs all hardware/OS interactions (systemctl, wpa_cli, iptables, etc.) with fake data. This lets you develop and test on any machine — no SBC, no root access required.

Visit `http://localhost:4000` to see the dashboard.

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

Tunneld follows a GenServer-per-concern pattern. Each server in `lib/tunneld/servers/` manages one domain (devices, services, resources, Wi-Fi, etc.) and communicates with the LiveView dashboard through Phoenix PubSub.

Key patterns:
- **PubSub topics** follow `component:<name>` for UI updates and `notifications` for flash messages
- **Periodic polling** uses `:timer.send_after` in `handle_info` callbacks
- **JSON file persistence** — no database; state is stored in JSON files under a configurable root path
- **Mock mode** — modules check `Application.get_env(:tunneld, :mock_data, false)` and delegate to `FakeData` modules when true

### Code Style

- Use `mix format` before committing
- No warnings allowed — the CI runs `mix compile --warnings-as-errors`
- Avoid `String.to_atom/1` with user input — use allowlist lookups instead
- Prefer `File.read/1` and `File.write/2` over `System.cmd("cat", ...)` or `System.cmd("sed", ...)`
- Every public module should have a `@moduledoc`
- Every public function in server modules should have a `@doc`

### Commits

- Use conventional commit prefixes: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `security:`, `chore:`
- Keep commits focused — one concern per commit
- Write commit messages that explain _why_, not just _what_

### Testing

- Tests live in `test/` mirroring the `lib/` structure
- Tests that interact with GenServers should handle the case where the supervised process is already running (don't stop/restart — use the existing instance or guard with `unless GenServer.whereis(...)`)
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
