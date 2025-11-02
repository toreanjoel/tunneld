#!/usr/bin/env bash
set -euo pipefail

[ -f mix.exs ] || { echo "Run from project root"; exit 1; }

APP=tunneld
VER="pre-alpha"
BUILD_DIR="_build/prod"
SRC_A="$BUILD_DIR/$APP-$VER.tar.gz"
SRC_B="_build/prod/rel/$APP/releases/$VER/$APP-$VER.tar.gz"
DEST_DIR="$HOME/tunneld_build"

MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
if [ -d assets ]; then MIX_ENV=prod mix assets.deploy; fi
MIX_ENV=prod mix release --overwrite

SRC="$SRC_A"
[ -f "$SRC" ] || SRC="$SRC_B"
[ -f "$SRC" ] || { echo "Release tar not found at: $SRC_A or $SRC_B"; exit 1; }

mkdir -p "$DEST_DIR"

# Always copy as tunneld-pre-alpha.tar.gz
DEST_TAR="$DEST_DIR/$APP-pre-alpha.tar.gz"
cp -f "$SRC" "$DEST_TAR"

# Generate SHA256 with only the hash (no filename, no path)
sha256sum "$DEST_TAR" | awk '{print $1}' > "$DEST_DIR/checksums.txt"

echo "Saved build: $DEST_TAR"
echo "SHA256 checksum: $DEST_DIR/checksums.txt"
cat "$DEST_DIR/checksums.txt"
