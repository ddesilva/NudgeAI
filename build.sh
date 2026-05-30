#!/bin/bash
# Build Cue and assemble a runnable Cue.app bundle (no full Xcode required).
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="Cue.app"
BUNDLE_EXEC="Cue"

echo "==> Building (${CONFIG})..."
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${BUNDLE_EXEC}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "Error: executable not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "==> Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BUNDLE_EXEC}"
cp Info.plist "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# Prefer the stable self-signed identity (so macOS remembers Screen Recording
# permission across rebuilds). Fall back to ad-hoc if it isn't set up yet.
SIGN_ID="Cue Self-Signed"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "${SIGN_ID}"; then
    echo "==> Code signing with stable identity '${SIGN_ID}'..."
    codesign --force --deep --sign "${SIGN_ID}" "${APP}"
else
    echo "==> No stable identity found - run ./setup-signing.sh to stop repeated"
    echo "    permission prompts. Falling back to ad-hoc signing for now..."
    codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || \
        echo "    (codesign skipped/failed - app may still run)"
fi

echo "Done: built ${APP}"
echo
echo "Run it with:  open ${APP}"
echo "First run: grant Screen Recording in System Settings > Privacy & Security > Screen Recording."
