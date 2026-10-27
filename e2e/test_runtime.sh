#!/usr/bin/env bash
# Native downstream execution with the published defaults; no RBE or runtime cache.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root/e2e/smoke"
temp_root=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
case "$(uname -s)" in MINGW*|MSYS*) temp_root=$(cygpath -u "$temp_root") ;; esac
scratch=$(mktemp -d "$temp_root/rules-wine-runtime.XXXXXX")
echo "Verification output: $scratch"
export MSYS2_ARG_CONV_EXCL='*'
bazel_cmd() {
  bazel --nosystem_rc --nohome_rc --output_base="$scratch/output" "$@"
}
trap 'bazel_cmd shutdown >/dev/null 2>&1' EXIT
case "$(uname -s)" in
  Linux) os=linux; cpu=$(uname -m) ;;
  Darwin) os=osx; cpu=$(uname -m) ;;
  MINGW*|MSYS*)
    os=windows
    cpu=${PROCESSOR_ARCHITEW6432:-$PROCESSOR_ARCHITECTURE}
    scratch=$(cygpath -m "$scratch")
    ;;
  *) echo 'Unsupported executor' >&2; exit 1 ;;
esac
case "$cpu" in
  ARM64|arm64|aarch64) cpu=aarch64 ;;
  AMD64|x86_64) cpu=x86_64 ;;
  *) echo "Unsupported CPU: $cpu" >&2; exit 1 ;;
esac
guests=("$cpu")
apis=(action)
if [[ $os != windows ]]; then
  apis+=(adapter)
  if [[ $cpu == aarch64 ]]; then guests+=(x86_64); fi
fi
targets=()
for guest in "${guests[@]}"; do
  pe="$root/tests/fixture/fixture_$guest.exe"
  offset=$(od -An -tu4 -j60 -N4 "$pe" | tr -d ' \n')
  machine=$(od -An -tx2 -j"$((offset + 4))" -N2 "$pe" | tr -d ' \n')
  case "$guest" in x86_64) expected=8664 ;; aarch64) expected=aa64 ;; esac
  [[ $machine == "$expected" ]]
  for api in "${apis[@]}"; do targets+=("//:${api}_${guest}"); done
done
flags=(--lockfile_mode=off --remote_executor= --remote_cache= --disk_cache=
  --remote_accept_cached=false --symlink_prefix="$scratch/bazel-")
echo "Expected native executor: $os/$cpu"
bazel_cmd query @platforms//host:host --lockfile_mode=off --output=build | tee "$scratch/host.txt"
grep -q "cpu:$cpu" "$scratch/host.txt"
grep -q "os:$os" "$scratch/host.txt"
modes=(off strip)
# Bazel has no local Windows sandbox strategy capable of path mapping.
# Mapped native Windows actions need a suitable remote executor, not this job.
if [[ $os == windows ]]; then modes=(off); fi
for mode in "${modes[@]}"; do
  bazel_cmd build "${targets[@]}" "${flags[@]}" --experimental_output_paths="$mode" \
    '--modify_execution_info=WindowsRun|WineAdapterConsumer=+supports-path-mapping' \
    2>&1 | tee "$scratch/$mode.log"
  bin=$(bazel_cmd info bazel-bin "${flags[@]}" 2>/dev/null)
  for guest in "${guests[@]}"; do
    for api in "${apis[@]}"; do
      record="$scratch/$mode-$api-$guest.json"
      cp "$bin/${api}_${guest}/result café.json" "$record"
      jq -e --arg os "$os" --arg mode "$mode" '
        .child == "child-ok" and
        .env.FIXTURE_VALUE == "environment café" and
        .args[2:] == ["space value", "", "café", "$literal", "declared input café"] and
        (.args[1] | endswith("result café.json")) and
        ((.args[1] | test("bazel-out[/\\\\]cfg[/\\\\]")) == ($mode == "strip")) and
        ((.env.WINEPREFIX != "") == ($os != "windows"))
      ' "$record" >/dev/null
    done
  done
done
bazel_cmd aquery "mnemonic(\"WindowsRun|WineAdapterConsumer\", set(${targets[*]}))" \
  "${flags[@]}" --output=jsonproto > "$scratch/actions.json" 2> "$scratch/actions.log"
jq -e --arg os "$os" --arg cpu "$cpu" --argjson count "${#targets[@]}" '
  (.actions | length) == $count and
  all(.actions[]; (.executionPlatform | endswith("//host:host"))) and
  (if $os == "windows" then
    all(.actions[]; (.arguments[0] | endswith(".exe")) and
      (.arguments | index("--config") == null)) and
    all(.pathFragments[]; (.label | test("wine_prebuilt|supervisor") | not))
  else
    all(.actions[] | select(.mnemonic == "WindowsRun");
      (.arguments[2] | fromjson | .arch) == $cpu)
  end)
' "$scratch/actions.json" >/dev/null
echo "PASS: $os/$cpu, guests ${guests[*]}, APIs ${apis[*]}, mapping ${modes[*]}"
