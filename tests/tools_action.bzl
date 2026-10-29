"""Consumers exercise default execution, additional FTR tools and File inputs."""

load("//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    runner = windows_actions.resolve(ctx, exec_group = ctx.attr._exec_group)
    arguments = ctx.actions.args()
    arguments.add("--output")
    windows_actions.add_path(runner, arguments, output)
    kwargs = {}
    if ctx.attr.additional_tools:
        extra = ctx.attr.extra[DefaultInfo]
        windows_actions.add_path(runner, arguments, ctx.file.extra_data, format = "@%s")
        kwargs["tools"] = [extra.files_to_run]

        # A directly addressed File is an input. FTR runfiles have their own
        # logical layout and do not imply this execroot path is materialized.
        kwargs["runtime_files"] = [ctx.file.extra_data]
    windows_actions.run(
        ctx,
        runner = runner,
        executable = ctx.file.binary,
        arguments = [arguments],
        outputs = [output],
        **kwargs
    )
    return [DefaultInfo(files = depset([output]))]

def _attrs(group):
    cfg = "exec" if group == "default" else config.exec(group)
    return {
        "binary": attr.label(allow_single_file = True, cfg = cfg, mandatory = True),
        "extra": attr.label(executable = True, cfg = cfg),
        "extra_data": attr.label(allow_single_file = True, cfg = cfg, default = "//tests:fixture/data café.txt"),
        "additional_tools": attr.bool(),
        "_exec_group": attr.string(default = group),
    }

tools_action = rule(
    implementation = _impl,
    attrs = _attrs("windows"),
    exec_groups = {
        "windows": exec_group(
            toolchains = [windows_actions.toolchain_type],
            exec_compatible_with = ["@platforms//cpu:x86_64"],
        ),
    },
)

default_tools_action = rule(
    implementation = _impl,
    attrs = _attrs("default"),
    toolchains = [windows_actions.toolchain_type],
    exec_compatible_with = ["@platforms//cpu:x86_64"],
)
