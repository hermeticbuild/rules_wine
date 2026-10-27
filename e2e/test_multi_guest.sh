#!/bin/sh
# Real first-party native Wine and bundled-FEX guests on both Linux executors.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d /tmp/rules-wine-multi-guest.XXXXXX)
printf 'Verification output: %s\n' "$scratch"
cd "$root"
bazel_cmd() {
  bazel --output_base="$scratch/output" "$@"
}
trap 'bazel_cmd shutdown >/dev/null 2>&1' EXIT
case "$*" in
  '') set -- --extra_toolchains=//tests:multi_guest_arm_runner,//tests:multi_guest_arm_adapter ;;
  --default-toolchains) set -- ;;
  *) printf 'usage: %s [--default-toolchains]\n' "$0" >&2; exit 2 ;;
esac
set -- --config=remote --lockfile_mode=off --jobs=80 --symlink_prefix="$scratch/bazel-" --extra_execution_platforms=//platforms:remote_linux_x86_64,//platforms:remote_linux_aarch64 "$@"
bazel_cmd build //tests:arm_bare_x86 //tests:arm_bare_arm //tests:arm_source //tests:arm_explicit_x86 //tests:arm_imported_dll //tests:arm_typed_dll //tests:source_tool "$@" > "$scratch/build.log" 2>&1
bin=$(bazel_cmd info bazel-bin --config=remote --lockfile_mode=off 2>/dev/null)
for target in arm_bare_x86 arm_bare_arm arm_source arm_explicit_x86 arm_imported_dll arm_typed_dll source_tool; do
  cp "$bin/tests/$target.json" "$scratch/$target.json"
  jq -e '.child == "child-ok"' "$scratch/$target.json"
done
bazel_cmd aquery '//tests:arm_bare_x86 + //tests:arm_bare_arm + //tests:arm_source + //tests:arm_explicit_x86 + //tests:arm_typed_dll + //tests:source_tool' "$@" --output=jsonproto > "$scratch/actions.json" 2> "$scratch/actions.log"
jq -e '
  [.actions[] | select(.mnemonic == "WindowsRun") | .executionPlatform] == ["//platforms:remote_linux_aarch64"] and
  ([.actions[] | select(.mnemonic == "Action") | .executionPlatform] | length == 4 and all(. == "//platforms:remote_linux_aarch64")) and
  [.actions[] | select(.mnemonic == "AdapterTool") | .executionPlatform] == ["//platforms:remote_linux_x86_64"]
' "$scratch/actions.json"
printf '%s\n' 'PASS: native ARM64/amd64 source defaults, bare PE guests, FEX amd64 source override and typed/imported DLL adjacency'
