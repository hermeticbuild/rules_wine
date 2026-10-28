# Custom Wine toolchains

The module extension generates the default toolchains. Register them with
`register_toolchains("@wine_toolchains//:all")`; a `bazel_dep` alone does not.
For a custom-only setup, omit that extension and register your own toolchains
as below. To choose workers without replacing the distributions, see
[execution platform selection](actions.md#choose-a-worker-cpu).

## Acquire and register a distribution

Acquire custom archives with a standard repository rule in `MODULE.bazel`:

```starlark
http_archive = use_repo_rule("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
    name = "company_wine",
    urls = ["https://your-artifact-store/wine-arm64.tar.xz"],
    sha256 = "<actual archive sha256>",
    strip_prefix = "wine-arm64",
    build_file_content = """
package(default_visibility = ["//visibility:public"])
filegroup(name = "loader", srcs = ["bin/wine"])
filegroup(name = "server", srcs = ["bin/wineserver"])
filegroup(name = "files", srcs = glob(["**"]))
""",
)
register_toolchains("//:company_runner", "//:company_adapter")
```

Declare the implementation and both registrations in `BUILD.bazel`:

```starlark
load("@rules_wine//wine:toolchain.bzl", "windows_runner_toolchain")

windows_runner_toolchain(
    name = "company_impl",
    arch = "aarch64",
    backend = "wine",
    launcher = "@rules_wine//wine/runtime:supervisor",
    loader = "@company_wine//:loader",
    server = "@company_wine//:server",
    files = "@company_wine//:files",
    identity = "your Wine build and revision",
    requirements = "your audited host dependency baseline",
)

toolchain(
    name = "company_runner",
    toolchain = "company_impl",
    toolchain_type = "@rules_wine//wine:runner_toolchain_type",
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:aarch64"],
)

toolchain(
    name = "company_adapter",
    toolchain = "company_impl",
    toolchain_type = "@rules_wine//wine:adapter_toolchain_type",
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:aarch64"],
    target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:aarch64"],
)
```

`http_archive` owns download, checksum, mirror retry and extraction. Loader/server
must be native ELF or Mach-O executables; the supervisor checks their CPU headers
before launch (no Rosetta fallback). Shell-script Wine launchers are not accepted.
Keep the complete installation layout.

The extension supplies pinned Linux x86-64, Linux ARM64 and macOS ARM64 Wine,
plus native Windows x86-64/ARM64: five runners and three adapters. Each registration
requires Wine itself to match its executor CPU. It has no tags and does not combine custom
archives from transitive modules. Intel macOS requires a custom runtime. For custom-only
setup, omit the extension and register only your own toolchains. Adding a
`bazel_dep` alone does not register the defaults.

## Runtime configuration

Distribution `env` may supply loader library paths using `{loader_dir}` and
`{server_dir}`, e.g. `DYLD_FALLBACK_LIBRARY_PATH = "{loader_dir}/../../libs"`.
Lifecycle variables such as WINEPREFIX, WINESERVER and WINELOADER are reserved.
The supervisor initializes each private prefix with Wine's `wineboot.exe --init`.
Wine owns lookup of its builtin programs; no distribution-specific DLL directory
is assumed.

Define `windows_runner_toolchain` from
`@rules_wine//wine:toolchain.bzl`. A Wine implementation requires `arch`,
`backend = "wine"`, `launcher`, `loader` and `server`. Supply `files` for the
complete distribution; `identity` and `requirements` describe its provenance and
host requirements. `env` defaults to an empty dictionary. The implementation
can serve runner and binary adapter registrations. Native Windows uses a direct
action runner without `launcher` or Wine files.
Wine implementations can register against `runner_toolchain_type` and
`adapter_toolchain_type`; native implementations register only as runners.
Both have executor OS/CPU constraints. Runners impose no final-output
constraints; binary adapters additionally have matching target OS/CPU constraints.
`WindowsRunnerInfo` and `WineRuntimeInfo` expose
the advanced contract. `launcher` is an executable dependency in execution
configuration; its FilesToRunProvider and full runfiles are preserved, including
executable targets with sidecar outputs. Runtime
loader/server/files dependencies also use execution configuration.

