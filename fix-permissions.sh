#!/bin/bash
# One-shot fix for "macOS keeps asking for Screen Recording permission".
#
# Root cause: an ad-hoc code signature changes its hash on every build, and
# macOS TCC ties the Screen Recording grant to that hash (the app's Designated
# Requirement). So every rebuild looks like a brand-new app and re-prompts.
#
# This script:
#   1. Creates a STABLE self-signed signing identity (once), so the app keeps
#      the same Designated Requirement across rebuilds.
#   2. Rebuilds NudgeAI.app and signs it with that identity.
#   3. Resets the stale Screen Recording grant so you get ONE clean prompt.
#   4. Relaunches the app.
#
# After running this once and granting permission, future ./build.sh runs reuse
# the same identity and the grant sticks.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> [1/4] Ensuring stable signing identity..."
./setup-signing.sh

KC="$HOME/Library/Keychains/nudgeai-codesign.keychain-db"
security unlock-keychain -p "nudgeai-local-signing" "$KC" 2>/dev/null || true

echo "==> [2/4] Rebuilding and signing NudgeAI.app..."
pkill -f "NudgeAI.app/Contents/MacOS/NudgeAI" 2>/dev/null || true
sleep 1
./build.sh release

echo "==> Verifying signature is NOT ad-hoc..."
if codesign -dvv NudgeAI.app 2>&1 | grep -q "Signature=adhoc"; then
    echo "    WARNING: still ad-hoc. The identity may need keychain approval."
    echo "    If a dialog appeared asking to use key 'Nudge AI Self-Signed', click"
    echo "    'Always Allow', then re-run this script."
else
    echo "    OK: signed with stable identity."
    codesign -dvv NudgeAI.app 2>&1 | grep -E "Authority|Signature" | sed 's/^/    /'
fi

echo "==> [3/4] Resetting stale Screen Recording grant..."
tccutil reset ScreenCapture com.dilshan.nudgeai 2>/dev/null || true

echo "==> [4/4] Launching Nudge AI..."
open NudgeAI.app

cat <<'EOF'

Done. Now:
  1. Click the Nudge AI menu-bar icon -> Start Nudge Session.
  2. When macOS prompts for Screen Recording, enable Nudge AI and (if asked) reopen it.
From now on, rebuilds keep the same identity, so the permission will persist.
EOF
