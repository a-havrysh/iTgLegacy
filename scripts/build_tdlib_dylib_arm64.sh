#!/bin/bash
# build_tdlib_dylib_arm64.sh - build TDLib as libtdjson.dylib for arm64.
#
# Same dlopen-based design as build_tdlib_dylib.sh (see src/TGClient.m):
# TGClient dlopens libtdjson.dylib from the app bundle at runtime, so no
# static tdlib linking is needed for arm64 either.
#
# Output: build/arm64/tdlib/lib/libtdjson.dylib

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TDLIB_SRC="${ROOT_DIR}/tdlib/td"
BUILD_DIR="${ROOT_DIR}/build/tdlib-dylib-arm64"
OUT_DIR="${ROOT_DIR}/build/arm64/tdlib/lib"

XCODE_DEV="$(xcode-select -p)"
SDK_PATH="${ROOT_DIR}/build/sdks/iPhoneOS12.4.sdk"
[ -d "${SDK_PATH}" ] || SDK_PATH="${XCODE_DEV}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
TOOLCHAIN="${XCODE_DEV}/Toolchains/XcodeDefault.xctoolchain/usr/bin"

XCODE_SDK="${XCODE_DEV}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
CXX_STDLIB_INC="-isystem ${XCODE_SDK}/usr/include/c++/v1"

for tool in cmake gperf; do
	command -v "$tool" >/dev/null || { echo "[-] $tool not found (brew install $tool)"; exit 1; }
done

echo "[+] TDLib -> libtdjson.dylib (arm64)"
echo "    src : ${TDLIB_SRC}"
echo "    sdk : ${SDK_PATH}"

if [ ! -d "${ROOT_DIR}/tdlib/native-build" ]; then
	echo "[+] pregenerating sources"
	mkdir -p "${ROOT_DIR}/tdlib/native-build"
	cd "${ROOT_DIR}/tdlib/native-build"
	cmake -DTD_GENERATE_SOURCE_FILES=ON "${TDLIB_SRC}"
	cmake --build . --target prepare_cross_compiling
fi

mkdir -p "${BUILD_DIR}" "${OUT_DIR}"

cd "${BUILD_DIR}"

cmake "${TDLIB_SRC}" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_C_COMPILER_LAUNCHER=ccache \
	-DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
	-DCMAKE_C_COMPILER="${TOOLCHAIN}/clang" \
	-DCMAKE_CXX_COMPILER="${TOOLCHAIN}/clang++" \
	-DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
	-DCMAKE_OSX_ARCHITECTURES="arm64" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=9.0 \
	-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
	-DATOMICS_FOUND=TRUE \
	-DATOMICS_LIBRARIES="" \
	-DCMAKE_C_FLAGS="-Wno-error -Os" \
	-DCMAKE_CXX_FLAGS="-Wno-error -Os ${CXX_STDLIB_INC}" \
	-DCMAKE_SHARED_LINKER_FLAGS="-install_name @executable_path/libtdjson.dylib" \
	-DOPENSSL_INCLUDE_DIR="${ROOT_DIR}/include" \
	-DOPENSSL_CRYPTO_LIBRARY="${ROOT_DIR}/build/arm64/libs/libcrypto.a" \
	-DOPENSSL_SSL_LIBRARY="${ROOT_DIR}/build/arm64/libs/libssl.a" \
	-DBUILD_SHARED_LIBS=ON \
	-DTD_ENABLE_LTO=OFF \
	-DCMAKE_POLICY_DEFAULT_CMP0074=NEW

cmake --build . --target tdjson -- -j"$(sysctl -n hw.logicalcpu)"

DYLIB="$(find "${BUILD_DIR}" -name 'libtdjson*.dylib' | head -1)"
[ -n "${DYLIB}" ] || { echo "[-] no dylib produced"; exit 1; }

cp -f "${DYLIB}" "${OUT_DIR}/libtdjson.dylib"
"${TOOLCHAIN}/strip" -x "${OUT_DIR}/libtdjson.dylib" 2>/dev/null || true
install_name_tool -id "@executable_path/libtdjson.dylib" "${OUT_DIR}/libtdjson.dylib"
ldid -S "${OUT_DIR}/libtdjson.dylib" 2>/dev/null || true

echo ""
echo "[+] ${OUT_DIR}/libtdjson.dylib"
ls -lh "${OUT_DIR}/libtdjson.dylib"
