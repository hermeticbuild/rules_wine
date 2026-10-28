# Running Windows build tools

## Default execution platform

For a prebuilt tool, use the rule's default execution group:

```starlark
load("@rules_wine//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    runner = windows_actions.resolve(ctx)
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    args = ctx.actions.args()
    args.add("--output")
    windows_actions.add_path(runner, args, out)
    windows_actions.run(
        ctx,
        runner = runner,
        executable = ctx.file.tool,
        arguments = [args],
        outputs = [out],
    )
    return [DefaultInfo(files = depset([out]))]

my_rule = rule(
    implementation = _impl,
    attrs = {
        "tool": attr.label(allow_single_file = [".exe"], mandatory = True, cfg = "exec"),
    },
    toolchains = [windows_actions.toolchain_type],
)
```

No CPU is specified here. Bazel selects a worker and the matching runner; the
selected Wine distribution determines which prebuilt guest CPUs it can execute.

## Choose a worker CPU

To run a Windows x86_64 prebuilt without CPU translation, constrain the action's
execution group to x86_64 and resolve its runner once, as below. For the default
behavior, declare `toolchains = [windows_actions.toolchain_type]` on the rule,
use `cfg = "exec"` on the tool attribute and `windows_actions.resolve(ctx)`;
no named group or CPU constraint is needed. The default ARM64 Wine runtimes can
then run the x86_64 prebuilt through FEX. The final output may target a different
OS or CPU in either case.

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

## Runner and payload configuration

`windows_actions.toolchain_type` is a Label, shared by every supported CPU.
Declare it on the rule or execution group before calling `resolve`. The returned
context binds the selected `WindowsRunnerInfo` (available as `runner.windows`)
and execution group; pass that same context to `run` and `add_path`. No architecture
or group is repeated on those calls. `resolve(ctx)` uses the default group.
Resolution chooses the runner for the executor, independently of the rule's
target platform. A fixed-CPU payload needs a compatible runtime, not necessarily
a matching executor CPU. Use an execution constraint when you require a specific
executor, for example to avoid translation or accommodate a single-CPU Wine build.
The payload's `target_compatible_with` does not select the consumer's executor.

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

## Paths and optional path mapping

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

