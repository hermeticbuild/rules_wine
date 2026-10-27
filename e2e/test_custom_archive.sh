#!/bin/sh
# External-consumer acquisition verification, validating a caller-supplied checksum.
set -eu
archive=${1:?usage: e2e/test_custom_archive.sh archive.tar.xz sha256}
checksum=${2:?archive sha256 required}
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d /tmp/rules-wine-custom-consumer.XXXXXX)
cat > "$scratch/MODULE.bazel" <<MODULE
module(name = "custom_wine_consumer")
bazel_dep(name = "rules_wine", version = "0.1.0")
bazel_dep(name = "platforms", version = "1.1.0")
local_path_override(module_name = "rules_wine", path = "$root")
http_archive = use_repo_rule("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
    name = "company_wine",
    urls = ["file://$archive"],
    sha256 = "$checksum",
    strip_prefix = "wine-11.0-amd64-wow64",
    build_file_content = """
package(default_visibility = ["//visibility:public"])
filegroup(name = "loader", srcs = ["bin/wine"])
filegroup(name = "server", srcs = ["bin/wineserver"])
filegroup(name = "files", srcs = glob(["**"]))
""",
)
register_toolchains("//:company_runner", "//:company_adapter")
MODULE
cp "$root/e2e/smoke/BUILD.bazel" "$scratch/BUILD.bazel"
cat >> "$scratch/BUILD.bazel" <<'BUILD'
load("@rules_wine//wine:toolchain.bzl", "windows_runner_toolchain")

windows_runner_toolchain(
    name = "company_impl",
    arch = "x86_64",
    backend = "wine",
    launcher = "@rules_wine//wine/runtime:supervisor",
    loader = "@company_wine//:loader",
    server = "@company_wine//:server",
    files = "@company_wine//:files",
    identity = "Local Kron4ek Wine 11.0 archive",
    requirements = "Ubuntu 24.04 console baseline",
)

toolchain(
    name = "company_runner",
    toolchain = "company_impl",
    toolchain_type = "@rules_wine//wine:runner_toolchain_type",
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
)

toolchain(
    name = "company_adapter",
    toolchain = "company_impl",
    toolchain_type = "@rules_wine//wine:adapter_toolchain_type",
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
)
BUILD
cp "$root/e2e/smoke/consumer.bzl" "$scratch/consumer.bzl"
cp "$root/e2e/smoke/.bazelrc" "$scratch/.bazelrc"
cp "$root/.bazelversion" "$scratch/.bazelversion"
printf '%s\n' "Verification consumer: $scratch"
cd "$scratch"
trap 'bazel --output_base="$scratch/output" shutdown >/dev/null 2>&1' EXIT
bazel --output_base="$scratch/output" build //:generate --config=remote
jq -e '.args | index("external-consumer") != null' bazel-bin/external.json
jq -e '.args | index("adapter-consumer") != null' bazel-bin/adapter.json
