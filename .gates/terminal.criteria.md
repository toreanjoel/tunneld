# Acceptance criteria: terminal

- compile --warnings-as-errors, mix test, mix format pass
- mix.exs declares :ssh in extra_applications so it ships in the release
- A real SSH session module allocates a PTY, starts a shell, sends keystrokes, handles window_change
- An exec channel exists, user_socket declares the channel route, and the socket is mounted
- SECURITY: the channel authenticates the operator; terminal sessions are written to the audit log
- xterm is vendored into assets/vendor - no runtime CDN (the gateway is LAN-only)
- The Terminal hook is both registered and used in markup - no dead scaffolding
- The terminal opens from the machine sidebar
- Auto-login uses the stored per-machine SSH key, not a typed password
- No key or password material is referenced in frontend JS
- The ssh session / exec channel have test coverage
