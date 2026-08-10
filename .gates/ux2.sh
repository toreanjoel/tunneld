#!/usr/bin/env bash
# Gate: ux2 — toast layout, device card sizing, device sync latency, modal dismissal.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 90
FAIL=0
bad(){ printf 'FAIL   %s\n' "$1"; FAIL=1; }
ok(){  printf 'ok     %s\n' "$1"; }
D=lib/tunneld_web/live/components
CC=lib/tunneld_web/components/core_components.ex

mix compile --warnings-as-errors >/tmp/x_c.log 2>&1 && ok "compile" || { bad "compile/warnings"; tail -20 /tmp/x_c.log; }
mix test >/tmp/x_t.log 2>&1 && ok "mix test" || { bad "tests"; tail -20 /tmp/x_t.log; }
mix format --check-formatted >/dev/null 2>&1 && ok "formatted" || bad "unformatted"

# --- 1. TOAST: title and message must stack, not sit in two wrapping columns ---
# Root cause: <p title> and <p msg> were siblings in `flex items-center`, so each
# became its own column and both wrapped independently.
if grep -q 'flex items-center gap-2' "$CC" && grep -q '<p :if={@title}' "$CC"; then
  bad "flash still lays title+message as flex-row siblings (two wrapping columns)"
else ok "flash title/message no longer flex-row siblings"; fi
if grep -qE 'items-start' "$CC"; then ok "flash aligns to top"; else bad "flash not items-start"; fi
if grep -qE 'break-words|break-all|overflow-wrap' "$CC"; then
  ok "flash wraps long words cleanly"
else bad "flash has no word-breaking - long tokens will wrap mid-word"; fi
if grep -qE 'min-w-0' "$CC"; then ok "flash text column can shrink (min-w-0)"
else bad "flash text column missing min-w-0 - flex child will not wrap correctly"; fi

# --- 2. DEVICE CARDS: one tagged card must not resize its whole row -----------
# CSS grid defaults to align-items:stretch, so the tallest card sets row height.
if grep -qE 'grid-cols-1 sm:grid-cols-2[^"]*' $D/devices.ex && \
   grep -qE 'items-start' $D/devices.ex; then
  ok "devices grid is items-start (cards size independently)"
else bad "devices grid still stretches - a tagged card resizes every card in its row"; fi
# the divider the owner asked to remove
if grep -qE '\bborder-t\b' $D/devices.ex; then
  bad "border-t divider still present in the device card"
  grep -nE '\bborder-t\b' $D/devices.ex | head -3
else ok "device card divider removed"; fi

# --- 3. DEVICE SYNC LATENCY --------------------------------------------------
# Was: 10s poll only. Mount waited for the next broadcast; mutations never
# triggered one. So init and every tag/lease change lagged up to 10 seconds.
if grep -qE 'def (sync_now|refresh)' lib/tunneld/servers/devices.ex; then
  ok "Devices exposes an immediate sync/refresh"
else bad "no Devices.sync_now/refresh - mutations still wait for the 10s poll"; fi
if grep -qE 'def (current|get_devices|list)\b' lib/tunneld/servers/devices.ex; then
  ok "Devices exposes current state for an immediate first paint"
else bad "no way to read current devices on mount - UI waits for a broadcast"; fi
# mutations must trigger it
MUT=0
for fn in revoke_lease add_tag remove_tag; do
  grep -qE "$fn" lib/tunneld_web/live/dashboard/actions.ex || continue
  MUT=$((MUT+1))
done
if grep -qE 'sync_now|refresh' lib/tunneld_web/live/dashboard/actions.ex lib/tunneld/servers/device_tags.ex lib/tunneld/servers/devices.ex; then
  ok "mutations trigger an immediate resync"
else bad "tag/lease mutations do not trigger an immediate resync"; fi
# first paint must not be a blind loading state
if grep -qE 'Devices\.(current|get_devices|list)' $D/devices.ex lib/tunneld_web/live/dashboard.ex; then
  ok "devices list paints from current state on mount"
else bad "devices still mount with loading:true and wait for the poll"; fi

# --- 4. MODALS: click outside and Escape must dismiss ------------------------
# NB: an earlier version of this check grepped for phx-click="modal_close"
# anywhere in the file, which passed trivially on the X button. It must be the
# BACKDROP element itself that is clickable, or the panel must use click-away.
python3 - <<'PY'
import re, sys
bad = []
for path in ["lib/tunneld_web/live/components/modal.ex",
             "lib/tunneld_web/live/components/enrollment_wizard.ex"]:
    try: s = open(path).read()
    except FileNotFoundError: continue
    # every backdrop = an element carrying `fixed inset-0`
    for m in re.finditer(r'<div\b([^>]*fixed inset-0[^>]*)>', s, re.S):
        attrs = m.group(1)
        if 'phx-click' not in attrs:
            line = s.count("\n", 0, m.start()) + 1
            # a click-away on the inner panel is an acceptable alternative
            tail = s[m.end():m.end()+900]
            if 'phx-click-away' not in tail:
                bad.append(f"{path}:{line} backdrop is not dismissable by outside click")
        if 'phx-key' not in attrs and 'phx-window-keydown' not in attrs:
            line = s.count("\n", 0, m.start()) + 1
            bad.append(f"{path}:{line} backdrop has no Escape handler")
for b in bad: print("       " + b)
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && ok "modals dismiss on outside click AND Escape" || bad "modal dismissal incomplete"

echo "-----------------------------------------------"
[ "$FAIL" -eq 0 ] && echo "UX2 GATE: PASS" || echo "UX2 GATE: FAIL"
exit $FAIL
