#!/usr/bin/env bash
# Gate: polish — terminal scrollbar theming, render performance, and docs.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 90
FAIL=0
bad(){ printf 'FAIL   %s\n' "$1"; FAIL=1; }
ok(){  printf 'ok     %s\n' "$1"; }
CSS=assets/css/app.css
HOOK=assets/js/terminal_hook.js

mix compile --warnings-as-errors >/tmp/p_c.log 2>&1 && ok "compile" || { bad "compile"; tail -15 /tmp/p_c.log; }
mix test >/tmp/p_t.log 2>&1 && ok "mix test" || { bad "tests"; tail -15 /tmp/p_t.log; }
mix format --check-formatted >/dev/null 2>&1 && ok "formatted" || bad "unformatted"
# The JS bundle must actually BUILD. Without this a bad vendor import path only
# surfaces at release time, long after the gate went green.
if mix assets.build >/tmp/p_a.log 2>&1; then ok "assets build"
else bad "assets build FAILED"; tail -15 /tmp/p_a.log; fi
# and every vendor file the hook imports must exist
MISSINGV=0
while read -r vf; do
  [ -f "assets/$vf" ] || { bad "hook imports missing vendor file: assets/$vf"; MISSINGV=1; }
done < <(grep -oE '\.\./vendor/[A-Za-z0-9._-]+' assets/js/terminal_hook.js | sed 's|^\.\./||' | sort -u)
[ "$MISSINGV" -eq 0 ] && ok "hook vendor imports all resolve"

# --- 1. Scrollbar theming --------------------------------------------------
# xterm scrolls inside its OWN .xterm-viewport element. The app's .system-scroll
# utility never applies there, so it renders the default OS/browser scrollbar.
if grep -q 'xterm-viewport' "$CSS"; then ok "xterm viewport is themed"
else bad ".xterm-viewport not themed - terminal shows the default browser scrollbar"; fi
if grep -A6 'xterm-viewport' "$CSS" | grep -q '::-webkit-scrollbar'; then
  ok "webkit scrollbar rules for the terminal"
else bad "no ::-webkit-scrollbar rules for .xterm-viewport (Chrome/Safari)"; fi
if grep -A8 'xterm-viewport' "$CSS" | grep -qE 'scrollbar-color|scrollbar-width'; then
  ok "firefox scrollbar rules for the terminal"
else bad "no scrollbar-color/width for .xterm-viewport (Firefox)"; fi
# must reuse the existing palette, not invent a new one
if grep -A8 'xterm-viewport' "$CSS" | grep -q '#25232f'; then
  ok "terminal scrollbar reuses the app scrollbar colour"
else bad "terminal scrollbar does not match the app's #25232f thumb"; fi

# --- 2. Render performance --------------------------------------------------
# REVERSAL, and this IS a relaxation of an earlier requirement. This gate used to
# REQUIRE a vendored WebGL/canvas renderer. Shipping that produced a completely
# blank terminal in the browser - strictly worse than the "working but slow" DOM
# renderer it replaced. Most likely cause: the addon was activated against a
# container that still had zero dimensions inside a freshly-rendered modal (fit()
# is deferred to a setTimeout), which the DOM renderer tolerates and a GPU
# renderer does not. It was reverted rather than shipped a third time unverified,
# because none of it can be checked without a real browser.
# What remains required are the safe wins that need no GPU:
if grep -qE 'setTimeout|requestAnimationFrame|debounce' "$HOOK"; then
  ok "resize is debounced"
else bad "ResizeObserver calls fit()+sendResize() unthrottled on every frame"; fi
if grep -qE 'scrollback:\s*(1[0-9]{4}|[2-9][0-9]{4})' "$HOOK"; then
  bad "scrollback is very large - trims responsiveness and memory"
else ok "scrollback is bounded sensibly"; fi
# no orphaned vendored payload: every vendor file must be imported by something
for vf in assets/vendor/*.js; do
  b=$(basename "$vf"); stem="${b%.js}"   # imports may omit the .js extension
  if grep -rqE "vendor/${stem}(\.js)?[\"']" assets/js/ ; then ok "vendor in use: $b"
  else bad "orphaned vendored file (dead weight in every bundle): $b"; fi
done

# --- 3. Still no runtime CDN ------------------------------------------------
if grep -rqE 'https?://[^"]*(xterm|addon)' assets/js "$CSS" lib/ 2>/dev/null; then
  bad "terminal assets referenced from a CDN at runtime (gateway is LAN-only)"
else ok "no runtime CDN for terminal assets"; fi

# --- 4. Documentation -------------------------------------------------------
if bash .gates/docs.sh >/tmp/p_d.log 2>&1; then ok "curriculum gate passes (incl. terminal page)"
else bad "curriculum gate fails"; grep '^FAIL' /tmp/p_d.log | head -6; fi
# the terminal page must document what was actually learned the hard way
D=docs/curriculum/18-terminal-exec.html
if [ -f "$D" ]; then
  for t in "phx-update" "_csrf_token" "user_dir"; do
    grep -q "$t" "$D" && ok "docs cover $t" || bad "terminal docs do not mention $t"
  done
fi

echo "-----------------------------------------------"
[ "$FAIL" -eq 0 ] && echo "POLISH GATE: PASS" || echo "POLISH GATE: FAIL"
exit $FAIL
