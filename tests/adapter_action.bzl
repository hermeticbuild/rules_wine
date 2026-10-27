"""Fixture consumers of executable adapters and source-built Windows tools."""

load("//wine:actions.bzl", "windows_actions", "wine_path")

def _impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    args = ctx.actions.args()
    args.add_all(ctx.attr.arguments)
    args.add("--output")
    args.add_all([output], map_each = wine_path)
    args.add("adapter-tool")
    ctx.actions.run(
        executable = ctx.attr.tool[DefaultInfo].files_to_run,
        arguments = [args],
        outputs = [output],
        mnemonic = "AdapterTool",
    )
    return [DefaultInfo(files = depset([output]))]

adapter_action = rule(
    implementation = _impl,
    attrs = {
        "tool": attr.label(executable = True, cfg = "exec", mandatory = True),
        "arguments": attr.string_list(),
    },
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
)

def _runfiles_adapter_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    args = ctx.actions.args()
    args.add_all([output], map_each = wine_path)
    ctx.actions.run(
        executable = ctx.attr.tool[DefaultInfo].files_to_run,
        arguments = [args],
        outputs = [output],
        mnemonic = "RunfilesAdapterFixture",
    )
    return [DefaultInfo(files = depset([output]))]

runfiles_adapter_action = rule(
    implementation = _runfiles_adapter_impl,
    attrs = {
        "tool": attr.label(executable = True, cfg = "exec", mandatory = True),
    },
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
)

def _runfiles_impl(ctx):
    runner = windows_actions.resolve(ctx)
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    args = ctx.actions.args()
    windows_actions.add_path(runner, args, output)
    windows_actions.run(
        ctx,
        runner = runner,
        executable = ctx.attr.tool[0][DefaultInfo].files_to_run,
        arguments = [args],
        outputs = [output],
        mnemonic = "RunfilesFixture",
    )
    return [DefaultInfo(files = depset([output]))]

def _windows_impl(_settings, _attr):
    return {"//command_line_option:platforms": [str(Label("@llvm//platforms:windows_x86_64"))]}

_windows = transition(
    implementation = _windows_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

runfiles_action = rule(
    implementation = _runfiles_impl,
    attrs = {
        "tool": attr.label(executable = True, cfg = _windows, mandatory = True),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = [windows_actions.toolchain_type],
    exec_compatible_with = ["@platforms//cpu:x86_64"],
)
