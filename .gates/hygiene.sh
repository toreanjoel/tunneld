#!/usr/bin/env bash
# Gate: hygiene — dead-code removal, formatting, stale-reference purge.
# Exits 0 only if EVERY check passes. Prints the reason for each failure.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 90
FAIL=0
say(){ printf '%-6s %s\n' "$1" "$2"; }
bad(){ say FAIL "$1"; FAIL=1; }
ok(){  say ok   "$1"; }

# --- 1. Build must stay green -------------------------------------------------
if mix compile --warnings-as-errors >/tmp/g_compile.log 2>&1; then
  ok "compile --warnings-as-errors"
else
  bad "compile failed / has warnings"; tail -30 /tmp/g_compile.log
fi

# --- 2. Tests must stay green -------------------------------------------------
if mix test >/tmp/g_test.log 2>&1; then
  ok "mix test ($(grep -oE '[0-9]+ tests' /tmp/g_test.log | tail -1))"
else
  bad "mix test failed"; tail -30 /tmp/g_test.log
fi

# --- 3. Formatting ------------------------------------------------------------
if mix format --check-formatted >/tmp/g_fmt.log 2>&1; then
  ok "mix format --check-formatted"
else
  bad "unformatted files: $(grep -c '^ ' /tmp/g_fmt.log 2>/dev/null || echo many)"
  head -20 /tmp/g_fmt.log
fi

# --- 4. Dead modules must be gone --------------------------------------------
for f in lib/tunneld/geo_data/centroids.ex \
         lib/tunneld/schema/machine.ex \
         lib/tunneld_web/live/components/devices_summary.ex; do
  [ -e "$f" ] && bad "dead module still present: $f" || ok "deleted: $f"
done

# --- 5. Dead functions must be gone ------------------------------------------
check_absent(){ # pattern file label
  if grep -qE "$1" "$2" 2>/dev/null; then bad "$3 still in $2"; else ok "$3 removed"; fi
}
check_absent '^  def world_map\b' lib/tunneld/geo_data/world_map.ex "world_map/1"
check_absent '^  def all_tags\b'   lib/tunneld/servers/device_tags.ex "all_tags/0"
check_absent '^  def ensure_lan_domain\b' lib/tunneld/servers/dns_config.ex "ensure_lan_domain/0"
check_absent '^  def find_service\b'      lib/tunneld/servers/services.ex "find_service/1"
check_absent '^  def get_service_logs\b'  lib/tunneld/servers/services.ex "get_service_logs/1"
check_absent 'incus_not_installed'        lib/tunneld_web/controllers/machine_controller.ex "dead incus 424 branch"

# --- 6. Stale Incus references purged from live code --------------------------
# runtime.ex may legitimately mention incus (runtime *detection*, TODO 4.3).
# Legitimate: runtime.ex (runtime DETECTION) and setup.ex:27 (product copy listing
# several runtimes as examples). Everything else is a stale Provider-era reference.
STALE=$(grep -rniE 'incus' lib/ --include=*.ex --include=*.heex \
        | grep -v 'lib/tunneld/machines/runtime.ex' \
        | grep -v 'lib/tunneld_web/live/setup.ex' | wc -l | tr -d ' ')
if [ "$STALE" -eq 0 ]; then ok "no stale incus refs (runtime.ex + setup.ex copy allowed)"
else bad "$STALE stale incus refs remain"
     grep -rniE 'incus' lib/ --include=*.ex --include=*.heex \
       | grep -v 'runtime.ex' | grep -v 'setup.ex' | head -15
fi

# --- 7. Tombstone comments referencing deleted modules ------------------------
TOMB=$(grep -rniE 'former .Tunneld\.(Servers\.)?(Nginx|Wlan)|Replaces the former|Provider module issues|after WireGuard mesh removal' \
       lib/ --include=*.ex | wc -l | tr -d ' ')
if [ "$TOMB" -eq 0 ]; then ok "no tombstone comments"
else bad "$TOMB tombstone comments remain"; grep -rniE 'Replaces the former|Provider module issues|after WireGuard mesh removal' lib/ --include=*.ex | head; fi

# --- 8. Stray files -----------------------------------------------------------
for f in erl_crash.dump .DS_Store; do
  [ -e "$f" ] && bad "stray file present: $f" || ok "absent: $f"
done
if git status --porcelain 2>/dev/null | grep -q '^?? ad/'; then
  bad "ad/ is untracked AND unignored (pollutes git status)"
else ok "ad/ not dangling in git status"; fi

# --- 9. Net line reduction (TODO principle 7: delete more than you add) -------
LIBLINES=$(find lib -name '*.ex' -o -name '*.heex' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
BASELINE=12237
TARGET=11237          # require >= 1000 lines removed (audit identified ~1480 safely removable)
if [ "$LIBLINES" -le "$TARGET" ]; then
  ok "lib/ shrank: $BASELINE -> $LIBLINES ($((BASELINE-LIBLINES)) lines removed)"
else
  bad "lib/ must be <= $TARGET, is $LIBLINES (only $((BASELINE-LIBLINES)) removed)"
fi

echo "-----------------------------------------------"
[ "$FAIL" -eq 0 ] && echo "HYGIENE GATE: PASS" || echo "HYGIENE GATE: FAIL"
exit $FAIL
