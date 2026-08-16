#!/bin/bash
# build_tdlib_dylib.sh - build TDLib as libtdjson.dylib for armv7.
#
# Why a dylib and not the static libs we already have: linking TDLib into the
# app statically pushes __TEXT past 19MB, and an armv7 Thumb BL only reaches
# +/-16MB. A working linker inserts branch islands; ld-27036.1 does not - it
# just fails with
#   "22-bit thumb branch out of range (displacement=19198446, max is +/-16MB)"
# Splitting TDLib into its own image keeps each __TEXT under the limit. This is
# also how TDLib normally ships.
#
# Output: build/armv7/tdlib/lib/libtdjson.dylib, install_name set so the app
# can carry it inside the bundle.
#
# NOTE: whether TDLib actually RUNS on iOS 7.1.2 is still unproven. It needs
# C++ thread_local, which iOS 7's dyld lacks - src/tlv_polyfill.c exists for
# exactly that reason but only covers the main binary.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TDLIB_SRC="${ROOT_DIR}/tdlib/td"
BUILD_DIR="${ROOT_DIR}/build/tdlib-dylib-armv7"
OUT_DIR="${ROOT_DIR}/build/armv7/tdlib/lib"

XCODE_DEV="$(xcode-select -p)"
SDK_PATH="${ROOT_DIR}/build/sdks/iPhoneOS12.4.sdk"
[ -d "${SDK_PATH}" ] || SDK_PATH="${XCODE_DEV}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
TOOLCHAIN="${XCODE_DEV}/Toolchains/XcodeDefault.xctoolchain/usr/bin"

# The theos SDK carries no C++ standard library headers, so point clang at
# Xcode's libc++ the same way the Makefile does.
XCODE_SDK="${XCODE_DEV}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
CXX_STDLIB_INC="-isystem ${XCODE_SDK}/usr/include/c++/v1"

for tool in cmake gperf; do
	command -v "$tool" >/dev/null || { echo "[-] $tool not found (brew install $tool)"; exit 1; }
done

echo "[+] TDLib -> libtdjson.dylib (armv7)"
echo "    src : ${TDLIB_SRC}"
echo "    sdk : ${SDK_PATH}"

# TDLib needs host-side code generation before it can cross-compile
if [ ! -d "${ROOT_DIR}/tdlib/native-build" ]; then
	echo "[+] pregenerating sources"
	mkdir -p "${ROOT_DIR}/tdlib/native-build"
	cd "${ROOT_DIR}/tdlib/native-build"
	cmake -DTD_GENERATE_SOURCE_FILES=ON "${TDLIB_SRC}"
	cmake --build . --target prepare_cross_compiling
fi

mkdir -p "${BUILD_DIR}" "${OUT_DIR}"

# clock_gettime and fdopendir are iOS 10 APIs. Against a modern SDK they link
# as weak imports and dyld resolves them to NULL on iOS 7 - TDLib then calls
# address 0 from one of its own threads. Provide strong definitions so the
# linker binds them here instead.
COMPAT_O="${BUILD_DIR}/ios7_compat.o"
"${TOOLCHAIN}/clang" -arch armv7 -mthumb -Os -isysroot "${SDK_PATH}" \
	-miphoneos-version-min=6.0 -c "${ROOT_DIR}/compat/ios7_compat.c" -o "${COMPAT_O}"
echo "[+] ios7 compat shims: ${COMPAT_O}"

cd "${BUILD_DIR}"

cmake "${TDLIB_SRC}" \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DCMAKE_C_COMPILER_LAUNCHER=ccache \
	-DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
	-DCMAKE_C_COMPILER="${TOOLCHAIN}/clang" \
	-DCMAKE_CXX_COMPILER="${TOOLCHAIN}/clang++" \
	-DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
	-DCMAKE_OSX_ARCHITECTURES="armv7" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=6.0 \
	-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
	-DATOMICS_FOUND=TRUE \
	-DATOMICS_LIBRARIES="" \
	-DCMAKE_C_FLAGS="-Wno-error -mthumb -Os -g -I${ROOT_DIR}" \
	-DCMAKE_CXX_FLAGS="-Wno-error -mthumb -Os -g -I${ROOT_DIR} ${CXX_STDLIB_INC}" \
	-DCMAKE_SHARED_LINKER_FLAGS="-install_name @executable_path/libtdjson.dylib ${COMPAT_O}" \
	-DOPENSSL_INCLUDE_DIR="${ROOT_DIR}/include" \
	-DOPENSSL_CRYPTO_LIBRARY="${ROOT_DIR}/build/armv7/libs/libcrypto.a" \
	-DOPENSSL_SSL_LIBRARY="${ROOT_DIR}/build/armv7/libs/libssl.a" \
	-DBUILD_SHARED_LIBS=ON \
	-DTD_ENABLE_LTO=OFF \
	-DCMAKE_POLICY_DEFAULT_CMP0074=NEW

# tdclientjson_export_list is not a CMake dependency, so an edit to it never
# relinks on its own and a newly exported symbol silently stays hidden.
find "${BUILD_DIR}" -name 'libtdjson*.dylib' -delete

cmake --build . --target tdjson -- -j"$(sysctl -n hw.logicalcpu)"

DYLIB="$(find "${BUILD_DIR}" -name 'libtdjson*.dylib' | head -1)"
[ -n "${DYLIB}" ] || { echo "[-] no dylib produced"; exit 1; }

cp -f "${DYLIB}" "${OUT_DIR}/libtdjson.dylib"
"${TOOLCHAIN}/dsymutil" "${OUT_DIR}/libtdjson.dylib" -o "${OUT_DIR}/libtdjson.dylib.dSYM" 2>&1 | tail -5 || true
# Debug build: keep full symbol table (no strip) so crash addresses resolve.

# CMake overrides -install_name with its own @rpath value; the app carries the
# dylib next to its binary, and iOS 7 has no @rpath support worth relying on.
install_name_tool -id "@executable_path/libtdjson.dylib" "${OUT_DIR}/libtdjson.dylib"

# Same broken armv7 linker, same lost Thumb bits - a dylib full of C++ vtables
# needs the fixup at least as much as the app does.
MACHOFIX="${ROOT_DIR}/build/tools/machofix"
[ -x "${MACHOFIX}" ] || cc -O2 -o "${MACHOFIX}" "${ROOT_DIR}/tools/machofix.c"
"${MACHOFIX}" "${OUT_DIR}/libtdjson.dylib"
ldid -S "${OUT_DIR}/libtdjson.dylib" 2>/dev/null || true

echo ""
echo "[+] ${OUT_DIR}/libtdjson.dylib"
ls -lh "${OUT_DIR}/libtdjson.dylib"
otool -l "${OUT_DIR}/libtdjson.dylib" | grep -A2 LC_ID_DYLIB | head -3
echo "    __TEXT size (must stay under 16MB for armv7 thumb branches):"
otool -l "${OUT_DIR}/libtdjson.dylib" | awk '/segname __TEXT/{f=1} f&&/vmsize/{print "    "$2; exit}'
