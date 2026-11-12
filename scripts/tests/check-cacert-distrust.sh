#!/usr/bin/env bash
# Fail if a CA bundle contains any of the four distrusted eMudhra/Comodo roots.
# Run from dotfiles-cacert's postInstall so an upstream reintroduction fails
# the build. Usage: check-cacert-distrust.sh <bundle.crt>
set -euo pipefail

bundle="$1"
blocked=(
  'd7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4'
  '86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b'
  '125609aa301da0a249b97a8239cb6a34216f44dcac9f3954b14292f2e8c8608f'
  'bc4d809b15189d78db3e1d8cf4f9726a795da1643ca5f1358e1ddb0edc0d7eb3'
)

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

awk -v dir="$work" '
  /-----BEGIN CERTIFICATE-----/ { n++; file = sprintf("%s/%05d.pem", dir, n) }
  file { print > file }
  /-----END CERTIFICATE-----/ { close(file); file = "" }
' "$bundle"

count=0
for pem in "$work"/*.pem; do
  [ -e "$pem" ] || continue
  count=$((count + 1))
  fingerprint="$(openssl x509 -noout -fingerprint -sha256 -in "$pem" | cut -d= -f2 | tr -d : | tr 'A-F' 'a-f')"
  for entry in "${blocked[@]}"; do
    if [ "$fingerprint" = "$entry" ]; then
      echo "blocked trust anchor in $bundle: $(openssl x509 -noout -subject -in "$pem")" >&2
      exit 1
    fi
  done
done

if [ "$count" -eq 0 ]; then
  echo "CA bundle contains no certificates: $bundle" >&2
  exit 1
fi
echo "CA bundle excludes all ${#blocked[@]} blocked root fingerprints ($count certificates checked)"
