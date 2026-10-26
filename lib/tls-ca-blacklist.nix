# CVE-2026-111943: compromised eMudhra intermediates and their cross-signs.
# Names are NSS labels, not necessarily certificate subject common names.
#
# NSS 3.131.1 (nixpkgs cacert) already dropped the three emSign roots, and
# cacert's blacklist is strict: listing a label that is no longer in the store
# fails the build. Only the Comodo cross-sign anchor still needs local removal.
# Pi's trust.test.cjs keeps asserting all four fingerprints are absent from the
# built bundle, so an upstream reintroduction would still fail closed.
[
  "Comodo AAA Services root"
]
