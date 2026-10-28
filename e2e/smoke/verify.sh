#!/usr/bin/env bash
# The Windows fixture emits one JSON line; verify its observable contract.
set -euo pipefail
for output in "$@"; do
  IFS= read -r record < "$(rlocation "$output")"
  [[ $record == *'"child":"child-ok"'* ]]
  [[ $record == *'"FIXTURE_VALUE":"environment café"'* ]]
  [[ $record == *',"space value","","café","$literal","declared input café"]'* ]]
  printf 'PASS: %s\n' "$output"
done
