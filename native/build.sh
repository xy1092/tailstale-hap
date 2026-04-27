#!/bin/bash
# Build script: cross-compile Rust + NAPI bridge for HarmonyOS ARM64
# Prerequisites:
#   rustup target add aarch64-unknown-linux-gnu
#   pacman -S aarch64-linux-gnu-gcc nodejs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="aarch64-unknown-linux-gnu"
TARGET_DIR="$SCRIPT_DIR/target/$TARGET/release"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
export PATH="$HOME/.cargo/bin:$PATH"

echo "=== Step 1/4: Build Rust staticlib ==="
cd "$SCRIPT_DIR" && cargo build --target "$TARGET" --release 2>&1

echo "=== Step 2/4: Link NAPI bridge with Rust staticlib ==="
aarch64-linux-gnu-gcc -shared -fPIC \
  -I/usr/include/node \
  "$SCRIPT_DIR/src/napi_bridge.c" \
  "$TARGET_DIR/libhm_tailscale_native.a" \
  -lpthread -ldl -lm \
  -o "$TARGET_DIR/libhm_tailscale_native.so"

echo "=== Step 3/4: Strip debug symbols ==="
aarch64-linux-gnu-strip "$TARGET_DIR/libhm_tailscale_native.so"

echo "=== Step 4/4: Copy to HarmonyOS project ==="
mkdir -p "$PROJECT_ROOT/entry/libs/arm64-v8a"
cp "$TARGET_DIR/libhm_tailscale_native.so" "$PROJECT_ROOT/entry/libs/arm64-v8a/"

echo "=== Done ==="
ls -lh "$PROJECT_ROOT/entry/libs/arm64-v8a/libhm_tailscale_native.so"
file "$PROJECT_ROOT/entry/libs/arm64-v8a/libhm_tailscale_native.so"
