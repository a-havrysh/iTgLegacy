#!/bin/bash
# Build TDLib for iOS arm64 (min deployment target iOS 6.0)
#
# Prerequisites:
#   brew install cmake gperf openssl
#
# Output:
#   tdlib/build/libtd.a          — static TDLib library
#   tdlib/build/libtdclient.a    — TDLib client helpers
#   tdlib/include/               — installed public headers
#
# After running this script, the main build_ipa.sh will automatically
# pick up the headers (via -I../tdlib/td) and link against libtd.a.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TDLIB_SRC="${ROOT_DIR}/tdlib/td"
TDLIB_BUILD="${ROOT_DIR}/build/tdlib/build"
TDLIB_INSTALL="${ROOT_DIR}/build/tdlib"

# Prefer Xcode SDK over theos SDK (Xcode provides full C++ stdlib headers)
XCODE_DEV="/Applications/Xcode-beta.app/Contents/Developer"
if [ -d "${XCODE_DEV}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk" ]; then
  SDK_PATH="${XCODE_DEV}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
  XCODE_TOOLCHAIN="${XCODE_DEV}/Toolchains/XcodeDefault.xctoolchain/usr/bin"
  CMAKE_C_COMPILER="${XCODE_TOOLCHAIN}/clang"
  CMAKE_CXX_COMPILER="${XCODE_TOOLCHAIN}/clang++"
else
  # Fall back to theos SDK (requires Xcode or LLVM with full libc++ headers)
  SDK_PATH="${ROOT_DIR}/build/sdks/iPhoneOS12.4.sdk"
  if [ ! -d "${SDK_PATH}" ]; then
    SDK_PATH="${ROOT_DIR}/build/sdks/iPhoneOS9.3.sdk"
  fi
  CMAKE_C_COMPILER="$(which clang)"
  CMAKE_CXX_COMPILER="$(which clang++)"
fi
if [ ! -d "${SDK_PATH}" ]; then
  echo "[-] iOS SDK not found. Run scripts/setup_sdk.sh first."
  exit 1
fi

# Check requirements
for tool in cmake gperf; do
  if ! command -v "$tool" &>/dev/null; then
    echo "[-] $tool not found. Install with: brew install $tool"
    exit 1
  fi
done

echo "[+] Building TDLib for iOS arm64"
echo "    src  : ${TDLIB_SRC}"
echo "    build: ${TDLIB_BUILD}"
echo "    sdk  : ${SDK_PATH}"
echo ""

echo "[+] Pregenerating TDLib source files..."
mkdir -p "${ROOT_DIR}/tdlib/native-build"
cd "${ROOT_DIR}/tdlib/native-build"
cmake -DTD_GENERATE_SOURCE_FILES=ON "${TDLIB_SRC}"
cmake --build . --target prepare_cross_compiling

mkdir -p "${TDLIB_BUILD}"
cd "${TDLIB_BUILD}"

# Find the C++ stdlib headers from the active clang (Homebrew LLVM)
CLANG_RESOURCE_DIR=$(clang -print-resource-dir 2>/dev/null)
CXX_STDLIB_INCLUDE=$(clang -target arm64-apple-ios12.0 -isysroot "${SDK_PATH}" -x c++ -v /dev/null 2>&1 \
  | grep 'c++/v1' | awk '{print $1}' | head -1)
if [ -z "${CXX_STDLIB_INCLUDE}" ]; then
  # Fallback: use Homebrew LLVM include directly
  CXX_STDLIB_INCLUDE=$(ls -d /opt/homebrew/Cellar/llvm/*/include/c++/v1 2>/dev/null | tail -1)
fi
echo "[+] Using C++ stdlib headers: ${CXX_STDLIB_INCLUDE}"

OPENSSL_ROOT="$(brew --prefix openssl@1.1 2>/dev/null || brew --prefix openssl)"

cmake "${TDLIB_SRC}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${TDLIB_INSTALL}" \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_C_COMPILER="${CMAKE_C_COMPILER}" \
  -DCMAKE_CXX_COMPILER="${CMAKE_CXX_COMPILER}" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
  -DCMAKE_OSX_ARCHITECTURES="armv7;arm64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=9.0 \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DATOMICS_FOUND=TRUE \
  -DATOMICS_LIBRARIES="" \
  -DCMAKE_CXX_FLAGS="-Wno-error" \
  -DCMAKE_C_FLAGS="-Wno-error" \
  -DOPENSSL_ROOT_DIR="${OPENSSL_ROOT}" \
  -DOPENSSL_INCLUDE_DIR="${ROOT_DIR}/include" \
  -DOPENSSL_CRYPTO_LIBRARY="${ROOT_DIR}/build/libs/libcrypto.a" \
  -DOPENSSL_SSL_LIBRARY="${ROOT_DIR}/build/libs/libssl.a" \
  -DBUILD_SHARED_LIBS=OFF \
  -DTD_ENABLE_LTO=OFF \
  -DCMAKE_POLICY_DEFAULT_CMP0074=NEW

cmake --build . --target tdjson_static -- -j$(sysctl -n hw.logicalcpu)
cmake --build . --target tdclient -- -j$(sysctl -n hw.logicalcpu)

mkdir -p "${TDLIB_INSTALL}/lib" "${TDLIB_INSTALL}/include/td/telegram"
find . -name "libtd*.a" -exec cp {} "${TDLIB_INSTALL}/lib/" \; 2>/dev/null || true
cp -rf "${TDLIB_SRC}/td/telegram/"*.h "${TDLIB_INSTALL}/include/td/telegram/" 2>/dev/null || true
cp -rf "${ROOT_DIR}/tdlib/install/include/td/telegram/"*.h "${TDLIB_INSTALL}/include/td/telegram/" 2>/dev/null || true
find "${TDLIB_BUILD}" -name "*.h" -exec cp {} "${TDLIB_INSTALL}/include/td/telegram/" \; 2>/dev/null || true

# Clean up temporary CMake objects directory to keep build/tdlib clean
rm -rf "${TDLIB_BUILD}"

echo ""
echo "[+] TDLib static libraries built and installed to ${TDLIB_INSTALL}"
echo "    Headers : ${TDLIB_INSTALL}/include/"
echo "    Libs    : $(ls ${TDLIB_INSTALL}/lib/*.a 2>/dev/null | tr '\n' ' ')"
echo ""
echo "Next: run ./scripts/build_ipa.sh"
