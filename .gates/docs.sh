#!/usr/bin/env bash
# Gate: docs — the learning curriculum. Structure + depth + no placeholders.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 90
FAIL=0
bad(){ printf 'FAIL   %s\n' "$1"; FAIL=1; }
ok(){  printf 'ok     %s\n' "$1"; }

DOCS=docs/curriculum
[ -d "$DOCS" ] || { bad "missing directory $DOCS"; echo "DOCS GATE: FAIL"; exit 1; }

# --- 1. Required pages exist --------------------------------------------------
REQUIRED_PAGES="index.html
00-orientation.html
01-architecture.html
02-networking-foundations.html
03-wireguard.html
04-iptables-nat.html
05-routing-tables-egress.html
06-caddy-reverse-proxy.html
07-dns-dnsmasq-dhcp.html
08-ssh-transport.html
09-elixir-otp-supervision.html
10-phoenix-liveview.html
11-persistence-state.html
12-agent-api-auth.html
13-build-release-deploy.html
14-testing-mock-mode.html
15-systemd-service-lifecycle.html
16-pooling-load-balancing.html
17-glossary.html"
for p in $REQUIRED_PAGES; do
  if [ -f "$DOCS/$p" ]; then ok "page: $p"; else bad "missing page: $DOCS/$p"; fi
done

# --- 2. Depth: subsystem pages must be substantial ----------------------------
# A page that merely names a tool teaches nothing. Require real word count.
for f in "$DOCS"/0[2-9]-*.html "$DOCS"/1[0-6]-*.html; do
  [ -f "$f" ] || continue
  words=$(sed -e 's/<[^>]*>/ /g' "$f" | tr -s '[:space:]' ' ' | wc -w | tr -d ' ')
  if [ "$words" -ge 900 ]; then ok "depth $(basename "$f"): ${words}w"
  else bad "$(basename "$f") too thin: ${words}w (need >=900)"; fi
done

# --- 3. Every subsystem page answers the four required questions --------------
# The user asked for: what it is, how it works, what we used it for, why, examples.
for f in "$DOCS"/0[2-9]-*.html "$DOCS"/1[0-6]-*.html; do
  [ -f "$f" ] || continue
  b=$(basename "$f"); miss=""
  grep -qi 'id="what-it-is"'      "$f" || miss="$miss what-it-is"
  grep -qi 'id="how-it-works"'    "$f" || miss="$miss how-it-works"
  grep -qi 'id="how-tunneld-uses-it"' "$f" || miss="$miss how-tunneld-uses-it"
  grep -qi 'id="why"'             "$f" || miss="$miss why"
  grep -qi 'id="examples"'        "$f" || miss="$miss examples"
  if [ -z "$miss" ]; then ok "sections $b"; else bad "$b missing section ids:$miss"; fi
done

# --- 4. Examples must be real commands, not prose -----------------------------
for f in "$DOCS"/0[2-9]-*.html "$DOCS"/1[0-6]-*.html; do
  [ -f "$f" ] || continue
  n=$(grep -c '<pre' "$f")
  if [ "$n" -ge 3 ]; then ok "code blocks $(basename "$f"): $n"
  else bad "$(basename "$f") has $n <pre> blocks (need >=3 worked examples)"; fi
done

# --- 5. Citations into the real codebase --------------------------------------
# A curriculum about THIS system must point at THIS system's files.
for f in "$DOCS"/0[1-9]-*.html "$DOCS"/1[0-6]-*.html; do
  [ -f "$f" ] || continue
  if grep -qE 'lib/tunneld[a-z_/]*\.ex' "$f"; then ok "cites source $(basename "$f")"
  else bad "$(basename "$f") cites no lib/tunneld/*.ex file"; fi
done

# --- 6. No placeholders -------------------------------------------------------
# NB: an earlier version of this gate also flagged lines ending in '...', which
# false-positived on legitimately elided terminal OUTPUT (truncated `ip route`
# output, redacted token suffixes). Real placeholder words only.
PH=$(grep -rniE 'lorem ipsum|\bTBD\b|TODO:|FIXME|coming soon|placeholder' "$DOCS" --include=*.html | wc -l | tr -d ' ')
if [ "$PH" -eq 0 ]; then ok "no placeholder text"
else bad "$PH placeholder markers found"; grep -rniE 'lorem ipsum|TBD|TODO:|FIXME|coming soon|placeholder' "$DOCS" --include=*.html | head -8; fi

# --- 7. Internal links resolve ------------------------------------------------
BROKEN=0
for f in "$DOCS"/*.html; do
  for href in $(grep -oE 'href="[^"#:]+\.html' "$f" | sed 's/href="//'); do
    [ -f "$DOCS/$href" ] || { echo "       broken link in $(basename "$f"): $href"; BROKEN=$((BROKEN+1)); }
  done
done
[ "$BROKEN" -eq 0 ] && ok "all internal links resolve" || bad "$BROKEN broken internal links"

# --- 8. index.html must link every page ---------------------------------------
MISSINGNAV=0
for p in $REQUIRED_PAGES; do
  [ "$p" = "index.html" ] && continue
  grep -q "$p" "$DOCS/index.html" 2>/dev/null || { echo "       index.html does not link $p"; MISSINGNAV=$((MISSINGNAV+1)); }
done
[ "$MISSINGNAV" -eq 0 ] && ok "index links every page" || bad "index.html misses $MISSINGNAV pages"

# --- 9. Self-contained: no external CDN dependency ----------------------------
CDN=$(grep -rlE 'src="https?://|href="https?://[^"]*\.css' "$DOCS" --include=*.html | wc -l | tr -d ' ')
[ "$CDN" -eq 0 ] && ok "no external CDN assets (works offline)" \
  || { bad "$CDN pages depend on external CDN assets"; grep -rlE 'src="https?://' "$DOCS" --include=*.html | head -5; }

# --- 10. Valid, parseable HTML ------------------------------------------------
python3 - "$DOCS" <<'PY'
import sys, glob, os
from html.parser import HTMLParser
class P(HTMLParser):
    def __init__(self): super().__init__(); self.err=0
bad=[]
for f in sorted(glob.glob(os.path.join(sys.argv[1],"*.html"))):
    s=open(f,encoding="utf-8",errors="replace").read()
    if "<!DOCTYPE" not in s[:200] and "<!doctype" not in s[:200]: bad.append((f,"no doctype"))
    if "<title" not in s: bad.append((f,"no <title>"))
    try:
        p=P(); p.feed(s)
    except Exception as e: bad.append((f,f"parse error {e}"))
for f,r in bad: print(f"       {os.path.basename(f)}: {r}")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && ok "html parses, has doctype + title" || bad "html structural problems"


# --- 11. Cited code must actually exist in the codebase ----------------------
# A curriculum that invents plausible-looking functions teaches the wrong system.
python3 - <<'PY'
import re, glob, os, sys
root = os.getcwd()
src = ""
for p in glob.glob(os.path.join(root, "lib/**/*.ex"), recursive=True):
    src += open(p, errors="replace").read()
defined = set(re.findall(r'def[p]?\s+([a-z_][a-z0-9_?!]*)', src))
mods = set(re.findall(r'defmodule\s+([A-Za-z0-9_.]+)', src))
bad = []
for f in sorted(glob.glob(os.path.join(root, "docs/curriculum/*.html"))):
    html = open(f, encoding="utf-8", errors="replace").read()
    for block in re.findall(r'<pre[^>]*>(.*?)</pre>', html, re.S):
        # only audit blocks that claim to come from this repo
        if not re.search(r'lib/tunneld[a-z_/]*\.ex', block):
            continue
        for fn in re.findall(r'^\s*def[p]?\s+([a-z_][a-z0-9_?!]*)', block, re.M):
            if fn not in defined:
                bad.append((os.path.basename(f), fn))
for f, fn in bad:
    print(f"       {f}: cites def {fn}/? which does not exist in lib/")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && ok "cited functions exist in lib/" || bad "curriculum cites non-existent functions"

echo "-----------------------------------------------"
[ "$FAIL" -eq 0 ] && echo "DOCS GATE: PASS" || echo "DOCS GATE: FAIL"
exit $FAIL
