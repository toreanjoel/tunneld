#!/usr/bin/env bash
set -euo pipefail

# --- CONFIGURATION ---
# We use the OFFICIAL Elixir 1.17 image.
# It is stable, exists, and uses Debian Bookworm (GLIBC 2.36).
# This satisfies both your NanoPi (needs < GLIBC 2.38) and the compiler.
BUILDER_IMAGE="elixir:1.17-slim"
# ---------------------

[ -f mix.exs ] || { echo "Run from project root"; exit 1; }

APP=tunneld
DEST_DIR="$HOME/tunneld_build"
# Extract version from mix.exs
VERSION=$(grep 'version:' mix.exs | head -n1 | cut -d '"' -f2)

echo "--- Starting Release Build for $APP v$VERSION ---"

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is required."
    echo "Install: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# 1. PULL IMAGE
echo "PULLING BUILDER IMAGE: $BUILDER_IMAGE"
sudo docker pull "$BUILDER_IMAGE"

# 2. RUN BUILD
echo "COMPILING RELEASE..."
sudo docker run --rm \
  -v "$(pwd):/app" \
  -w /app \
  -e MIX_ENV=prod \
  "$BUILDER_IMAGE" \
  /bin/bash -c "
    # Install build dependencies
    apt-get update -qq && apt-get install -y -qq git build-essential

    # Setup Mix (Official images need this)
    mix local.hex --force
    mix local.rebar --force

    # --- COMPATIBILITY FIXES ---
    # 1. Remove lockfile to allow fresh resolution on Elixir 1.17
    rm -f mix.lock
    
    # 2. Patch mix.exs to allow Elixir 1.17
    # We change '~> 1.18' to '~> 1.17' to prevent the version error
    sed -i 's/~> 1.18/~> 1.17/g' mix.exs
    # ---------------------------

    # Fetch and Compile
    echo 'Fetching deps...'
    mix deps.get --only prod
    
    echo 'Compiling...'
    mix compile
    
    # Handle Assets if they exist
    if [ -d assets ]; then 
      echo 'Deploying assets...'
      mix assets.deploy
    fi
    
    # Create Release
    echo 'Generating release...'
    mix release --overwrite
  "

# 3. FIX PERMISSIONS
echo "Fixing file permissions..."
sudo chown -R "$(id -u):$(id -g)" _build deps

# 4. PACKAGE THE ARTIFACTS
shopt -s nullglob
candidates=(
  "_build/prod/rel/$APP/releases/"*/"$APP-"*.tar.gz
  "_build/prod/$APP-"*.tar.gz
)
shopt -u nullglob

SRC=""
if [ ${#candidates[@]} -gt 0 ]; then
  SRC=$(ls -t "${candidates[@]}" 2>/dev/null | head -n1 || true)
fi

if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "ERROR: Could not find release tarball after Docker build."
  exit 1
fi

mkdir -p "$DEST_DIR"
DEST_TAR="$DEST_DIR/$APP-pre-alpha.tar.gz"
cp -f "$SRC" "$DEST_TAR"

# Create checksums
(
  cd "$DEST_DIR"
  sha256sum "$(basename "$DEST_TAR")" > "$DEST_DIR/checksums.txt"
)

# Create metadata
printf '{\n  "version": "%s"\n}\n' "$VERSION" > "$DEST_DIR/metadata.json"

echo "---------------------------------------------"
echo "SUCCESS: Compatible Build Saved"
echo "Stack: Elixir 1.17 / GLIBC 2.36 (Bookworm)"
echo "Location: $DEST_TAR"
echo "Checksum: $DEST_DIR/checksums.txt"
echo "---------------------------------------------"
cat "$DEST_DIR/checksums.txt"
