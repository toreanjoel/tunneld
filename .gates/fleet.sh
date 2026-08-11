#!/usr/bin/env bash
# Gate: fleet — visible terminal errors, deps-on-enroll, resilient removal.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 90
FAIL=0
bad(){ printf 'FAIL   %s\n' "$1"; FAIL=1; }
ok(){  printf 'ok     %s\n' "$1"; }
HOOK=assets/js/terminal_hook.js
W=lib/tunneld_web/live/components/enrollment_wizard.ex

mix compile --warnings-as-errors >/tmp/f_c.log 2>&1 && ok "compile" || { bad "compile"; tail -15 /tmp/f_c.log; }
mix test >/tmp/f_t.log 2>&1 && ok "mix test" || { bad "tests"; tail -20 /tmp/f_t.log; }
mix format --check-formatted >/dev/null 2>&1 && ok "formatted" || bad "unformatted"
mix assets.build >/tmp/f_a.log 2>&1 && ok "assets build" || { bad "assets build"; tail -10 /tmp/f_a.log; }

# --- 1. Terminal errors must be VISIBLE --------------------------------------
# Root cause: setStatus did this.el.querySelector('.terminal-status*'), but the
# status element lives in the modal HEADER, a SIBLING of the hook element. All
# three lookups returned null, so every status/error update was silently
# dropped. A real SSH failure ("Host unreachable") rendered as a blank terminal
# stuck on "Initializing...".
if grep -qE "this\.el\.querySelector\('\.terminal-status" "$HOOK"; then
  bad "setStatus still scopes .terminal-status to this.el - it is NOT inside the hook"
else ok "status lookup is not wrongly scoped to this.el"; fi
if grep -qE 'ssh_error|terminal_error|onError|"error"' "$HOOK"; then
  ok "hook handles error events"
else bad "hook has no error handling path"; fi
# the failure must reach the user's eyes, not just the console
if grep -qE 'term\.write.*(rror|ailed)|writeln' "$HOOK"; then
  ok "errors are written into the terminal surface itself"
else bad "errors never appear in the terminal - user sees an empty box"; fi

# --- 2. Enrolling a machine installs its dependencies -------------------------
# Owner: "adding a machine on connect should just be a install the deps" and
# there should be no separate exit-node step, since the overlay is implied.
# NB: an earlier version of this check just grepped for the symbol anywhere in
# the file. That passed while the ONLY caller was the manual "Install WireGuard"
# button's handler - so deleting the button would have left NOTHING installing
# the overlay, which is strictly worse than before. Require that the manual
# handler is gone AND ensure_peer is still invoked from the automatic path.
if grep -qE 'handle_event\("wizard_install_wg"' "$W"; then
  bad "dead handler wizard_install_wg still present (its button was removed)"
else ok "manual wireguard handler removed"; fi
if grep -qE 'handle_event\("wizard_make_exit"' "$W"; then
  bad "dead handler wizard_make_exit still present"
else ok "manual exit-node handler removed"; fi
if grep -qE 'ensure_peer' "$W"; then
  ok "wizard still installs the overlay automatically"
else bad "NOTHING installs the overlay during enrollment - remote machines stay unreachable"; fi
if grep -qiE '"Make Exit Node"|Make Exit Node' "$W"; then
  bad "wizard still exposes a separate Make Exit Node step"
else ok "no separate exit-node step in the wizard"; fi
if grep -qiE '"Install WireGuard"' "$W"; then
  bad "wizard still exposes WireGuard as a manual step"
else ok "WireGuard is not a manual wizard step"; fi

# --- 3. Removal must work when the host is already gone ----------------------
# Removal calls Egress.cleanup_machine + Overlay.remove_peer, which SSH to the
# target. Against a dead host those block until the SSH timeout, and since
# Machines is now a plain module the caller (the LiveView) blocks with it.
if grep -qE 'start_async|Task\.(start|async)' lib/tunneld_web/live/dashboard.ex; then
  ok "dashboard has an async path available"
else bad "no async mechanism in dashboard"; fi
if grep -A25 'def remove(id)' lib/tunneld/machines.ex | grep -qE 'timeout|Task\.|async|:timer'; then
  ok "remove bounds the time it spends on remote teardown"
else bad "remove has no timeout around remote teardown - a dead host blocks deletion"; fi
# and it must still delete locally regardless of remote failure
if grep -A25 'def remove(id)' lib/tunneld/machines.ex | grep -q 'Store.delete'; then
  ok "remove always deletes local state"
else bad "remove may skip local deletion"; fi

# --- 4. Regressions from earlier fixes ---------------------------------------
grep -q '_csrf_token' "$HOOK"            && ok "socket still sends _csrf_token"  || bad "REGRESSION: _csrf_token lost"
grep -q 'phx-update="ignore"' lib/tunneld_web/live/dashboard.ex && ok "phx-update=ignore retained" || bad "REGRESSION: phx-update=ignore lost"
grep -q 'user_dir' lib/tunneld/machines/ssh/session.ex && ok "user_dir auth retained" || bad "REGRESSION: user_dir lost"
grep -q 'xterm-viewport' assets/css/app.css && ok "terminal scrollbar theme retained" || bad "REGRESSION: scrollbar theme lost"

echo "-----------------------------------------------"
[ "$FAIL" -eq 0 ] && echo "FLEET GATE: PASS" || echo "FLEET GATE: FAIL"
exit $FAIL
