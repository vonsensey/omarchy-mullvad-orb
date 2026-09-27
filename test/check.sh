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

jq -e 'length > 200 and all(.[]; (.r | length) > 0)' assets/countries.json >/dev/null \
  && echo "assets: countries.json ok" || { echo "FAIL: assets/countries.json"; fail=1; }

exit $fail
