#!/usr/bin/env bash
set -euo pipefail

[ -f mix.exs ] || { echo "Run from project root"; exit 1; }

read -rp "Version (e.g. 0.4.0): " VER
[ -n "$VER" ] || { echo "Version is required"; exit 1; }

APP=tunneld
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
cp -f "$SRC" "$DEST_DIR/"

sha256sum "$DEST_DIR/$APP-$VER.tar.gz" > "$DEST_DIR/$APP-$VER.tar.gz.sha256"

echo "Saved: $DEST_DIR/$APP-$VER.tar.gz"
echo "SHA256: $DEST_DIR/$APP-$VER.tar.gz.sha256"
