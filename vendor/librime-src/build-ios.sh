#!/usr/bin/env bash
# Build librime for iOS (arm64 device + arm64 simulator)
# Run from repo root: ./vendor/librime-src/build-ios.sh
#
# Prerequisites:
#   brew install cmake boost glog yaml-cpp leveldb marisa opencc
#
# This script clones librime, applies our patches, and builds static libraries.
# Output: Frameworks/librime.xcframework/{ios-arm64,ios-arm64-simulator}/librime.a

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="/tmp/librime-build"
PATCH_DIR="$SCRIPT_DIR/src"

echo "=== Cloning librime ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
git clone --depth 1 https://github.com/rime/librime.git

echo "=== Applying patches ==="
cp "$PATCH_DIR/rime_api.h" librime/src/rime_api.h
cp "$PATCH_DIR/rime_replace_input.cc" librime/src/rime_replace_input.cc
cp "$PATCH_DIR/CMakeLists.txt" librime/src/CMakeLists.txt
cp "$PATCH_DIR/rime/gear/gears_module.cc" librime/src/rime/gear/gears_module.cc

CMAKE_COMMON_ARGS=(
  -DCMAKE_SYSTEM_NAME=iOS
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
  -DCMAKE_OSX_ARCHITECTURES=arm64
  -DBUILD_SHARED_LIBS=OFF
  -DBUILD_TEST=OFF
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
  -DCMAKE_FIND_ROOT_PATH="/opt/homebrew"
  -DCMAKE_C_FLAGS="-Oz"
  -DCMAKE_CXX_FLAGS="-Oz"
)

echo "=== Building for iOS device (arm64) ==="
mkdir -p build-device && cd build-device
cmake "$BUILD_DIR/librime" "${CMAKE_COMMON_ARGS[@]}" -DCMAKE_OSX_SYSROOT=iphoneos
make -j$(sysctl -n hw.ncpu)
cd ..

echo "=== Building for iOS simulator (arm64) ==="
mkdir -p build-sim && cd build-sim
cmake "$BUILD_DIR/librime" "${CMAKE_COMMON_ARGS[@]}" -DCMAKE_OSX_SYSROOT=iphonesimulator
make -j$(sysctl -n hw.ncpu)
cd ..

echo "=== Installing to xcframework ==="
FRAMEWORK_DIR="$REPO_ROOT/Frameworks/librime.xcframework"
cp build-device/lib/librime.a "$FRAMEWORK_DIR/ios-arm64/librime.a"
cp build-sim/lib/librime.a "$FRAMEWORK_DIR/ios-arm64-simulator/librime.a"

echo "=== Done ==="
ls -lh "$FRAMEWORK_DIR/ios-arm64/librime.a"
ls -lh "$FRAMEWORK_DIR/ios-arm64-simulator/librime.a"
echo ""
echo "NOTE: This build does NOT include Lua support."
echo "Lua adds ~38MB to the binary and exceeds iOS keyboard extension memory limits."
echo "To add Lua, use src-with-lua/gears_module.cc and add lua dirs to CMakeLists.txt."
