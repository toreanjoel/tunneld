#!/usr/bin/env bash
set -euo pipefail

[ -f mix.exs ] || { echo "Run from project root"; exit 1; }

APP=tunneld
DEST_DIR="$HOME/tunneld_build"

# Build the release
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
if [ -d assets ]; then MIX_ENV=prod mix assets.deploy; fi
MIX_ENV=prod mix release --overwrite

# Find the produced tarball from mix release.
# We try the common locations and pick the most recent one.
shopt -s nullglob

candidates=(
  "_build/prod/rel/$APP/releases/"*/"$APP-"*.tar.gz
  "_build/prod/$APP-"*.tar.gz
)

shopt -u nullglob

# Pick the newest candidate that exists
SRC=""
if [ ${#candidates[@]} -gt 0 ]; then
  # sort by mtime descending, take first
  SRC=$(ls -t "${candidates[@]}" 2>/dev/null | head -n1 || true)
fi

if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "ERROR: Could not find release tarball after mix release."
  echo "Looked in:"
  echo "  _build/prod/rel/$APP/releases/*/$APP-*.tar.gz"
  echo "  _build/prod/$APP-*.tar.gz"
  exit 1
fi

# Prepare destination folder
mkdir -p "$DEST_DIR"

# Always copy/rename to tunneld-pre-alpha.tar.gz
DEST_TAR="$DEST_DIR/$APP-pre-alpha.tar.gz"
cp -f "$SRC" "$DEST_TAR"

# Create checksums.txt with ONLY the hash (no filename/path)
sha256sum "$DEST_TAR" | awk '{print $1}' > "$DEST_DIR/checksums.txt"

echo "Saved build: $DEST_TAR"
echo "SHA256 written to: $DEST_DIR/checksums.txt"
cat "$DEST_DIR/checksums.txt"
