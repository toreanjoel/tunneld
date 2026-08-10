#!/usr/bin/env bash
# Gate: ui — the 12 dashboard UX defects. Structural checks only; taste is reviewed by hand.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 90
FAIL=0
bad(){ printf 'FAIL   %s\n' "$1"; FAIL=1; }
ok(){  printf 'ok     %s\n' "$1"; }
D=lib/tunneld_web/live/components
DASH=lib/tunneld_web/live/dashboard.ex

# --- 0. Build stays green -----------------------------------------------------
mix compile --warnings-as-errors >/tmp/u_c.log 2>&1 && ok "compile" || { bad "compile/warnings"; tail -25 /tmp/u_c.log; }
mix test >/tmp/u_t.log 2>&1 && ok "mix test" || { bad "tests"; tail -25 /tmp/u_t.log; }
mix format --check-formatted >/dev/null 2>&1 && ok "formatted" || bad "unformatted files"

# --- 1. LOADERS: sidebar must not block on a 30s SSH call ---------------------
if grep -qE 'start_async|assign_async' "$DASH" $D/sidebar/details.ex; then
  ok "sidebar loads listeners asynchronously"
else
  bad "no start_async/assign_async - sidebar still blocks on Machines.listeners/1"
fi
# NB: phx-click-loading is per-click opacity feedback, NOT a data-loading state.
if grep -E 'animate-spin|role="status"|listeners_loading|:loading' $D/sidebar/details.ex \
     | grep -qv 'phx-click-loading'; then
  ok "sidebar has a real loading/spinner state"
else bad "sidebar has no real loading state (phx-click-loading does not count)"; fi

# --- 2. LISTENERS: infrastructure ports filtered out --------------------------
if grep -qE 'sshd|caddy|systemd-resolve|dnsmasq' lib/tunneld/machines/runtime.ex; then
  ok "runtime.ex filters/classifies infrastructure listeners"
else bad "runtime.ex still passes raw ss -tlnp through with no infra filtering"; fi

# --- 3. EXIT wording: redundant description removed ---------------------------
if grep -q 'Route specific devices through this exit from the' $D/sidebar/details.ex; then
  bad "redundant Exit description still present in details.ex"
else ok "redundant Exit description removed"; fi

# --- 4. MACHINES: one status indicator, not two competing green dots ----------
if grep -q 'defp wg_dot' $D/machines.ex; then
  bad "machines.ex still renders a second independent WG dot (wg_dot/1)"
else ok "duplicate WG dot removed / merged into one status"; fi

# --- 5. SSH access affordance -------------------------------------------------
if grep -qE 'ssh_connect|open_terminal|phx-hook="Terminal"' $D/sidebar/details.ex $DASH; then
  ok "an SSH/terminal affordance exists in the machine sidebar"
else bad "no SSH/terminal action wired in the machine sidebar"; fi

# --- 6. OVERFLOW: modals use the themed scrollbar, not the OS default ---------
for f in $D/modal.ex $D/enrollment_wizard.ex; do
  if grep -q 'overflow-y-auto' "$f" && ! grep -q 'system-scroll' "$f"; then
    bad "$(basename $f) scrolls with an unthemed default scrollbar"
  else ok "$(basename $f) uses themed scroll"; fi
done
# invalid CSS from the audit: scrollbar-width must be auto|thin|none, not 8px
if grep -qE 'scrollbar-width:\s*8px' assets/css/app.css; then
  bad "assets/css/app.css has invalid 'scrollbar-width: 8px'"
else ok "scrollbar-width is valid"; fi

# --- 7. EGRESS help icon: one per section, not one per device card ------------
if awk '/for device/,/^  end/' $D/devices.ex | grep -q 'help_icon'; then
  bad "help_icon still rendered inside the per-device loop (N devices = N '?' icons)"
else ok "egress help icon no longer repeats per device card"; fi

# --- 8. Devices header divider removed ---------------------------------------
# \b prevents matching the substring inside "border-border".
if grep -qE '\bborder-b\b|\bborder-b-[0-9]' $D/devices.ex $D/section_header.ex; then
  bad "a bottom border/underline remains under the devices list header"
  grep -nE '\bborder-b\b|\bborder-b-[0-9]' $D/devices.ex $D/section_header.ex | head -3
else ok "no bottom border under devices header (padding untouched)"; fi
# the accent underline bar in the shared section header
if grep -q 'h-px w-6 bg-accent' $D/section_header.ex; then
  bad "section_header still draws the h-px accent underline bar"
else ok "section_header underline bar removed"; fi

# --- 9. FLASH: bounded width, no raw inspect() leaking into toasts ------------
if grep -qE 'max-w-' lib/tunneld_web/components/core_components.ex; then
  ok "flash toast width is bounded"
else bad "flash has no max-width - long messages span the viewport"; fi
LEAK=$(grep -rnE '(message|flash).*#\{inspect\(' $DASH $D/devices.ex | wc -l | tr -d ' ')
if [ "$LEAK" -eq 0 ]; then ok "no raw inspect() in user-facing messages"
else bad "$LEAK raw inspect() calls still leak into flash messages"
     grep -rnE '(message|flash).*#\{inspect\(' $DASH $D/devices.ex | head -5; fi

# --- 10. MAP PINS: hover metadata wired (hook exists but was dead code) -------
if grep -q 'phx-hook="MapPinHover"' $D/map_card.ex && grep -q 'data-pin-' $D/map_card.ex; then
  ok "map pins wired to the MapPinHover hook with data-pin-* metadata"
else bad "map_card.ex still has no phx-hook/data-pin-* - hover tooltip stays dead code"; fi

# --- 11. "(HOST)" chip removed from the machines list ------------------------
if grep -q 'machine\["kind"\]' $D/machines.ex; then
  bad "machines.ex still renders the uppercase kind chip (shows as HOST)"
else ok "HOST kind chip removed from machines list"; fi

# --- 12. No dead JS hooks left registered ------------------------------------
for hook in Hemisphere MapPinHover Terminal; do
  if grep -q "Hooks.$hook" assets/js/hooks.js; then
    if grep -rq "phx-hook=\"$hook\"" lib/; then ok "hook $hook registered and used"
    else bad "hook $hook registered in hooks.js but never used in markup (dead code)"; fi
  else ok "hook $hook not registered"; fi
done

echo "-----------------------------------------------"
[ "$FAIL" -eq 0 ] && echo "UI GATE: PASS" || echo "UI GATE: FAIL"
exit $FAIL
