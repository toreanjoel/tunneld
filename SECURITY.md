# Security

Tunneld is a gateway. It sits between a subnet and the internet, holds SSH keys
for every machine it manages, and can open a root shell on any of them. That
makes it a high-value target by construction, and it means the honest security
posture is not "this is secure" but "here is exactly what it defends, what it
does not, and what you have to do yourself".

This document is the current state, not an aspiration. Where something is a
known gap it is listed as one.

## Reporting

Open an issue for anything non-exploitable. For something exploitable, contact
the maintainer directly rather than filing publicly.

## Threat model

**Tunneld assumes:**

- The operator running the dashboard is trusted and authorised for the whole fleet.
- The LAN behind the gateway is semi-trusted: devices there get DHCP, DNS, and
  internet, and may read a limited inventory API (see below).
- Managed machines are trusted enough to receive a WireGuard peer and to run
  commands the operator issues over SSH.

**Tunneld does not defend against:**

- An attacker who already has the dashboard password.
- An attacker with a shell on the gateway.
- A malicious managed machine. It is a peer on the overlay and the gateway dials
  out to it.

## What is enforced, and where

| Surface | Control |
|---|---|
| Dashboard (`/`, LiveView) | Password (bcrypt) → in-memory session, TTL'd, renewed on interaction |
| Exec terminal (`/ws`) | Same session, re-checked at socket connect; every open/close audited |
| Admin HTTP API (`/api/v1/machines`, ...) | `require_admin` — same session as the dashboard, else 401 |
| Agent API (`/api/v1/agent/*`) | Scoped bearer token, SHA-256 hashed at rest, revocable, audited |
| Device API (`/api/v1/device/*`) | **No credential.** Caller must hold a DHCP lease from this gateway |
| Quick Expose (`/api/v1/expose`) | Caller's MAC must be on the allow-list, set per device by the operator |
| Client LAN access | Per-client, per-host `FORWARD` + `MASQUERADE` rules on the gateway |

Agent tokens cannot be granted certain scopes at all — token issuance, machine
enrollment, iptables rules outside their own resources, DNS provider config, or
WireGuard key material. See `Tunneld.AgentTokens.forbidden_scopes/0`.

## Key material

- **WireGuard private keys** live under `TUNNELD_DATA/wg/`, mode `0600`. They are
  never logged, rendered, or returned by the API.
- **Client private keys are never persisted.** A client config is generated once,
  shown once, and the key is discarded server-side. Losing it means re-issuing.
- **SSH keys** are generated per machine and stored under the data root. The
  public half is installed by the operator, out of band.
- Nothing above is in this repository, and the data directory is gitignored.

## Known gaps

These are real and currently unfixed. They are listed here rather than in an
issue tracker because anyone deploying this should read them before they do.

### 1. A fresh install can end up with a trivial password

Signup checks only that the two password fields match. There is no minimum
length, no strength requirement, and no forced change on first login. An install
left on a default-ish password is one guess away from full compromise.

**If you run this: set a real password.** Nothing else in this list matters as
much.

### 2. Dashboard access is root on every managed machine

There is no privilege separation inside the dashboard. Whoever can log in can
open a terminal on any enrolled machine, change egress, wake devices, and issue
agent tokens. The dashboard password is effectively the fleet's root password.

### 3. Gateway services are reachable from everywhere, including the overlay

`Tunneld.Iptables.reset/0` opens SSH (22), the dashboard (80), and Caddy's
resource port (18000) with no source or interface restriction. Any WireGuard
client — and anything on the LAN — can reach all three.

The consequence is that **per-client LAN grants are not a security boundary.**
They scope direct L3 traffic to named hosts, and that part works, but a client
that can reach the dashboard, SSH, or a resource proxied by Caddy on 18000 has
paths to the LAN that the grant does not cover.

Treat the overlay as trusted, or scope those ports to the downstream interface.

### 4. The device API needs no credentials

`GET /api/v1/device/machines` and its siblings answer any caller that holds a
DHCP lease from this gateway. They disclose the machine inventory: names, public
addresses, OS, kernel, architecture, and detected runtimes. A device that joins
the subnet can enumerate the fleet.

### 5. Disenrollment leaves its footprint on the target

Removing a machine tears down the gateway's half of the overlay and disables the
remote unit, but the target keeps `/etc/wireguard/<iface>.conf` — **including its
private key** — plus the firewall rule opening the overlay port, any MASQUERADE
and FORWARD rules added to make it an exit node, and Tunneld's entry in
`authorized_keys`. Re-enrolling repeatedly accumulates all of it.

### 6. Sessions are in-memory and not bound to an address

The auth session store is a map in the BEAM, keyed by a cookie value, with a
TTL renewed on interaction. Restarting the service logs everyone out. A stolen
session cookie is usable from anywhere until it expires.

### 7. Committed dev and test secrets

`config/dev.exs` and `config/test.exs` contain literal `secret_key_base` values,
as generated Phoenix projects do. They are real signing keys for those
environments. Production reads `SECRET_KEY_BASE` from the environment and
**raises** if it is missing, so it never falls back to a committed value — but do
not reuse the dev or test values anywhere real.

Earlier commits in this repository's history contained a default password and a
bcrypt hash, both since removed from the source. History is public: treat any
password that ever appeared in it as burned.

## Hardening checklist

1. Set a strong dashboard password. Do not leave the one you installed with.
2. Decide whether the overlay is trusted. If it is not, scope ports 22 and 18000
   to the downstream interface.
3. Do not expose the dashboard to the internet. It is designed to be reached on
   the LAN or over WireGuard.
4. Keep `SECRET_KEY_BASE` in the environment, generated per install.
5. Issue agent tokens with the narrowest scopes that work, and revoke them when
   the task is done.
6. After disenrolling a machine, remove `/etc/wireguard/tunneld-*` and the
   `authorized_keys` entry on the target by hand until gap 5 is closed.
