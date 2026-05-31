#!/bin/bash
# Build, Developer-ID sign, notarize, staple, and package Cue into a
# distributable .dmg for public download.
#
# PREREQUISITES (one-time, after you enroll in the Apple Developer Program):
#   1. Install your "Developer ID Application" certificate (Xcode ▸ Settings ▸
#      Accounts ▸ Manage Certificates ▸ +, or download from developer.apple.com).
#      Confirm it's there:   security find-identity -v -p codesigning
#   2. Store a notarytool credential profile once (uses an app-specific password
#      from appleid.apple.com, NOT your Apple ID password):
#        xcrun notarytool store-credentials cue-notary \
#          --apple-id "you@example.com" \
#          --team-id  "YOURTEAMID" \
#          --password "abcd-efgh-ijkl-mnop"
#
# USAGE:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" ./release.sh
#
# Optional env vars:
#   NOTARY_PROFILE   notarytool keychain profile name   (default: cue-notary)
#   SKIP_NOTARIZE=1  build + sign only, skip notarization (for dry runs)
set -euo pipefail

cd "$(dirname "$0")"

APP="Cue.app"
BUNDLE_EXEC="Cue"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
DMG="Cue-${VERSION}.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-cue-notary}"

if [[ -z "${DEVELOPER_ID:-}" ]]; then
    echo "Error: set DEVELOPER_ID to your Developer ID Application identity." >&2
    echo "  List identities with: security find-identity -v -p codesigning" >&2
    echo "  Example:" >&2
    echo "    DEVELOPER_ID=\"Developer ID Application: Jane Doe (AB12CD34EF)\" ./release.sh" >&2
    exit 1
fi

# --- Build -----------------------------------------------------------------
echo "==> Building release..."
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/${BUNDLE_EXEC}"
[[ -f "${BIN_PATH}" ]] || { echo "Error: executable not found at ${BIN_PATH}" >&2; exit 1; }

# --- Assemble .app ---------------------------------------------------------
echo "==> Assembling ${APP} (v${VERSION})..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BUNDLE_EXEC}"
cp Info.plist "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# --- Sign with hardened runtime (required for notarization) ----------------
echo "==> Code signing with Developer ID + hardened runtime..."
codesign --force --options runtime --timestamp \
    --sign "${DEVELOPER_ID}" "${APP}"
codesign --verify --strict --verbose=2 "${APP}"

# --- Package into a .dmg ----------------------------------------------------
echo "==> Building ${DMG}..."
rm -f "${DMG}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"   # drag-to-install affordance
hdiutil create -volname "Cue" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}" >/dev/null

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    echo "Done (signed, NOT notarized): ${DMG}"
    echo "Set SKIP_NOTARIZE=0 (or unset) to notarize before public release."
    exit 0
fi

# --- Notarize + staple ------------------------------------------------------
echo "==> Submitting ${DMG} to Apple notary service (this can take a few minutes)..."
xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"

echo
echo "Done: ${DMG} is signed, notarized, and stapled — ready to publish."
echo "Verify on a clean machine with:  spctl -a -t open --context context:primary-signature -vv ${DMG}"
