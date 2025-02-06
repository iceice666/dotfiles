printcat()
{
  echo "Here is your cat.     "
  echo " "
  echo "            A____A    "
  echo "           /*    *\   "
  echo "          {   _  _ }  "
  echo "          A\` >  v /< "
  echo "        / !!!!! !!}   "
  echo "       / ! \!!!!! |   "
  echo "  ____{   ) |  |  |   "
  echo " / ___{ !!c |  |  |   "
  echo "{ (___ \__\__@@_)@_)  "
  echo " \____)               "
  echo "Paradise is no longer paradise if there is no cat."
}

printdog(){
  echo "no dog"
}

mcd  ()
{
  mkdir -p "$1"
  cd "$1" || return
}

urlencode()
{
    if [ -z "$1" ]; then
        python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read().strip()))'
    else
        python3 -c "import urllib.parse as ul; print(ul.quote_plus(\"'$1'\"))"
    fi
}

urldecode()
{
    if [ -z "$1" ]; then
        python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read().strip()))'
    else
        python3 -c "import urllib.parse as ul; print(ul.unquote_plus(\"'$1'\"))"
    fi
}
