#!/bin/bash
# Generate the Xcode project, build Debug, then sign with a stable certificate.
# A stable signature keeps the Screen Recording permission across rebuilds.
# Set GLIMPSE_SIGN_ID when the keychain holds more than one "Apple Development" identity.
# The last stdout line is the app path.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="${GLIMPSE_SIGN_ID:-Apple Development}"

xcodegen generate --quiet
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet build

APP="build/Build/Products/Debug/Glimpse.app"

# A revoked or expired certificate makes macOS flag the app as malware and offer to trash it.
# The keychain may hold a renewed certificate next to an old one with the same name, so pick by SHA-1:
# take the identities `find-identity -v` lists whose name matches SIGN_ID, OCSP-check each, and sign with
# the first one that is not revoked or expired. Being offline is not a verdict, so it keeps the cert.
# Command output is captured into variables (not piped into grep -q) because of pipefail.
if [ "$SIGN_ID" != "-" ]; then
  IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  ALL_CERTS="$(security find-certificate -a -Z -p 2>/dev/null || true)"
  CERT_PEM="$(mktemp)"
  trap 'rm -f "$CERT_PEM"' EXIT
  CHOSEN=""
  FOUND_ANY=0
  while read -r HASH; do
    [ -n "$HASH" ] || continue
    FOUND_ANY=1
    # Export the certificate with this hash from the `-Z -p` listing (each PEM follows its hash line).
    awk -v h="$HASH" '/^SHA-1 hash:/ { on = ($3 == h) } on && /-----BEGIN CERTIFICATE-----/ { pem = 1 } pem && on { print } /-----END CERTIFICATE-----/ { pem = 0 }' \
      <<< "$ALL_CERTS" > "$CERT_PEM"
    [ -s "$CERT_PEM" ] || continue
    # verify-cert exits non-zero on a bad cert; capture first so pipefail cannot hide the verdict.
    VERIFY_OUT="$(security verify-cert -c "$CERT_PEM" -p codeSign -R ocsp 2>&1 || true)"
    if [[ "$VERIFY_OUT" =~ REVOKED|EXPIRED ]]; then
      echo "warning: certificate $HASH (\"$SIGN_ID\") is revoked or expired; skipping" >&2
      continue
    fi
    CHOSEN="$HASH"
    break
  done < <(awk -v name="$SIGN_ID" 'index($0, name) { print $2 }' <<< "$IDENTITIES")
  if [ -n "$CHOSEN" ]; then
    SIGN_ID="$CHOSEN"
  else
    if [ "$FOUND_ANY" = 0 ]; then
      echo "warning: no identity matching \"$SIGN_ID\"; signing ad-hoc (Screen Recording must be re-granted after each build)" >&2
    else
      echo "warning: no valid certificate for \"$SIGN_ID\"; signing ad-hoc (Screen Recording must be re-granted after each build)." >&2
      echo "warning: fix: Xcode → Settings → Accounts → sign in → Manage Certificates → + Apple Development" >&2
    fi
    SIGN_ID="-"
  fi
fi

# No --deep: there are no nested bundles (GlimpseCore is linked statically).
codesign --force --options runtime --timestamp=none --sign "$SIGN_ID" "$APP"
echo "$APP"
