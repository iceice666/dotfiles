/^model:/ {
  print
  print "  api_key: \"" key "\""
  inmodel = 1
  next
}
inmodel && /^  api_key:/ { next }
inmodel && /^[a-zA-Z_]/ { inmodel = 0 }
{ print }
