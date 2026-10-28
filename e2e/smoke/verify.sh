#!/usr/bin/env bash
# The Windows fixture emits one JSON line; verify its observable contract.
# --- begin runfiles.bash initialization v3 ---
# Standard initialization also supports Windows manifest-only runfiles.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo >&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---
set -euo pipefail
for output in "$@"; do
  IFS= read -r record < "$(rlocation "$output")"
  [[ $record == *'"child":"child-ok"'* ]]
  [[ $record == *'"FIXTURE_VALUE":"environment café"'* ]]
  [[ $record == *',"space value","","café","$literal","declared input café"]'* ]]
  printf 'PASS: %s\n' "$output"
done
