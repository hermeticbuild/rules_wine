# rules_wine

Run Windows executables as Bazel actions and executable tools. Wine runs
supported Windows guest CPUs on native Linux or macOS runtimes; Windows actions execute the payload directly.
The rules do not own your compiler, SDK, language, or final output platform.

Bazel 8.5.0 and 9.3.1 are exercised. Initial runtime status:

| Executor / Windows payload | Acquisition | Validation |
| --- | --- | --- |
| Linux x86_64 / x86_64 | Pinned Wine 11.0 default | Remote actions, adapters and lifecycle pass |
| Linux ARM64 / ARM64 | User-supplied native archive | Supervisor cross-compiled; execution untested |
| Windows x86_64 / x86_64 | No Wine required | Direct-action graph verified; execution untested |
| Windows ARM64 / ARM64 | No Wine required | Direct-action graph verified; execution untested |
| macOS Intel / x86_64 | User-supplied native archive | Supervisor cross-compiled with Apple SDK 26.5 override; execution untested |
| macOS ARM64 / ARM64 | User-supplied native archive | Supervisor cross-compiled with Apple SDK 26.5 override; experimental runtime limitation below |

Supported Windows guests are x86_64 and ARM64 only. A custom native Wine runtime
may support both, for example through bundled FEX. No Rosetta or QEMU integration;
i386 payloads are rejected. Capability declarations do not select a new executor.

## Setup

Until this module is published, consume a checkout through a local override:

```starlark
bazel_dep(name = "rules_wine", version = "0.1.0")
bazel_dep(name = "platforms", version = "1.1.0")
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

The default is [Kron4ek Wine 11.0 amd64 WoW64](https://github.com/Kron4ek/Wine-Builds/releases/tag/11.0),
SHA256 `39574efa1132c3ca0d5c77dd2eddbe4a49cca0d6cc2c290ff4924493a1c40314`.
It requires the host glibc ELF interpreter, libc/libdl/libpthread and libgcc_s.
Ubuntu 24.04 console execution was verified; missing FreeType emits warnings.
Other Windows subsystems can require additional host libraries. A pinned archive
is not a fully bundled Linux userspace. See [testing and maintenance](tests/README.md).

## Executable adapters

```starlark
load("@rules_wine//wine:windows_binary.bzl", "windows_binary")

# A source target such as cc_binary(name = "generator_impl", srcs = [...]).
windows_binary(name = "generator", binary = "generator_impl")

# Ordinary fixed PE files need no metadata wrapper.
windows_binary(name = "prebuilt_generator", binary = "generator-amd64.exe")
```

`windows_binary` exposes a Windows executable through Wine on Linux or macOS.
Use it with `bazel run //:generator -- ...` or as an executable dependency with
`cfg = "exec"` in a generic rule. For actions that also need native Windows,
use `windows_actions.run`.

Source dependencies are compiled for a supplied Windows platform matching the
wrapper's CPU: x86_64 or ARM64. The wrapper follows its own target configuration,
usually the local host for `bazel run`, or the consuming action's executor for
`cfg = "exec"`. Set `target_platform = "//platforms:my_windows_platform"` to
choose another Windows CPU or preserve custom SDK/ABI constraints. A compatible
compiler toolchain must be available; supplied platforms do not preserve arbitrary
constraints from the incoming platform.

The transition requests a configuration; it never proves a PE's actual CPU.
A fixed prebuilt stays fixed. A target with `select()` is evaluated in the chosen
Windows configuration, including imports. At execution, Wine's supervisor reads
the PE machine and checks it against the selected runtime's supported guests.
Undeclared incompatibilities therefore fail during execution, not analysis.

For optional earlier checks and companion files:

```starlark
load("@rules_wine//wine:windows_import.bzl", "windows_import")

windows_import(
    name = "generator_payload",
    executable = "generator-amd64.exe",
    guest_cpu = "@platforms//cpu:x86_64",
    data = ["companion.dll"],
)
windows_binary(name = "declared_generator", binary = "generator_payload")
```

`windows_import` supplies `WindowsExecutableInfo`; it is a metadata target, not an
executable wrapper. It retains the original File/FilesToRunProvider and executable
path. Declared incompatibilities fail during analysis; Wine also rejects a PE
whose actual CPU contradicts its declaration. CPU labels must be the standard
`@platforms//cpu:x86_64` or `@platforms//cpu:aarch64` constraints.

`data` adds companion default-output files at their existing paths. It does not
import data targets' runfiles, relocate DLLs, or augment the underlying executable's
own runfiles tree/manifest. DLLs requiring adjacency must already share the PE's
artifact directory. The adapter exposes those files at their normal runfiles keys.
An executable target's existing runfiles, including aliases, are preserved.

Callers provide invocation arguments and environment. There are no adapter
`arguments`, `env`, or `data` attributes or location-expression expansion.
`RunEnvironmentInfo` is forwarded for `bazel run`; ordinary adapter actions use
the action's environment. The underlying target's default command-line arguments
are not inherited. Registering remote platforms alone does not make a foreign
adapter runnable locally.

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

Resolve the runner for the consuming action or execution group. The final output
may target a different OS or CPU. This example explicitly requests a native x86_64
executor; generic reusable rules need not hardcode a guest CPU.

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
target platform. Use execution constraints when a specific native executor is
required; the payload's `target_compatible_with` does not select that executor.
Runtime capabilities do not participate in toolchain resolution.

The helper does not compile or transition the payload. The example accepts a
prebuilt `.exe`: `config.exec("windows")` means the group named `windows`, not
the Windows operating system. For source-built payloads, their owning rule must
provide a Windows compilation transition matching the executor CPU. Merely
setting `cfg = "exec"` on a `cc_binary` would build a Linux executable on a
Linux executor. Use an executable attribute and pass its `FilesToRunProvider`
when the payload owns runfiles. Alternatively, consume `windows_binary` through
`cfg = "exec"` and ordinary `ctx.actions.run` for Wine-only executable tools.

`executable` accepts a File, FilesToRunProvider, or Target. For a metadata import,
pass `executable = ctx.attr.tool`; the target supplies WindowsExecutableInfo. Typed
metadata carries companion inputs and declared CPU checks. Action environments
remain explicit; RunEnvironmentInfo applies to `bazel run` through an adapter.
A native Windows action invokes the payload directly, preserving its
FilesToRunProvider when supplied; Wine uses its supervisor, config and complete
distribution as declared inputs. Native declared mismatches fail in analysis;
undeclared compatibility is handled by Windows itself, without a supervisor.
`inputs` accepts
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

The adapter's internal rule jointly resolves its adapter, launcher template and
finalizer on one platform, including when automatic execution groups are enabled.
Runner actions resolve independently of the final product's target CPU.

For native-CPU RBE placement, put `exec_compatible_with` on the consuming rule's
action group, not the payload dependency. Register platforms whose `exec_properties`
actually route to the requested worker CPU. Constraints alone do not provision
workers. A named wrapper group uses `cfg = config.exec("windows")` for the tool
and `exec_group = "windows", toolchain = None` on its ordinary action; a low-level
runner action instead retains its runner toolchain association and uses
`windows_actions.resolve(ctx, exec_group = "windows")`.

A same-CPU initial payload uses the native Wine route even in a multi-guest
runtime. This is not a process-tree guarantee: a different-CPU child can use the
runtime's bundled emulation. Strict no-emulation policies require a restricted
runtime or separate enforcement.

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
    supported_guest_cpus = ["@platforms//cpu:aarch64"],
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

The extension supplies pinned Linux x86-64 Wine and native Windows x86-64/ARM64
registrations only. It has no tags and does not combine custom archives from
transitive modules. Linux ARM64 and macOS require custom toolchains. For custom-only
setup, omit the extension and register only your own toolchains. Adding a
`bazel_dep` alone does not register the defaults.

Distribution `env` may supply loader library paths using `{loader_dir}` and
`{server_dir}`, e.g. `DYLD_FALLBACK_LIBRARY_PATH = "{loader_dir}/../../libs"`.
Lifecycle variables such as WINEPREFIX, WINESERVER and WINELOADER are reserved.
The supervisor initializes each private prefix with Wine's `wineboot.exe --init`.
Wine owns lookup of its builtin programs; no distribution-specific DLL directory
is assumed.

Define `windows_runner_toolchain` from
`@rules_wine//wine:toolchain.bzl`. A Wine implementation needs `supported_guest_cpus`, `backend`,
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

macOS ARM64 requires a compatible native Wine archive. The experimental build
evaluated so far could run its bundled programs but failed independent ARM64
executables outside Bazel too. General external-program execution remains
**unverified**, and no macOS archive is selected by default.
