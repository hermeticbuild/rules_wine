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
guest=$1
pe=$(rlocation "$2")
mapping=$3
backend=$4
host_cpu=$5
shift 5
offset=$(od -An -tu4 -j60 -N4 "$pe" | tr -d ' \n')
machine=$(od -An -tx2 -j"$((offset + 4))" -N2 "$pe" | tr -d ' \n')
case "$guest" in x86_64) [[ $machine == 8664 ]] ;; aarch64) [[ $machine == aa64 ]] ;; esac
if [[ -n ${RULES_WINE_EXPECTED_CPU:-} ]]; then
  [[ $host_cpu == "$RULES_WINE_EXPECTED_CPU" ]]
fi
if [[ $backend != windows ]]; then
  case "$(uname -m)" in arm64|aarch64) [[ $host_cpu == aarch64 ]] ;; x86_64) [[ $host_cpu == x86_64 ]] ;; *) exit 1 ;; esac
fi
for output in "$@"; do
  IFS= read -r record < "$(rlocation "$output")"
  [[ $record == *'"child":"child-ok"'* ]]
  [[ $record == *'"FIXTURE_VALUE":"environment café"'* ]]
  [[ $record == *',"space value","","café","$literal","declared input café"]'* ]]
  if [[ $mapping == strip ]]; then
    [[ $record == *'bazel-out\\cfg\\'* ]]
  else
    [[ $record != *'bazel-out\\cfg\\'* ]]
  fi
  if [[ $backend == windows ]]; then
    [[ $record == *'"WINEPREFIX":""'* ]]
  else
    [[ $record != *'"WINEPREFIX":""'* ]]
  fi
  printf 'PASS: %s\n' "$output"
done
