#!/bin/sh
# Default Wine/FEX must run an amd64 PE and its child on native ARM64 workers.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d /tmp/rules-wine-translation.XXXXXX)
printf 'Verification output: %s\n' "$scratch"
cd "$root"
bazel_cmd() {
  bazel --output_base="$scratch/output" "$@"
}
trap 'bazel_cmd shutdown >/dev/null 2>&1' EXIT
set -- --config=remote --lockfile_mode=off \
  --extra_execution_platforms=//platforms:remote_linux_x86_64,//platforms:remote_linux_aarch64 \
  --symlink_prefix="$scratch/bazel-"
bazel_cmd test //tests:cpu_translation_test \
  //tests:translated_action //tests:translated_adapter \
  "$@" > "$scratch/test.log" 2>&1
bin=$(bazel_cmd info bazel-bin "$@" 2>/dev/null)
for name in translated_action translated_adapter; do
  cp "$bin/tests/$name.json" "$scratch/$name.json"
  jq -e '.child == "child-ok"' "$scratch/$name.json" >/dev/null
done
bazel_cmd aquery 'mnemonic("WindowsRun|AdapterTool", //tests:translated_action + //tests:translated_adapter)' \
  "$@" --output=jsonproto > "$scratch/actions.json" 2> "$scratch/actions.log"
jq -e '
  (.actions | length) == 2 and
  all(.actions[]; .executionPlatform == "//platforms:remote_linux_aarch64")
' "$scratch/actions.json" >/dev/null
# Inspect the PE itself, independently of Bazel platform labels.
file tests/fixture/fixture_x86_64.exe > "$scratch/payload.txt"
grep -q 'PE32+ executable.*x86-64' "$scratch/payload.txt"
printf '%s\n' 'PASS: default Wine/FEX runs amd64 payloads and children on ARM64 through both APIs'
