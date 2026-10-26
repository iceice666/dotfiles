# CVE-2026-111943: compromised eMudhra intermediates and their cross-signs.
# Names are NSS labels, not necessarily certificate subject common names.
#
# cacert's blacklist is strict: a label that is no longer in the NSS store
# fails the build. NSS 3.131.1 dropped the three emSign roots upstream, so
# they are only listed for older bundles (nixos-26.05 still ships 3.126).
# Pi's trust.test.cjs asserts all four fingerprints are absent from the built
# bundle regardless, so an upstream reintroduction still fails closed.
cacertVersion:
[ "Comodo AAA Services root" ]
++ (
  if builtins.compareVersions cacertVersion "3.131" < 0 then
    [
      "emSign ECC Root CA - G3"
      "emSign Root CA - C1"
      "emSign ECC Root CA - C3"
    ]
  else
    [ ]
)
