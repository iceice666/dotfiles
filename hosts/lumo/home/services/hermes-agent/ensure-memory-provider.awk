BEGIN { wrote = 0; skipping = 0 }
/^memory:/ {
  print "memory:"
  print "  provider: \"honcho\""
  wrote = 1
  skipping = 1
  next
}
skipping && /^[^[:space:]]/ { skipping = 0 }
skipping { next }
{ print }
END {
  if (!wrote) {
    print ""
    print "memory:"
    print "  provider: \"honcho\""
  }
}
