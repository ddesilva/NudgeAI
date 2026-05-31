#!/bin/bash
# Build a UNIVERSAL (Apple Silicon + Intel) Cue.app, ad-hoc sign it, and zip it
# up for casual sharing with others — no Apple Developer account needed.
#
# This is the "send it to a few technical friends" route. Recipients must clear
# the macOS quarantine flag once (instructions are written into the zip). For a
# clean public release with no warnings, use ./release.sh instead.
#
# USAGE:  ./share.sh
set -euo pipefail

cd "$(dirname "$0")"

APP="Cue.app"
BUNDLE_EXEC="Cue"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ZIP="Cue-${VERSION}.zip"

# --- Build a universal binary (arm64 + x86_64) -----------------------------
# Passing both arches to one `swift build` needs full Xcode, so instead build
# each arch separately (works with Command Line Tools) and lipo them together.
BIN_PATH="$(mktemp -d)/${BUNDLE_EXEC}"
ARCH_BINS=()
for ARCH in arm64 x86_64; do
    echo "==> Building release for ${ARCH}..."
    swift build -c release --arch "${ARCH}"
    A="$(swift build -c release --arch "${ARCH}" --show-bin-path)/${BUNDLE_EXEC}"
    [[ -f "${A}" ]] || { echo "Error: ${ARCH} executable not found at ${A}" >&2; exit 1; }
    ARCH_BINS+=("${A}")
done
echo "==> Merging into a universal binary..."
lipo -create -output "${BIN_PATH}" "${ARCH_BINS[@]}"
echo "    arch(s): $(lipo -archs "${BIN_PATH}")"

# --- Assemble .app ---------------------------------------------------------
echo "==> Assembling ${APP} (v${VERSION})..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BUNDLE_EXEC}"
cp Info.plist "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# --- Ad-hoc sign (no identity required) ------------------------------------
echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "${APP}"

# --- Stage app + read-me, then zip -----------------------------------------
echo "==> Packaging ${ZIP}..."
PKGDIR="${STAGE}/Cue-${VERSION}"          # zip expands to one tidy folder
mkdir -p "${PKGDIR}"
cp -R "${APP}" "${PKGDIR}/"
cat > "${PKGDIR}/READ-ME-FIRST.txt" <<'EOF'
Cue — first launch on your Mac
==============================

Cue is shared unsigned, so macOS will block the first launch with a warning
like "Cue is damaged" or "can't verify the developer." That's expected. Clear
it once with EITHER method below, then it opens normally forever after.

1) Drag Cue.app into your Applications folder.

2a) Easiest (any macOS) — open Terminal and run:

       xattr -dr com.apple.quarantine /Applications/Cue.app

    then double-click Cue in Applications.

2b) Or without Terminal:
    - macOS 14 (Sonoma) and earlier: right-click Cue.app > Open > Open.
    - macOS 15 (Sequoia) and later: double-click it once (it gets blocked),
      then go to System Settings > Privacy & Security, scroll down, and click
      "Open Anyway".

3) Cue lives in the menu bar (no Dock icon). On your first screen capture it
   will ask for Screen Recording permission:
   System Settings > Privacy & Security > Screen Recording > enable Cue,
   then quit and reopen Cue.

That's it. Enjoy!
EOF

rm -f "${ZIP}"
# ditto preserves the bundle + ad-hoc signature correctly inside the zip.
# (No --sequesterRsrc, so no stray __MACOSX/._ files.)
ditto -c -k --keepParent "${PKGDIR}" "${ZIP}"

echo
echo "Done: ${ZIP}  (universal, ad-hoc signed, ready to send)"
echo "It contains Cue.app + READ-ME-FIRST.txt with unquarantine instructions."
