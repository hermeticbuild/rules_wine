#!/usr/bin/env bash
# The adapter's executor may differ from the run_binary action's executor.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/rules-wine-tools-selection.XXXXXX")
echo "Native executable selection verification: $scratch"
cd "$root/e2e/tools"
bazel_cmd() { bazel --nosystem_rc --nohome_rc --output_base="$scratch/output" "$@"; }
trap 'bazel_cmd shutdown >/dev/null 2>&1' EXIT
for executor in selection_b selection_arm; do
  bazel_cmd aquery 'deps(//:selection)' --lockfile_mode=off --output=jsonproto \
    --platforms=@rules_wine//platforms:windows_aarch64 \
    --extra_execution_platforms="//:$executor,//:selection_a" \
    --extra_toolchains=//:selection_registration_a,//:selection_registration_b \
    > "$scratch/$executor.json" 2> "$scratch/$executor.log"
  jq -e --arg executor "$executor" '
    any(.actions[]; .mnemonic == "RunBinary" and (.executionPlatform | endswith("//:selection_a"))) and
    any(.actions[]; (.arguments | index("_main/messages.mc")) != null and
      (.executionPlatform | endswith("//:" + $executor))) and
    all(.actions[]; (.arguments | index("_main/unicode.rc")) == null)
  ' "$scratch/$executor.json" >/dev/null
done
echo 'PASS: target-selected executable honors consumer executor CPU and custom worker constraints'
