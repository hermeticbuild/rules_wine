#!/bin/sh
# Exercise the extension through real module graphs and generated BUILD targets.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
rules=${1:-$root}
scratch=$(mktemp -d /tmp/rules-wine-extension.XXXXXX)
cp "$root/.bazelversion" "$scratch/.bazelversion"
printf 'Verification workspace: %s\n' "$scratch"
mkdir "$scratch/first" "$scratch/second"
printf '\n' > "$scratch/BUILD.bazel"
printf 'common --enable_bzlmod\n' > "$scratch/.bazelrc"
dependency() {
  printf 'module(name = "%s", version = "0.1.0")\nbazel_dep(name = "rules_wine", version = "0.1.0")\nwine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")\n%s\nuse_repo(wine, "wine_toolchains")\n' "$1" "$2" > "$scratch/$1/MODULE.bazel"
  printf '\n' > "$scratch/$1/BUILD.bazel"
}
root_module() {
  printf 'module(name = "extension_checks")\nbazel_dep(name = "rules_wine", version = "0.1.0")\nlocal_path_override(module_name = "rules_wine", path = "%s")\nbazel_dep(name = "first", version = "0.1.0")\nbazel_dep(name = "second", version = "0.1.0")\nlocal_path_override(module_name = "first", path = "first")\nlocal_path_override(module_name = "second", path = "second")\nwine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine"%s)\n%s\nuse_repo(wine, "wine_toolchains")\n' "$rules" "${2:-}" "$1" > "$scratch/MODULE.bazel"
}
query() {
  bazel cquery '@wine_toolchains//:all' --lockfile_mode=off --output=starlark --starlark:expr='str(target.label) + " " + str(providers(target))' > "$1" 2> "$1.log"
}
reject() {
  if query "$1"; then
    printf 'expected extension failure: %s\n' "$1" >&2
    exit 1
  fi
  grep -q "$2" "$1.log"
}
cd "$scratch"
trap 'bazel shutdown >/dev/null 2>&1' EXIT
dependency first ''
dependency second ''
root_module ''
# Unlike the runtime fixture, this consumer deliberately selects no compiler.
bazel mod graph --lockfile_mode=off --output=json > modules.json
jq -e 'all(.. | objects; .name != "llvm")' modules.json >/dev/null
query default.txt
grep -q 'hermeticbuild Wine 11.20.2 linux-amd64' default.txt
grep -q 'hermeticbuild Wine 11.20.2 linux-arm64' default.txt
grep -q 'hermeticbuild Wine 11.20.2 macos-arm64' default.txt
grep -q ':windows_x86_64 ' default.txt
grep -q ':windows_aarch64 ' default.txt
if grep -Eq ':windows_(x86_64|aarch64)_adapter' default.txt; then exit 1; fi
grep -q ':linux_aarch64 ' default.txt
grep -q ':osx_aarch64 ' default.txt
if grep -q ':osx_x86_64' default.txt; then exit 1; fi
[ "$(grep -Ec '^.*:(linux_x86_64|linux_aarch64|osx_aarch64|windows_x86_64|windows_aarch64) ' default.txt)" = 5 ]
[ "$(grep -Ec '^.*:(linux_x86_64|linux_aarch64|osx_aarch64)_adapter ' default.txt)" = 3 ]
# The extension has no acquisition API, including from transitive modules.
dependency first 'wine.prebuilt()'
reject removed_tag.txt 'does not have a tag class named prebuilt'
dependency first ''
root_module '' ', dev_dependency = True'
query dev.txt
if grep -q 'WARNING.*extension' dev.txt.log; then exit 1; fi
printf '%s\n' 'PASS: pinned defaults, shared extension usage, removed tags, native runners and dev usage'
