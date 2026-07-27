#!/usr/bin/env bash
# AI-OS run-capture v1.0 — the terminal error channel (any language, any command).
# Usage:  bash run-capture.sh <command ...>
#   e.g.  bash run-capture.sh python3 main.py
#         bash run-capture.sh mix test
#         bash run-capture.sh npm run build
# On failure: writes the universal ERROR REPORT to .ai/REPORT.txt and prints it,
# formatted for pasting straight back to an AI. All runs append to .ai/run.log.
# Configure workspace dir with AI_WORKSPACE (default: .ai in the current directory).
set -u

if [ "$#" -eq 0 ]; then
  echo "usage: run-capture.sh <command ...>" >&2
  exit 2
fi

DIR="${AI_WORKSPACE:-.ai}"
mkdir -p "$DIR"
LOG="$DIR/run.log"
REP="$DIR/REPORT.txt"
OUT="$DIR/.out.$$"
ERR="$DIR/.err.$$"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
CMD="$*"

# Run the command, buffered capture (tradeoff: no live streaming, full fidelity).
"$@" >"$OUT" 2>"$ERR"
EC=$?

# Append everything to the running log.
{
  echo "===== RUN $TS | exit=$EC | $CMD"
  echo "--- stdout ---"; cat "$OUT"
  echo "--- stderr ---"; cat "$ERR"
} >>"$LOG"

if [ "$EC" -ne 0 ]; then
  {
    echo "=== ERROR REPORT (paste this to your AI) ==="
    echo "cmd: $CMD"
    echo "cwd: $(pwd)"
    echo "exit: $EC"
    echo "time: $TS"
    echo "--- stderr (last 40 lines) ---"
    tail -n 40 "$ERR"
    echo "--- stdout (last 15 lines) ---"
    tail -n 15 "$OUT"
    echo "==="
  } | tee "$REP"
  echo "[run-capture] report saved: $REP (full history: $LOG)" >&2
else
  # Success: pass stdout through untouched, one quiet status line to stderr.
  cat "$OUT"
  echo "[run-capture] OK exit=0 $TS (logged: $LOG)" >&2
fi

rm -f "$OUT" "$ERR"
exit "$EC"
