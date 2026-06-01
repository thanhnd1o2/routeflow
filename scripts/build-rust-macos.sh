#!/bin/bash
# Build RouteFlow Rust core for macOS (Apple Silicon + Intel)
# Run this script from the project root on your Mac.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/rust-core"
OUTPUT_DIR="$PROJECT_ROOT/RouteFlow/Libraries"

echo "==> Building RouteFlow Rust core for macOS..."
echo "    Rust dir: $RUST_DIR"
echo "    Output:   $OUTPUT_DIR"

# Ensure targets are installed
rustup target add aarch64-apple-darwin x86_64-apple-darwin 2>/dev/null || true

cd "$RUST_DIR"

# Build for Apple Silicon (arm64)
echo ""
echo "==> Building for aarch64-apple-darwin (Apple Silicon)..."
cargo build --release --target aarch64-apple-darwin

# Build for Intel (x86_64)
echo ""
echo "==> Building for x86_64-apple-darwin (Intel)..."
cargo build --release --target x86_64-apple-darwin

# Create universal binary
echo ""
echo "==> Creating universal static library..."
mkdir -p "$OUTPUT_DIR"

lipo -create \
    "target/aarch64-apple-darwin/release/librouteflow_core.a" \
    "target/x86_64-apple-darwin/release/librouteflow_core.a" \
    -output "$OUTPUT_DIR/librouteflow_core.a"

# Copy header
cp "include/routeflow_core.h" "$OUTPUT_DIR/"

echo ""
echo "==> Build complete!"
echo "    Static library: $OUTPUT_DIR/librouteflow_core.a"
echo "    Header:         $OUTPUT_DIR/routeflow_core.h"
echo ""
echo "==> Xcode Integration:"
echo "    1. Add librouteflow_core.a to your target's 'Link Binary With Libraries'"
echo "    2. Add $OUTPUT_DIR to 'Library Search Paths'"
echo "    3. Add the Bridge directory to 'Header Search Paths'"
echo "    4. Set 'Import Paths' to include the module.modulemap directory"
echo "    5. Or use a Bridging Header that includes routeflow_core.h"
