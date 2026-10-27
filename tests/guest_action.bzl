"""Exercise typed payloads through the public action API."""

load("//wine:actions.bzl", "windows_actions")
load("//wine:windows_import.bzl", "WindowsExecutableInfo")

def _impl(ctx):
    runner = windows_actions.resolve(ctx)
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    args = ctx.actions.args()
    args.add_all(ctx.attr.arguments)
    args.add("--output")
    windows_actions.add_path(runner, args, output)
    windows_actions.run(
        ctx,
        runner = runner,
        executable = ctx.attr.tool,
        arguments = [args],
        outputs = [output],
    )
    return [DefaultInfo(files = depset([output]))]

guest_action = rule(
    implementation = _impl,
    attrs = {
        "tool": attr.label(providers = [WindowsExecutableInfo], mandatory = True),
        "arguments": attr.string_list(),
    },
    toolchains = [windows_actions.toolchain_type],
)
