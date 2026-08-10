#!/usr/bin/env bash
# Gate: terminal — a REAL interactive SSH terminal in the dashboard.
# The bar here is "it actually connects", not "a terminal-shaped div exists".
set -uo pipefail
cd "$(dirname "$0")/.." || exit 90
FAIL=0
bad(){ printf 'FAIL   %s\n' "$1"; FAIL=1; }
ok(){  printf 'ok     %s\n' "$1"; }

mix compile --warnings-as-errors >/tmp/t_c.log 2>&1 && ok "compile" || { bad "compile/warnings"; tail -20 /tmp/t_c.log; }
mix test >/tmp/t_t.log 2>&1 && ok "mix test" || { bad "tests"; tail -25 /tmp/t_t.log; }
mix format --check-formatted >/dev/null 2>&1 && ok "formatted" || bad "unformatted"

# --- 1. The :ssh OTP app must be declared, or this cannot work in a release ---
if grep -qE 'extra_applications:.*:ssh' mix.exs; then ok "mix.exs declares :ssh"
else bad "mix.exs does not list :ssh in extra_applications - will fail in the release"; fi

# --- 2. A real SSH PTY session module -----------------------------------------
SESS=lib/tunneld/machines/ssh/session.ex
if [ -f "$SESS" ]; then ok "ssh session module exists"
else bad "missing $SESS"; fi
if [ -f "$SESS" ]; then
  grep -q 'ptty_alloc'            "$SESS" && ok "allocates a PTY"        || bad "no ptty_alloc - not an interactive shell"
  grep -qE 'shell\('              "$SESS" && ok "starts a shell channel" || bad "no ssh_connection shell channel"
  grep -qE 'send\(|:ssh_connection.send' "$SESS" && ok "can write to the channel" || bad "no way to send keystrokes"
  grep -qE 'window_change|pty_ch'  "$SESS" && ok "handles terminal resize" || bad "no window_change - resizing will corrupt the display"
fi

# --- 3. Transport: a channel wired into the socket ----------------------------
CH=lib/tunneld_web/channels/exec_channel.ex
[ -f "$CH" ] && ok "exec channel exists" || bad "missing $CH"
if grep -qE 'channel "' lib/tunneld_web/channels/user_socket.ex; then
  ok "user_socket declares a channel route"
else bad "user_socket.ex still declares NO channel - the old dead-code problem"; fi
# the socket must actually be mounted on the endpoint
if grep -qE 'socket "/socket"|socket "/live"' lib/tunneld_web/endpoint.ex; then
  ok "socket mounted on endpoint"
else bad "user socket not mounted in endpoint.ex"; fi

# --- 4. Authorisation: a terminal is remote code execution -------------------
if [ -f "$CH" ]; then
  if grep -qE 'Session.valid\?|client_id|authorized|connect_info' "$CH" lib/tunneld_web/channels/user_socket.ex; then
    ok "channel/socket performs an auth check"
  else bad "SECURITY: exec channel has no auth check - anyone on the LAN gets a root shell"; fi
  grep -qE 'Tunneld.Audit|audit' "$CH" && ok "terminal sessions are audited" \
    || bad "terminal sessions are not written to the audit log"
fi

# --- 5. Frontend: a real emulator, vendored (no CDN at runtime) ---------------
if ls assets/vendor/xterm* >/dev/null 2>&1; then ok "xterm vendored locally"
else bad "no vendored xterm in assets/vendor - terminal cannot render properly"; fi
if grep -rqE 'https?://[^"]*xterm' lib/ assets/js 2>/dev/null; then
  bad "loads xterm from a CDN at runtime - gateway is LAN-only, this will break offline"
else ok "no runtime CDN dependency for the terminal"; fi
if grep -q 'Hooks.Terminal' assets/js/hooks.js && grep -rq 'phx-hook="Terminal"' lib/; then
  ok "Terminal hook registered AND used in markup"
else bad "Terminal hook is not both registered and used (dead-code regression)"; fi

# --- 6. It must be reachable from the machine sidebar ------------------------
if grep -qE 'open_terminal|terminal_modal' lib/tunneld_web/live/components/sidebar/details.ex lib/tunneld_web/live/dashboard.ex; then
  ok "terminal is reachable from the machine sidebar"
else bad "no way to open the terminal from the machine detail view"; fi

# --- 7. Auto-login: it must use the stored key, not prompt for a password ----
if [ -f "$SESS" ]; then
  if grep -qE 'user_dir|key_cb|identity|private_key_path|silently_accept_hosts' "$SESS"; then
    ok "authenticates with the stored machine key (auto-login)"
  else bad "no key-based auth wired - operator would have to type a password"; fi
fi

# --- 8. Credentials must never reach the browser -----------------------------
if grep -rnE 'private_key|PRIVATE KEY|password' assets/js/*.js >/dev/null 2>&1; then
  bad "SECURITY: key/password material referenced in frontend JS"
else ok "no credential material in frontend JS"; fi

# --- 9. Tests ----------------------------------------------------------------
if ls test/tunneld/machines/ssh/session_test.exs test/tunneld_web/channels/*_test.exs >/dev/null 2>&1; then
  ok "terminal has test coverage"
else bad "no tests for the ssh session or exec channel"; fi

# --- 10. Key auth must use the PROVEN-WORKING mechanism ----------------------
# Verified empirically against the real gateway 2026-08-10: a bespoke key_cb
# module negotiated SSH then FAILED userauth ("Unable to connect using the
# available authentication methods"), while the SAME key authenticated fine via
# the openssh client. Passing `user_dir` (a dir containing id_ed25519) to
# :ssh.connect/4 was confirmed to open a real shell on the same host.
if grep -q 'user_dir' "$SESS" 2>/dev/null; then
  ok "session uses user_dir for key auth (empirically verified to work)"
else
  bad "session does not use user_dir - bespoke key_cb was verified NOT to authenticate"
fi
if [ -f lib/tunneld/machines/ssh/session_key_callback.ex ]; then
  bad "session_key_callback.ex still present - it fails userauth against a real host"
else ok "no bespoke key callback"; fi

# --- 11. Mock mode must not attempt a real SSH connection --------------------
# TODO principle 6: "Mock mode must keep working. Every new module needs a mock path."
if grep -qE '@mock|mock_data' "$SESS" 2>/dev/null; then
  ok "session has a mock path"
else bad "session has NO mock path - MOCK_DATA=true will attempt a real SSH dial"; fi

echo "-----------------------------------------------"
[ "$FAIL" -eq 0 ] && echo "TERMINAL GATE: PASS" || echo "TERMINAL GATE: FAIL"
exit $FAIL
