#!/bin/sh
# Analysis/configuration regression checks; no execution of synthetic payloads.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
rules=${1:-$root}
scratch=$(mktemp -d /tmp/rules-wine-starlark.XXXXXX)
cp -R "$root/e2e/starlark/." "$scratch/"
cp "$root/.bazelversion" "$scratch/.bazelversion"
printf 'module(name = "wine_audit")\nbazel_dep(name = "rules_wine", version = "0.1.0")\nlocal_path_override(module_name = "rules_wine", path = "%s")\nbazel_dep(name = "platforms", version = "1.1.0")\n' "$rules" > "$scratch/MODULE.bazel"
printf 'bazel_dep(name = "rules_cc", version = "0.2.18")\n' >> "$scratch/MODULE.bazel"
printf 'bazel_dep(name = "caller", version = "0.1.0")\nlocal_path_override(module_name = "caller", path = "caller")\n' >> "$scratch/MODULE.bazel"
printf 'import %s/.bazelrc\n' "$rules" > "$scratch/.bazelrc"
printf 'Verification workspace: %s\n' "$scratch"
cd "$scratch"
trap 'bazel shutdown >/dev/null 2>&1' EXIT
query() {
  bazel aquery "$1" --config=remote --extra_execution_platforms=//:audit_exec --extra_toolchains="$2" --lockfile_mode=off --include_param_files > "$scratch/$3"
}
query 'deps(//:collision)' '//:runner' actions.txt
grep -q 'launcher_data' actions.txt
query '//:collision' '//:generated_runner' generated.txt
grep -Eq 'bazel-out/[^ /]*-opt-exec[^ /]*/bin/built_loader.sh' generated.txt
query 'deps(//:collision)' '//:sidecar_runner' sidecar.txt
grep -q 'sidecar_launcher.json' sidecar.txt
grep -q 'launcher_data' sidecar.txt
bazel aquery '//:collision' --config=remote --extra_execution_platforms=//:audit_windows --extra_toolchains=//:native_runner --lockfile_mode=off > native.txt
if grep -Eq 'wine.json|launcher_data|supervisor' native.txt; then
  printf '%s\n' 'native action acquired a launcher or Wine configuration' >&2
  exit 1
fi
bazel aquery //:native_declared_x86 --config=remote --extra_execution_platforms=//:audit_windows --extra_toolchains=//:native_runner --output=jsonproto > native-typed.json
jq -e 'all(.actions[]; .mnemonic != "WindowsRun" or (.arguments[0] | endswith("payload_with_data.sh"))) and ([.actions[].environmentVariables[]?.key | select(. == "FIXTURE_VALUE")] | length) == 0' native-typed.json
if bazel aquery //:native_declared_arm --config=remote --extra_execution_platforms=//:audit_windows --extra_toolchains=//:native_runner > native-arm.txt 2> native-arm.log; then
  printf '%s\n' 'expected declared mismatch on native Windows' >&2
  exit 1
fi
grep -q 'declares aarch64; runtime native Windows supports' native-arm.log
bazel build //:data_adapter //:apparent_platform @caller//:mapped --config=remote --jobs=80 --lockfile_mode=off --platforms=//:audit_exec --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter
jq -e '.runfiles == true and .supported_guest_cpus == ["x86_64"] and .declared_guest_cpu == null and .args == null and .env == null' bazel-bin/data_adapter.json
grep -q 'launcher_data' bazel-bin/data_adapter.runfiles_manifest
grep -q 'alias.txt.*only_via_alias' bazel-bin/data_adapter.runfiles_manifest
bazel cquery //:data_adapter --config=remote --platforms=//:audit_exec --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter --lockfile_mode=off --output=starlark --starlark:expr='providers(target)["RunEnvironmentInfo"].environment' > environment.txt
grep -q 'binary-owned environment' environment.txt
bazel aquery 'deps(//:data_adapter)' --config=remote --platforms=//:audit_exec --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter > adapter.txt
grep -q 'finalize' adapter.txt
for target in wrong_platform declared_arm; do
  if bazel aquery "//:$target" --config=remote --platforms=//:audit_exec --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter > "$target.txt" 2> "$target.log"; then
    printf 'expected analysis failure: %s\n' "$target" >&2
    exit 1
  fi
  grep -Eq 'target_platform must be Windows|payload .* declares aarch64; runtime .* supports' "$target.log"
done
# The same rule selects either CPU from its target platform. Only inspect the
# ARM64 graph: the synthetic runtime and execution platform cannot run programs.
for platform in audit_exec audit_arm64; do
  bazel aquery 'mnemonic("FileWrite", //:data_adapter)' --config=remote --lockfile_mode=off --platforms="//:$platform" --extra_execution_platforms=//:audit_exec,//:audit_arm64 --extra_toolchains=//:adapter,//:adapter_arm64 --include_file_write_contents --output=jsonproto > "$platform.json"
done
jq -e '[.actions[] | (.fileContents | fromjson).supported_guest_cpus] == [["x86_64"]]' audit_exec.json
jq -e '[.actions[] | (.fileContents | fromjson).supported_guest_cpus] == [["aarch64"]]' audit_arm64.json
jq -e '[.actions[].executionPlatform] == ["//:audit_exec"]' audit_exec.json
jq -e '[.actions[].executionPlatform] == ["//:audit_arm64"]' audit_arm64.json
for target in declared_x86 fixed_x86; do
  if bazel aquery "//:$target" --config=remote --lockfile_mode=off --platforms=//:audit_arm64 --extra_execution_platforms=//:audit_exec,//:audit_arm64 --extra_toolchains=//:adapter,//:adapter_arm64 > "$target-arm64.txt" 2> "$target-arm64.log"; then
    printf 'expected ARM64 incompatibility: %s\n' "$target" >&2
    exit 1
  fi
done
grep -q 'declares x86_64; runtime .* supports' declared_x86-arm64.log
grep -q 'incompatible' fixed_x86-arm64.log
bazel aquery '//:apparent_platform + //:wrong_cpu' --config=remote --lockfile_mode=off --platforms=//:audit_arm64 --extra_execution_platforms=//:audit_exec,//:audit_arm64 --extra_toolchains=//:adapter,//:adapter_arm64 > undeclared.txt
# Metadata imports preserve original executable ownership, runfiles and env.
bazel build //:imported_adapter --config=remote --lockfile_mode=off --platforms=//:audit_exec --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter
jq -e '.declared_guest_cpu == "x86_64" and (.payload | endswith("payload_with_data.sh"))' bazel-bin/imported_adapter.json
grep -q 'alias.txt.*only_via_alias' bazel-bin/imported_adapter.runfiles_manifest
grep -q 'companion_data' bazel-bin/imported_adapter.runfiles_manifest
bazel cquery //:imported_adapter --config=remote --platforms=//:audit_exec --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter --output=starlark --starlark:expr='providers(target)["RunEnvironmentInfo"].environment' > imported-env.txt
grep -q 'binary-owned environment' imported-env.txt
# One rule uses different CPUs/backends on its two execution groups. Its target
# platform must not steer either group, and paths must follow their own backend.
for platform in audit_exec audit_arm64; do
  bazel aquery //:grouped_actions --config=remote --lockfile_mode=off --platforms="//:$platform" --extra_execution_platforms=//:audit_arm64,//:audit_windows --extra_toolchains=//:runner_arm64,//:native_runner --include_param_files --output=jsonproto > "groups-$platform.json"
  jq -e '
    [.actions[] | select(.mnemonic == "WineFixture")] as $wine |
    [.actions[] | select(.mnemonic == "NativeFixture")] as $native |
    [$wine[].executionPlatform] == ["//:audit_arm64"] and
    [$native[].executionPlatform] == ["//:audit_windows"] and
    ([$wine[].arguments[] | contains("{windows_path:")] | any) and
    ([$native[].arguments[] | contains("{windows_path:")] | any | not) and
    [$wine[].arguments[2] | fromjson | .supported_guest_cpus] == [["aarch64"]] and
    ([$native[].arguments[] | select(. == "--config")] | length) == 0
  ' "groups-$platform.json"
done
# Fixed-x86 payloads constrain execution, even when the final target is ARM64.
bazel aquery //:fixed_action --config=remote --lockfile_mode=off --platforms=//:audit_arm64 --extra_execution_platforms=//:audit_arm64,//:audit_exec --extra_toolchains=//:runner_arm64,//:runner --output=jsonproto > fixed-action.json
jq -e '[.actions[] | select(.mnemonic == "WindowsRun").executionPlatform] == ["//:audit_exec", "//:audit_exec"]' fixed-action.json
if bazel aquery //:fixed_action --config=remote --lockfile_mode=off --extra_execution_platforms=//:audit_arm64 --extra_toolchains=//:runner_arm64 > fixed-action-arm64.txt 2> fixed-action-arm64.log; then
  printf '%s\n' 'expected fixed-x86 action to reject ARM64-only execution' >&2
  exit 1
fi
grep -Eq 'No matching (execution platform|toolchains)' fixed-action-arm64.log
printf '%s\n' 'PASS: executable runfiles, target/exec CPU separation, payload platforms, action identity, exec groups and native actions'
