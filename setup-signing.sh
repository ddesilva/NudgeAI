#!/bin/bash
# Create a STABLE self-signed code-signing identity for Nudge AI so that macOS
# remembers Screen Recording permission across rebuilds.
#
# Ad-hoc signatures change every build, so TCC (the permissions system) keeps
# re-prompting. A persistent self-signed cert gives Nudge AI a stable
# code-signing identity (and therefore a stable Designated Requirement), which
# TCC honors.
#
# The cert lives in a dedicated keychain locked with a known throwaway
# password, so this never needs your login/keychain password.
set -euo pipefail

cd "$(dirname "$0")"

CERT_CN="Nudge AI Self-Signed"
KEYCHAIN_NAME="nudgeai-codesign.keychain-db"
KEYCHAIN="$HOME/Library/Keychains/${KEYCHAIN_NAME}"
KCPASS="nudgeai-local-signing"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-certificate -c "$CERT_CN" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "==> Identity '$CERT_CN' already exists. Nothing to do."
    echo "    (delete $KEYCHAIN to recreate it)"
    exit 0
fi

echo "==> Generating self-signed code-signing certificate..."
cat > "$WORK/openssl.cnf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions    = codesign
prompt             = no

[ dn ]
CN = Nudge AI Self-Signed

[ codesign ]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -config "$WORK/openssl.cnf" >/dev/null 2>&1

# OpenSSL 3 defaults to a PKCS#12 MAC that Apple's `security import` cannot
# verify. Force the legacy SHA1 MAC + 3DES PBE and a real password so import
# succeeds across OpenSSL/macOS versions.
P12PASS="nudgeai"
openssl pkcs12 -export -out "$WORK/nudgeai.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$CERT_CN" -passout "pass:${P12PASS}" \
    -legacy -macalg sha1 \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES 2>/dev/null

echo "==> Creating dedicated signing keychain..."
security delete-keychain "$KEYCHAIN_NAME" >/dev/null 2>&1 || true
security create-keychain -p "$KCPASS" "$KEYCHAIN_NAME"
security set-keychain-settings "$KEYCHAIN"          # no auto-lock timeout
security unlock-keychain -p "$KCPASS" "$KEYCHAIN"

# Add to the user's keychain search list so codesign can find the identity.
EXISTING=$(security list-keychains -d user | sed 's/[\" ]//g')
security list-keychains -d user -s $EXISTING "$KEYCHAIN" >/dev/null 2>&1 || \
    security list-keychains -d user -s "$KEYCHAIN" login.keychain-db

echo "==> Importing identity..."
security import "$WORK/nudgeai.p12" -k "$KEYCHAIN" -P "${P12PASS}" -T /usr/bin/codesign -A
# Allow codesign to use the private key without an interactive prompt.
security set-key-partition-list -S apple-tool:,apple: -s -k "$KCPASS" "$KEYCHAIN" >/dev/null 2>&1 || true

# Trust the cert for code signing in the USER domain (no sudo). If this throws
# an auth dialog you can cancel it — signing still works without trust.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" >/dev/null 2>&1 || \
    echo "    (trust step skipped — not required for signing)"

echo "Done. Identity '$CERT_CN' is ready."
echo "Now run: ./build.sh release   (it will sign with this identity)"
