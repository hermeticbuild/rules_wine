#!/usr/bin/env bash
# Include roots must work when the generating rule belongs to an external repo.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/rules-wine-tools-external.XXXXXX")
echo "External native tools verification: $scratch"
cd "$root/e2e/tools_caller"
bazel_cmd() { bazel --nosystem_rc --nohome_rc --output_base="$scratch/output" "$@"; }
trap 'bazel_cmd shutdown >/dev/null 2>&1' EXIT
flags=(--lockfile_mode=off --remote_executor= --remote_cache= --disk_cache= --remote_accept_cached=false --symlink_prefix="$scratch/bazel-")
for mode in off strip; do
  bazel_cmd build @native_tools_consumer//:all_outputs "${flags[@]}" \
    --experimental_output_paths="$mode" \
    '--modify_execution_info=WineMessageCompile|WineResourceCompile|WineIdlCompile=+supports-path-mapping' \
    > "$scratch/$mode.log" 2>&1
  execution_root=$(bazel_cmd info execution_root "${flags[@]}" 2>/dev/null)
  output_dir=$(bazel_cmd cquery @native_tools_consumer//:messages.h "${flags[@]}" \
    --output=starlark --starlark:expr='target.files.to_list()[0].dirname' 2>/dev/null)
  bash "$root/e2e/verify_tools.sh" "$execution_root/$output_dir" "$scratch"
done
echo 'PASS: external repository native generation, qualified generated includes/assets, mapping off strip'
