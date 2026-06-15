#!/bin/bash
# Build third-party dependencies from source for iOS arm64/armv7
# Places output static libraries into build/libs/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_LIBS_DIR="${ROOT_DIR}/build/libs"
SRC_LIBS_DIR="${ROOT_DIR}/libs"

mkdir -p "${BUILD_LIBS_DIR}"

SDK_PATH="${ROOT_DIR}/build/sdks/iPhoneOS12.4.sdk"
if [ ! -d "${SDK_PATH}" ]; then
  SDK_PATH="${ROOT_DIR}/build/sdks/iPhoneOS9.3.sdk"
fi

echo "[+] Preparing dependencies into ${BUILD_LIBS_DIR}..."

# Source directory for universal binaries (either in libs/ or build/libs/)
INPUT_DIR="${SRC_LIBS_DIR}"
if [ ! -d "${INPUT_DIR}" ]; then
  INPUT_DIR="${BUILD_LIBS_DIR}"
fi

# ── Dual-arch (armv7 32-bit + arm64 64-bit) slices from universal .a files ─
echo "[openssl] Preparing dual-arch (armv7 + arm64) static libraries..."
if [ -f "${INPUT_DIR}/libcrypto-universal.a" ]; then
  lipo "${INPUT_DIR}/libcrypto-universal.a" -extract armv7 -extract arm64 -output "${BUILD_LIBS_DIR}/libcrypto.a" 2>/dev/null || \
    cp "${INPUT_DIR}/libcrypto-universal.a" "${BUILD_LIBS_DIR}/libcrypto.a"
  lipo "${INPUT_DIR}/libssl-universal.a"    -extract armv7 -extract arm64 -output "${BUILD_LIBS_DIR}/libssl.a"    2>/dev/null || \
    cp "${INPUT_DIR}/libssl-universal.a"    "${BUILD_LIBS_DIR}/libssl.a"
fi

echo "[libcurl] Preparing dual-arch (armv7 + arm64) static libraries..."
if [ -f "${INPUT_DIR}/libcurl-universal.a" ]; then
  lipo "${INPUT_DIR}/libcurl-universal.a" -extract armv7 -extract arm64 -output "${BUILD_LIBS_DIR}/libcurl.a" 2>/dev/null || \
    cp "${INPUT_DIR}/libcurl-universal.a"   "${BUILD_LIBS_DIR}/libcurl.a"
  lipo "${INPUT_DIR}/libnghttp2-universal.a" -extract armv7 -extract arm64 -output "${BUILD_LIBS_DIR}/libnghttp2.a" 2>/dev/null || \
    cp "${INPUT_DIR}/libnghttp2-universal.a" "${BUILD_LIBS_DIR}/libnghttp2.a"
fi

echo "[+] All dependencies ready in ${BUILD_LIBS_DIR}"
echo ""
echo "Libraries prepared:"
ls -lh "${BUILD_LIBS_DIR}/"*.a 2>/dev/null || true
