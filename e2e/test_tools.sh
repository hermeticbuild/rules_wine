#!/usr/bin/env bash
# Compiler-free consumer, native tools on every executor, both Windows output ABIs.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temp_root=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
case "$(uname -s)" in MINGW*|MSYS*) temp_root=$(cygpath -u "$temp_root") ;; esac
scratch=$(mktemp -d "$temp_root/rules-wine-tools.XXXXXX")
echo "Native tools verification: $scratch"
export MSYS2_ARG_CONV_EXCL='*'
# A relocated consumer also exercises spaces in the source and output roots.
mkdir "$scratch/consumer space"
cp "$root/e2e/tools/"*.bazel "$root/e2e/tools/"*.bzl "$root/e2e/tools/"*.idl \
  "$root/e2e/tools/"*.rc "$root/e2e/tools/"*.mc "$root/e2e/tools/"*.tlb "$scratch/consumer space/"
cp "$root/e2e/tools/.bazelrc" "$scratch/consumer space/"
cp "$root/.bazelversion" "$scratch/consumer space/"
rules_path=$root
case "$(uname -s)" in MINGW*|MSYS*) rules_path=$(cygpath -m "$root"); scratch=$(cygpath -m "$scratch") ;; esac
sed "s|path = \"../..\"|path = \"$rules_path\"|" "$root/e2e/tools/MODULE.bazel" > "$scratch/consumer space/MODULE.bazel"
cd "$scratch/consumer space"
bazel_cmd() { bazel --nosystem_rc --nohome_rc --output_base="$scratch/output" "$@"; }
trap 'bazel_cmd shutdown >/dev/null 2>&1' EXIT
flags=(--lockfile_mode=off --remote_executor= --remote_cache= --disk_cache= --remote_accept_cached=false --symlink_prefix="$scratch/bazel-")
for tool in wmc wrc widl; do
  version_flag=-V
  if [[ $tool == wrc ]]; then version_flag=--version; fi
  bazel_cmd run "@rules_wine//wine:$tool" "${flags[@]}" -- "$version_flag" > "$scratch/$tool-version.log" 2>&1
  grep -qi 'Wine' "$scratch/$tool-version.log"
done
bazel_cmd mod graph --lockfile_mode=off --output=json > "$scratch/modules.json"
jq -e 'all(.. | objects; .name != "llvm")' "$scratch/modules.json" >/dev/null
modes=(off strip)
# Local Windows has no sandbox strategy that supports path mapping.
case "$(uname -s)" in MINGW*|MSYS*) modes=(off) ;; esac
for cpu in x86_64 aarch64; do
  for mode in "${modes[@]}"; do
    bazel_cmd build //:all_outputs "${flags[@]}" --platforms="@rules_wine//platforms:windows_$cpu" \
      --experimental_output_paths="$mode" \
      '--modify_execution_info=WineMessageCompile|WineResourceCompile|WineIdlCompile=+supports-path-mapping' \
      2>&1 | tee "$scratch/$cpu-$mode.log"
    bin=$(bazel_cmd info bazel-bin "${flags[@]}" 2>/dev/null)
    bash "$root/e2e/verify_tools.sh" "$bin" "$scratch"
    if [[ $mode == strip ]]; then
      grep -q 'bazel-out/cfg/' "$bin/messages.rc"
    elif grep -q 'bazel-out/cfg/' "$bin/messages.rc"; then
      exit 1
    fi
    cp "$bin/example_p.c" "$scratch/$cpu-$mode-proxy.c"
    cp "$bin/rpc_c.c" "$scratch/$cpu-$mode-client.c"
  done
  bazel_cmd aquery 'deps(//:all_outputs)' "${flags[@]}" \
    --platforms="@rules_wine//platforms:windows_$cpu" --output=jsonproto \
    > "$scratch/$cpu-actions.json" 2> "$scratch/$cpu-actions.log"
  jq -e --arg cpu "$cpu" '
    ([.actions[] | select(.mnemonic | test("^Wine.*Compile$"))] | length) == 15 and
    ([.actions[] | select(.mnemonic == "RunBinary")] | length) == 5 and
    all(.actions[]; (.mnemonic | test("CppCompile|CppLink|CppArchive") | not)) and
    all(.actions[]; (.arguments // [] | index("-I")) == null) and
    all(.actions[] | select(.mnemonic | test("^Wine.*Compile$")); (.executionPlatform | endswith("//host:host"))) and
    all(.actions[] | select(.mnemonic == "WineIdlCompile");
      (.arguments | index($cpu + "-w64-mingw32")) != null and
      any(.arguments[]; endswith("/" + $cpu + "-windows")) and
      (.arguments | index("--nostdinc")) != null) and
    all(.pathFragments[]; (.label | test("wine_prebuilt_|^supervisor|^fex($|-)"; "i") | not)) and
    any(.pathFragments[]; .label == "stdole2.tlb") and
    any(.pathFragments[]; .label == "payload.txt")
  ' "$scratch/$cpu-actions.json" >/dev/null
done
# Force uncached actions at identical paths and compare concrete products.
stable=(messages.h messages.rc messages.res inline_messages.res nested/resources.res interfaces.tlb example_p.c rpc_c.c)
mkdir -p "$scratch/repeated/nested"
for file in "${stable[@]}"; do cp "$bin/$file" "$scratch/repeated/$file"; done
bazel_cmd build //:all_outputs "${flags[@]}" --platforms=@rules_wine//platforms:windows_aarch64 \
  --experimental_output_paths="${modes[${#modes[@]}-1]}" \
  '--modify_execution_info=WineMessageCompile|WineResourceCompile|WineIdlCompile=+supports-path-mapping,WineMessageCompile|WineResourceCompile|WineIdlCompile=+no-cache' \
  > "$scratch/repeated.log" 2>&1
for file in "${stable[@]}"; do cmp "$bin/$file" "$scratch/repeated/$file"; done
# ARM64 and x86_64 interpreter procedure formats must differ, on the same executor.
if cmp -s "$scratch/x86_64-off-proxy.c" "$scratch/aarch64-off-proxy.c"; then exit 1; fi
if cmp -s "$scratch/x86_64-off-client.c" "$scratch/aarch64-off-client.c"; then exit 1; fi
# Undeclared files are absent from the Unix sandbox, including generated siblings.
case "$(uname -s)" in
  MINGW*|MSYS*) negatives=(bad_message qualified_import) ;;
  *) negatives=(missing_asset missing_import bad_message qualified_import) ;;
esac
negatives+=(absolute_include absolute_windows_include)
for target in "${negatives[@]}"; do
  if bazel_cmd build "//:$target" "${flags[@]}" > "$scratch/$target.log" 2>&1; then
    echo "Expected failure: $target" >&2; exit 1
  fi
  case $target in
    missing_asset) grep -q 'payload.txt' "$scratch/$target.log" ;;
    missing_import) grep -q 'example.idl' "$scratch/$target.log" ;;
    bad_message) grep -q 'bad.mc' "$scratch/$target.log" ;;
    qualified_import) grep -q 'sub/example.idl' "$scratch/$target.log" ;;
    absolute*) grep -q 'includes entries must be package-relative' "$scratch/$target.log" ;;
  esac
done
bazel_cmd build //:resources //:message_res "${flags[@]}" --platforms=//:unsupported_cpu > "$scratch/neutral.log" 2>&1
if bazel_cmd build //:interfaces "${flags[@]}" --platforms=//:unsupported_cpu > "$scratch/unsupported.log" 2>&1; then
  echo 'Expected unsupported IDL target CPU failure' >&2; exit 1
fi
grep -q 'supports target CPUs x86_64 and aarch64' "$scratch/unsupported.log"
echo "PASS: native wmc/wrc/widl, both target ABIs, declared generated inputs, content, compiler-free graph, mapping ${modes[*]}"
