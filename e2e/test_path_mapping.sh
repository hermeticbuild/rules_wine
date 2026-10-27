#!/bin/sh
# Exercise the same actions with mapping enabled, disabled and collision fallback.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d /tmp/rules-wine-mapping.XXXXXX)
printf 'Verification output: %s\n' "$scratch"
cd "$root"
bazel_cmd() {
  bazel --output_base="$scratch/output" "$@"
}
trap 'bazel_cmd shutdown >/dev/null 2>&1' EXIT
for mode in strip off; do
  bazel_cmd test //tests:argv_test //tests:mapped_paths //tests:mapping_collision \
    //tests:param_file //tests:distinct_actions //tests:additional_tools \
    --config=remote --lockfile_mode=off --experimental_output_paths="$mode" \
    '--modify_execution_info=WindowsRun|AdapterTool|RunfilesFixture|RunfilesAdapterFixture=+supports-path-mapping' \
    --symlink_prefix="$scratch/bazel-" > "$scratch/$mode.log" 2>&1
  bin=$(bazel_cmd info bazel-bin --config=remote --lockfile_mode=off 2>/dev/null)
  cp "$bin/tests/mapped_paths/result café {output}.json" "$scratch/$mode.json"
  cp "$bin/tests/mapping_collision/result café {output}.json" "$scratch/$mode-collision.json"
  jq -e --arg mode "$mode" '
    .child == "child-ok" and
    .env.FIXTURE_VALUE == "space café\nquote\"backslash\\" and
    .args[2] == "first" and
    (.args[1] | endswith("\\tests\\mapped_paths\\result café {output}.json")) and
    ((.args[1] | contains("\\bazel-out\\cfg\\")) == ($mode == "strip")) and
    ((.args[3] | startswith("bazel-out/cfg/")) == ($mode == "strip")) and
    (.args[3] | endswith("/tests/mapping_input/data café {input}.txt"))
  ' "$scratch/$mode.json" >/dev/null
  jq -e '
    .child == "child-ok" and .args[2:4] == ["first", "second"] and
    (.args[1] | contains("\\bazel-out\\cfg\\") | not) and
    (.args[4] | contains("bazel-out/cfg/") | not) and
    (.args[4] | split("\n") | length) == 2
  ' "$scratch/$mode-collision.json" >/dev/null
  jq -e '.args[-1] == "response one\ncafé" and .env.FIXTURE_VALUE == "opaque/unchanged"' \
    "$bin/tests/param_file.json" >/dev/null
  for name in Aa BB; do
    jq -e --arg name "$name" '.args[-1] == $name and .env.FIXTURE_VALUE == $name' \
      "$bin/tests/distinct_actions/$name" >/dev/null
  done
done
bazel_cmd aquery '//tests:mapped_paths + //tests:mapping_collision' \
  --config=remote --lockfile_mode=off --include_param_files --output=jsonproto \
  > "$scratch/actions.json" 2> "$scratch/actions.log"
# aquery expands Starlark Args inline, even when execution uses parameter files.
jq -e '
  (.actions | length) == 2 and
  all(.actions[]; .mnemonic == "WindowsRun" and
    .arguments[1] == "--config" and
    (.arguments[2] | fromjson | .supported_guest_cpus == ["x86_64"]))
' "$scratch/actions.json" >/dev/null
printf '%s\n' 'PASS: mapped/unmapped Wine actions, adapters, runfiles, generated payload/data, parameter files and collision fallback'
