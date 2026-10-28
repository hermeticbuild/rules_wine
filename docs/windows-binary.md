# Executable adapters

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

## Payload compilation and platform selection

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

## Arguments, environment and runfiles

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

