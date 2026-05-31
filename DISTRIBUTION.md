# Distributing Cue (public release)

Cue is a non-sandboxed menu-bar macOS app that needs Screen Recording, so the
right model is **direct download** (a signed + notarized `.dmg`), **not** the Mac
App Store. The `release.sh` script does the whole pipeline in one command.

## Status / what's already done

- ✅ `release.sh` written and tested (build → assemble `Cue.app` → sign w/ hardened
  runtime → package `.dmg` → notarize → staple).
- ⏳ Blocked on: enrolling in the Apple Developer Program (no account yet).

## Step 1 — Enroll in the Apple Developer Program ($99/yr)

1. Go to https://developer.apple.com/programs/enroll and sign in with your Apple
   ID (dilshandesilva80@gmail.com).
2. Enroll as an **Individual** (simplest). Enable two-factor auth first if needed.
3. Approval is usually minutes to ~48 hours.

## Step 2 — One-time setup once approved

```bash
# A) Get your "Developer ID Application" cert:
#    Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#    (or download from developer.apple.com/account/resources/certificates)
security find-identity -v -p codesigning   # confirm it shows up; note the TEAMID

# B) Create an app-specific password at https://appleid.apple.com
#    (Sign-In & Security > App-Specific Passwords), then store a notary profile:
xcrun notarytool store-credentials cue-notary \
  --apple-id "dilshandesilva80@gmail.com" \
  --team-id  "YOURTEAMID" \
  --password "abcd-efgh-ijkl-mnop"
```

## Step 3 — Every release

```bash
DEVELOPER_ID="Developer ID Application: Your Name (YOURTEAMID)" ./release.sh
```

Produces `Cue-<version>.dmg` — signed, notarized, stapled. Runs cleanly on any
Mac with no Gatekeeper warnings.

## Step 4 — Publish

- Upload the `.dmg` to **GitHub Releases** (conventional home for Mac tools).
- Optional later: add a **Homebrew Cask** pointing at the release so users can
  `brew install --cask cue`.

## Notes

- **Dry run before you have the account:**
  `SKIP_NOTARIZE=1 DEVELOPER_ID="..." ./release.sh`
  builds + signs + makes the DMG but skips the Apple round-trip.
- **Bump the version** in `Info.plist` (`CFBundleShortVersionString`) before each
  release — the DMG filename is derived from it.
- **Screen Recording** needs no entitlement under notarization — macOS TCC handles
  the consent prompt at runtime.
- **Local dev scripts untouched:** `build.sh` / `setup-signing.sh` are still for
  fast local iteration; `release.sh` is only for shipping.

## Casual sharing (no Apple account) — `./share.sh`

For sending Cue to a few technical friends right now, without enrolling:

```bash
./share.sh        # -> Cue-<version>.zip
```

It builds a **universal** (arm64 + x86_64) ad-hoc-signed `Cue.app` and zips it
with a `READ-ME-FIRST.txt`. The zip expands to a tidy `Cue-<version>/` folder.

Recipients must clear macOS quarantine once (this is in the read-me too):
- Easiest, any macOS: `xattr -dr com.apple.quarantine /Applications/Cue.app`
- Or: macOS 14 right-click > Open; macOS 15 use System Settings > Privacy &
  Security > "Open Anyway" after the first blocked launch.

This route shows Gatekeeper warnings on first launch (expected for unsigned
apps) and doesn't scale to the public — use the notarized `release.sh` DMG above
for that.

## Optional follow-ups (not yet done)

- (a) Add GitHub Releases publishing to `release.sh` via the `gh` CLI.
- (b) Draft the Homebrew Cask formula.
- (c) Fold this distribution section into README.md.
