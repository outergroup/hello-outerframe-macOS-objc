#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FILE="${SCRIPT_DIR}/HelloWorldObjC.xcodeproj"
SCHEME_NAME="${SCHEME_NAME:-HelloWorldObjC}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_ROOT="${SCRIPT_DIR}/build"
DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData"
SITE_ROOT="${BUILD_ROOT}/site"
BINARY_SITE_PATH="${BINARY_SITE_PATH:-binaries/HelloWorldObjC}"
BINARY_URL_PATH="${BINARY_URL_PATH:-/${BINARY_SITE_PATH}}"
BINARY_ROOT="${SITE_ROOT}/${BINARY_SITE_PATH}"
OUTER_PATH="${SITE_ROOT}/hello-world.outer"

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required tool '$1' was not found on PATH" >&2
        exit 1
    fi
}

require_tool /usr/bin/xcodebuild
require_tool aa
require_tool lipo
require_tool /usr/bin/python3

bundle_executable_name() {
    local bundle_path="$1"
    local info_plist="${bundle_path}/Contents/Info.plist"
    local executable_name=""

    if [[ -f "${info_plist}" && -x /usr/libexec/PlistBuddy ]]; then
        executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${info_plist}" 2>/dev/null || true)"
    fi

    if [[ -z "${executable_name}" ]]; then
        executable_name="$(basename "${bundle_path}" .bundle)"
    fi

    printf '%s\n' "${executable_name}"
}

archive_platform_bundle() {
    local source_bundle="$1"
    local platform="$2"
    local slice_arch="$3"
    local archive_path="${BINARY_ROOT}/${platform}"
    local temp_root
    local temp_bundle
    local executable_name
    local executable_path
    local thinned_executable
    local executable_archs

    temp_root="$(mktemp -d)"
    temp_bundle="${temp_root}/$(basename "${source_bundle}")"
    cp -R "${source_bundle}" "${temp_bundle}"

    executable_name="$(bundle_executable_name "${temp_bundle}")"
    executable_path="${temp_bundle}/Contents/MacOS/${executable_name}"
    executable_archs="$(lipo -archs "${executable_path}")"
    case " ${executable_archs} " in
        *" ${slice_arch} "*) ;;
        *)
            echo "error: ${executable_path} does not contain ${slice_arch} (found: ${executable_archs})" >&2
            rm -rf "${temp_root}"
            exit 1
            ;;
    esac
    if [[ "${executable_archs}" != "${slice_arch}" ]]; then
        thinned_executable="${temp_root}/${executable_name}.${slice_arch}"
        lipo "${executable_path}" -thin "${slice_arch}" -output "${thinned_executable}"
        mv "${thinned_executable}" "${executable_path}"
        chmod +x "${executable_path}"
    fi

    aa archive \
        -d "${temp_root}" \
        -subdir "$(basename "${temp_bundle}")" \
        -o "${archive_path}" \
        -a lzfse

    rm -rf "${temp_root}"
}

rm -rf "${BUILD_ROOT}"
mkdir -p "${BINARY_ROOT}"

XCODEBUILD_ARGS=(
    -project "${PROJECT_FILE}"
    -scheme "${SCHEME_NAME}"
    -configuration "${CONFIGURATION}"
    -derivedDataPath "${DERIVED_DATA_DIR}"
    ARCHS="arm64 x86_64"
    ONLY_ACTIVE_ARCH=NO
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    build
)

echo "==> Building ${SCHEME_NAME}.bundle"
/usr/bin/xcodebuild "${XCODEBUILD_ARGS[@]}"

PRODUCTS_DIR="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}"
BUILT_BUNDLE="${PRODUCTS_DIR}/HelloWorldObjC.bundle"
if [[ ! -d "${BUILT_BUNDLE}" ]]; then
    echo "error: expected bundle at ${BUILT_BUNDLE}" >&2
    exit 1
fi

echo "==> Archiving macOS platform bundles for static hosting"
archive_platform_bundle "${BUILT_BUNDLE}" macos-arm arm64
archive_platform_bundle "${BUILT_BUNDLE}" macos-x86 x86_64

printf 'macos-arm\nmacos-x86\n' > "${BINARY_ROOT}/index.html"

echo "==> Writing hello-world.outer"
/usr/bin/python3 "${SCRIPT_DIR}/Scripts/generate_outer.py" \
    --bundle-url "${BINARY_URL_PATH}" \
    --output "${OUTER_PATH}"

echo "Site ready at ${SITE_ROOT}"
