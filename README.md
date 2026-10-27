# rules_wine

Run Windows executables as Bazel actions and executable tools. Wine runs
payloads on Linux or macOS; Windows actions execute the payload directly.
The rules do not own your compiler, SDK, language, or final output platform.

The [native E2E suite](tests/README.md) exercises the default toolchains on the
five required executor platforms with Bazel 8 and 9. Run `e2e/test_runtime.sh`
locally; GitHub Actions runs the same consumer and separate Linux regression tests.

Bazel 8.5.0 and 9.3.1 are exercised. Initial runtime status:

| Executor / Windows payload | Acquisition | Validation |
| --- | --- | --- |
| Linux x86_64 / x86_64 | Pinned Wine 11.20.1 default | Remote actions, adapters and lifecycle pass |
| Linux ARM64 / ARM64 and x86_64 | Pinned Wine 11.20.1 default | Native and FEX-translated remote execution verified |
| Windows x86_64 / x86_64 | No Wine required | Direct-action graph verified; execution untested |
| Windows ARM64 / ARM64 | No Wine required | Direct-action graph verified; execution untested |
| macOS Intel / x86_64 | User-supplied native archive | Supervisor cross-compiled with Apple SDK 26.5 override; execution untested |
| macOS ARM64 / ARM64 and x86_64 | Pinned Wine 11.20.1 default | Native and FEX-translated execution with Apple SDK 26.5 override; initialization caveat below |

The default ARM64 archives bundle FEX and can also run amd64 Windows executables.
No extra registration or guest-CPU attribute is needed: the selected Wine runtime
decides which payload CPUs it supports. Unsupported payloads fail inside Wine.
Linux amd64 → Windows ARM64 is unsupported by the default runtime. There is no
Rosetta or QEMU fallback; i386 execution is outside the tested contract.

## Setup

Until this module is published, consume a checkout through a local override:

```starlark
bazel_dep(name = "rules_wine", version = "0.1.0")
bazel_dep(name = "platforms", version = "1.1.0")  # CPU constraints for fixed prebuilts.
local_path_override(module_name = "rules_wine", path = "../rules_wine")
wine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")
use_repo(wine, "wine_toolchains")
register_toolchains("@wine_toolchains//:all")
```

Register execution platforms appropriate to your local or remote workers. The
ruleset does not infer remote worker capabilities from the machine running Bazel.
The supervisor is a C++ source target built with the execution-platform compiler.
This module depends on `rules_cc` and `@llvm` and registers `@llvm` C++ toolchains;
downstream Wine builds compile the supervisor on demand. `hermetic_launcher`
provides the small runfiles bootstrap from published binaries; consumers do not
need a Rust compiler.
`@llvm` 0.7.6 uses Bazel APIs unavailable in Bazel 7.7, so this source-built
version requires Bazel 8.5 or newer.
Native Windows registrations have no Wine archive dependency. Archives are fetched
only when referenced.

Defaults use the public [hermeticbuild Wine 11.20.1 release](https://github.com/hermeticbuild/wine-prebuilt/releases/tag/11.20.1).
Each archive is pinned by SHA-256 in the extension and retains its full layout.
Linux distributions require glibc 2.17 or newer and an available UTF-8 locale;
other Windows subsystems may need additional host libraries. macOS ARM64 has a
26.5 deployment target; the release was built/tested on 26.6.2 and these rules'
Bazel wrappers were exercised on 26.5.2. This does not prove execution on exact
26.5. The macOS archive is an unsigned command-line runtime, not a notarized app.
See release manifests, `DISTRIBUTION.md` and [testing notes](tests/README.md).

The pinned `@llvm` 0.7.6 default macOS SDK URL is unavailable. macOS source builds
currently need the SDK archive override documented in the testing notes.

## Executable adapters

```starlark
load("@rules_wine//wine:windows_binary.bzl", "windows_binary")

windows_binary(
    name = "generator",
    binary = "generator.exe",
)
```

`windows_binary` exposes a Windows executable through Wine on Linux or
macOS. Use it with `bazel run //:generator -- ...` or as an executable dependency
of a generic rule. It is currently scoped to non-Windows execution; use
`windows_actions.run` for actions that also need native Windows execution.

`binary` accepts one prebuilt PE file or an executable target. For source-built
inputs, optionally set `target_platform = "//platforms:windows_x86_64"` to
transition only the payload and its dependencies. That platform must declare
Windows and the same CPU as the resolved adapter toolchain; your compiler/toolchain
must support it. This source-compilation restriction is unchanged; the cross-CPU
support described here applies to already-built executables.

The adapter follows its own target platform: the host by default, or the
consumer's selected executor when its attribute uses `cfg = "exec"`. For a named
execution group use `cfg = config.exec("group")`. The consuming action must run
on that same platform. Registering remote platforms alone does not make a foreign
adapter executable locally with `bazel run`.

There is no `arch` attribute: Bazel selects the adapter implementation from platform
constraints. These describe the native adapter and Wine, not the PE payload.
For an amd64 prebuilt, the default ARM64 Wine runtime can translate its CPU.
To require an amd64 adapter instead, set
`target_compatible_with = ["@platforms//cpu:x86_64"]`; a consumer using
`cfg = "exec"` must then select a compatible executor. Bazel does not infer a
PE file's CPU or choose another worker after Wine rejects a payload.

Callers provide invocation arguments and environment. There are no wrapper
`arguments`, `env`, or `data` attributes and no location-expression expansion.
The underlying executable owns its runfiles. Its `RunEnvironmentInfo` is forwarded
for `bazel run`; ordinary action invocations still use the action's environment.
Default command-line arguments of the underlying target are not inherited.

Companion files retain their existing runfiles layout. DLLs that require
executable adjacency must already be adjacent in that layout; arrange generated
executable/DLL outputs in the same directory.
For prebuilts with companion files, expose an executable target owning those
runfiles instead of passing a bare PE file.

`hermetic_launcher` resolves the supervisor and configuration through runfiles,
then forwards invocation arguments. The Linux/macOS supervisor uses `rules_cc`'s
runfiles library and forwards its discovered runfiles environment, converting
paths for Wine. Wrapped programs can therefore use standard runfiles libraries
when launched as action tools. The ruleset does not create replacement manifests.
Response-file contents and encoding belong to the payload.

For path arguments to a Wine-only adapter, load `wine_path` from
`@rules_wine//wine:actions.bzl` and use it as an `Args` callback:
`args.add_all([output], map_each = wine_path)`. This requires no runner resolution.
Do not call `wine_path(output)` during analysis; the callback must run during
argument expansion for optional path mapping to work. For a directory artifact,
also set `expand_directories = False`.

## Other rule authors

For a standalone Windows x86_64 prebuilt, constrain the action's execution group
to x86_64 and resolve its runner once. The final output may target a different
OS or CPU.

```starlark
load("@rules_wine//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    runner = windows_actions.resolve(ctx, exec_group = "windows")
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    response = ctx.actions.args()
    response.add_all(["opaque value", "café"])
    response.use_param_file("@%s", use_always = True)  # Only if your tool supports it.
    response.set_param_file_format("multiline")
    args = ctx.actions.args()
    args.add("--output")
    windows_actions.add_path(runner, args, out)
    windows_actions.run(
        ctx,
        runner = runner,
        executable = ctx.file.tool,
        arguments = [args, response],
        outputs = [out],
    )
    return [DefaultInfo(files = depset([out]))]

my_rule = rule(
    implementation = _impl,
    attrs = {
        "tool": attr.label(
            allow_single_file = True,
            mandatory = True,
            cfg = config.exec("windows"),
        ),
    },
    exec_groups = {
        "windows": exec_group(
            toolchains = [windows_actions.toolchain_type],
            exec_compatible_with = ["@platforms//cpu:x86_64"],
        ),
    },
)
```

`windows_actions.toolchain_type` is a Label, shared by every supported CPU.
Declare it on the rule or execution group before calling `resolve`. The returned
context binds the selected `WindowsRunnerInfo` (available as `runner.windows`)
and execution group; pass that same context to `run` and `add_path`. No architecture
or group is repeated on those calls. `resolve(ctx)` uses the default group.
Resolution chooses the runner for the executor, independently of the rule's
target platform. A fixed-CPU payload requires an execution constraint; its
`target_compatible_with` does not select the consumer's executor.

The helper does not compile or transition the payload. The example accepts a
prebuilt `.exe`: `config.exec("windows")` means the group named `windows`, not
the Windows operating system. For source-built payloads, their owning rule must
provide a Windows compilation transition matching the executor CPU. Merely
setting `cfg = "exec"` on a `cc_binary` would build a Linux executable on a
Linux executor. Use an executable attribute and pass its `FilesToRunProvider`
when the payload owns runfiles. Alternatively, consume `windows_binary` through
`cfg = "exec"` and ordinary `ctx.actions.run` for Wine-only executable tools.

A native Windows action invokes the payload directly, preserving its
FilesToRunProvider when supplied; Wine uses its supervisor, config and complete
distribution as declared inputs. `inputs` accepts
a list or depset; `runtime_files`, outputs, environment, mnemonic and additional
`ctx.actions.run` keyword arguments are supported. Args stay lazy. Explicit path
markers inside a response file are not interpreted by the supervisor; use
payload-native relative paths or format response content in the consumer rule.

`windows_actions.add_path(runner, args, file, format = "%s")` appends a typed
`File` path to an `Args` object. It encodes a JSON-escaped `{windows_path:...}`
marker for Wine and uses an ordinary path for native Windows. Encoding happens
during argument expansion, after Bazel applies any path mapping. Directory
artifacts remain directory paths. Use `format = "/out:%s"` or `"@%s"` for tool
option syntax. The helper replaces the eager string-returning `windows_actions.path`.
Use `Args.add` for literal arguments; execution-path strings are not mapped.

Optional Bazel output path mapping is supported on Bazel 8.5 and 9.3. Callers opt
in with `execution_requirements = {"supports-path-mapping": "1"}` on
`windows_actions.run` or the action consuming an adapter, and enable
`--experimental_output_paths=strip`. The same implementation handles mapping off
and Bazel's fallback when input paths would collide. Wine configuration is JSON
serialized through an action-owned `Args` parameter file, so its loader, server
and payload paths receive that action's mapping. `windows_binary` configuration
continues to use logical runfiles keys; its consumer must construct path arguments
with deferred `Args` as well.

Opt-in covers the entire action: callers own whether their tool and outputs are
safe to map. Environment values remain literal strings; paths embedded there or
in separately generated files are not rewritten. Prefer typed command-line
arguments for generated paths. Payload response files retain their tool-specific
syntax and encoding: `Args` can map typed paths in action-owned parameter files,
but Wine markers inside their contents are not interpreted. Do not use `add_path`
inside a payload response file. Rules do not inspect or repair arbitrary strings,
manifests or output contents.

`windows_binary` is one rule requiring `adapter_toolchain_type`. Each implementation
constrains both executor and target OS/CPU; the resolved toolchain supplies the
architecture. This uses ordinary toolchain resolution on Bazel 8 and 9. Action helpers use
the runner type declared by the consuming rule; it selects native Wine for the executor
without restricting the final output platform.

## Custom distributions and toolchains

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

Distribution `env` may supply loader library paths using `{loader_dir}` and
`{server_dir}`, e.g. `DYLD_FALLBACK_LIBRARY_PATH = "{loader_dir}/../../libs"`.
Lifecycle variables such as WINEPREFIX, WINESERVER and WINELOADER are reserved.
The supervisor initializes each private prefix with Wine's `wineboot.exe --init`.
Wine owns lookup of its builtin programs; no distribution-specific DLL directory
is assumed.

Define `windows_runner_toolchain` from
`@rules_wine//wine:toolchain.bzl`. A Wine implementation needs `arch`, `backend`,
`launcher`, `loader`, `server`, `files`, `identity`, `requirements`, and `env`; it
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

## Isolation, runtime maintenance and limits

Each invocation creates a private prefix, home/cache/temp directories and a fresh
Wine server. Mono/Gecko and menu-builder integration are disabled. The pinned
loader/server paths are explicit. Initial setup has a 60-second deadline;
prefix-scoped server stop/wait each have a 5-second deadline. Linux cancellation
kills the payload process group, stops the owned server, reaps children, then
removes scratch state. Cleanup errors are reported without replacing the payload
result. Exit statuses 0–255 pass through on Unix; signals use 128+signal. Wine's
CLI can truncate full Windows statuses before the Unix supervisor receives them;
lossless full Windows exit reporting is not supplied. Native Windows actions
retain the native process interface.

Prefix isolation is not a security sandbox. No shared/prepared prefixes,
winetricks, machine Wine, shell utilities or Python are in the production runtime.
Stronger filesystem/process/network isolation, immutable prefix seeds, GUI/.NET,
coverage and workers remain future work. See [testing and maintenance](tests/README.md)
for the verification commands and platform gaps.

The supervisor is compiled from source for the selected execution platform. No
supervisor binary is checked in. `tests/compile_platforms.sh --config=remote` checks
the four Linux/macOS cross-compilation targets;
`tests/update_fixtures.sh --config=remote` rebuilds development-only fixtures,
which are not consumer dependencies.

The published macOS runtime prints a `virtual_alloc_first_teb` assertion during
fresh prefix initialization. This also occurs with bare Wine; initialization and
independently compiled ARM64 fixtures still return success. Native Windows runtime
execution and Intel macOS execution remain unverified.
