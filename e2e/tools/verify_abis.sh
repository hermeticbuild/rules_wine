#!/usr/bin/env bash
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo >&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
set -euo pipefail
x86_64=$(rlocation "$1")
aarch64=$(rlocation "$2")
if cmp -s "$x86_64/example_p.c" "$aarch64/example_p.c"; then
  echo 'COM proxy outputs did not select different Windows ABIs' >&2
  exit 1
fi
if cmp -s "$x86_64/rpc_c.c" "$aarch64/rpc_c.c"; then
  echo 'RPC client outputs did not select different Windows ABIs' >&2
  exit 1
fi
