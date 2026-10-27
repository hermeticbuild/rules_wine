#!/bin/sh
# Build actual wrapper and PE artifacts with opposite-CPU-first registration.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d /tmp/rules-wine-adapter-platforms.XXXXXX)
cp -R "$root/e2e/starlark/." "$scratch/"
cp "$root/.bazelversion" "$scratch/.bazelversion"
printf 'module(name = "wine_adapter_platforms")\nbazel_dep(name = "rules_wine", version = "0.1.0")\nlocal_path_override(module_name = "rules_wine", path = "%s")\nbazel_dep(name = "platforms", version = "1.1.0")\nbazel_dep(name = "rules_cc", version = "0.2.18")\n' "$root" > "$scratch/MODULE.bazel"
printf 'import %s/.bazelrc\n' "$root" > "$scratch/.bazelrc"
printf 'Verification workspace: %s\n' "$scratch"
cd "$scratch"
trap 'bazel shutdown >/dev/null 2>&1' EXIT
for platform in audit_exec audit_arm64; do
  case "$platform" in
    audit_exec) order='//:audit_arm64,//:audit_exec'; cpu=x86_64; elf='x86-64'; pe='x86-64' ;;
    audit_arm64) order='//:audit_exec,//:audit_arm64'; cpu=aarch64; elf='ARM aarch64'; pe='Aarch64' ;;
  esac
  for aeg in --noincompatible_auto_exec_groups --incompatible_auto_exec_groups; do
    set -- --config=remote --jobs=80 --platforms="//:$platform" --extra_execution_platforms="$order" --extra_toolchains=//:adapter,//:adapter_arm64 "$aeg"
    name="$platform$aeg"
    bazel build //:source_adapter //:explicit_source //:selected_adapter //:fixed_target_adapter "$@" --remote_download_regex='.*source.exe' > "$name.log" 2>&1
    file bazel-bin/source_adapter | tee "$name-wrapper.txt" | grep -q "$elf"
    bazel cquery 'filter("^//:source$", deps(//:source_adapter))' "$@" --output=files > "$name-payload-path.txt" 2> "$name-query.log"
    file "$(cat "$name-payload-path.txt")" | tee "$name-pe.txt" | grep -q "$pe"
    bazel cquery 'filter("^//:source$", deps(//:explicit_source))' "$@" --output=files > "$name-explicit-path.txt" 2>> "$name-query.log"
    file "$(cat "$name-explicit-path.txt")" | grep -q 'x86-64'
    jq -e --arg cpu "$cpu" '.declared_guest_cpu == null and (.payload | endswith("fixture_" + $cpu + ".exe"))' bazel-bin/selected_adapter.json
    jq -e '.declared_guest_cpu == null and (.payload | endswith("fixture_x86_64.exe"))' bazel-bin/fixed_target_adapter.json
    bazel aquery 'mnemonic("FileWrite", //:source_adapter)' "$@" --include_file_write_contents --output=jsonproto > "$name-actions.json" 2>> "$name-query.log"
    jq -e --arg platform "//:$platform" '[.actions[].executionPlatform] == [$platform]' "$name-actions.json"
  done
done
printf '%s\n' 'PASS: source/default/explicit PE CPUs, fixed and selected prebuilts, ELF wrapper CPUs and AEG alignment'
