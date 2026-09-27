#!/usr/bin/env bash
# Mullvad Orb checks: model unit tests, QML parse, manifest validation.
# Each step runs when its tool is present and says so when it is skipped.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

if command -v node >/dev/null; then
  node --test test/ || fail=1
else
  echo "skip: node not installed (model tests)"
fi

qmlformat=/usr/lib/qt6/bin/qmlformat
if [[ -x $qmlformat ]]; then
  for f in *.qml; do
    "$qmlformat" "$f" >/dev/null 2>&1 || { echo "FAIL: $f does not parse"; fail=1; }
  done
  echo "qml: $(ls *.qml | wc -l) files parse"
else
  echo "skip: qt6 qmlformat not found (QML parse)"
fi

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$PWD" >/dev/null && echo "manifest: valid" || { echo "FAIL: omarchy plugin validate"; fail=1; }
else
  echo "skip: omarchy not installed (manifest validation)"
fi

# Secrets never go on a command line (readable by any local process): the
# account number reaches login and wl-copy on stdin, vouchers not at all.
if grep -nE 'account\.number|voucher' Service.qml | grep -E 'command|execDetached|\["' ; then
  echo "FAIL: a secret is passed as a command argument"; fail=1
elif grep -nE '"redeem"' *.qml; then
  echo "FAIL: voucher redeem puts the code in argv"; fail=1
else
  echo "secrets: none passed as command arguments"
fi

jq -e 'length > 200 and all(.[]; (.r | length) > 0)' assets/countries.json >/dev/null \
  && echo "assets: countries.json ok" || { echo "FAIL: assets/countries.json"; fail=1; }

exit $fail
