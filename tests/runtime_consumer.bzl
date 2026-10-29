"""Downstream consumer of Windows actions and executable adapters."""

load("@rules_wine//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    runner = windows_actions.resolve(ctx)
    action_output = ctx.actions.declare_file(ctx.label.name + "/result café.json")
    data = ctx.actions.declare_file(ctx.label.name + "/input café.txt")
    ctx.actions.write(data, "declared input café\n")
    action_args = ctx.actions.args()
    action_args.add("--output")
    windows_actions.add_path(runner, action_args, action_output)
    action_args.add_all(["space value", "", "café", "$literal"])
    windows_actions.add_path(runner, action_args, data, format = "@%s")
    env = {"FIXTURE_VALUE": "environment café"}
    if ctx.attr.adapter:
        ctx.actions.run(
            executable = ctx.attr.adapter[DefaultInfo].files_to_run,
            arguments = [action_args],
            inputs = [data],
            outputs = [action_output],
            env = env,
            mnemonic = "WineAdapterConsumer",
        )
    else:
        windows_actions.run(
            ctx,
            runner = runner,
            executable = ctx.file.binary,
            arguments = [action_args],
            inputs = [data],
            outputs = [action_output],
            env = env,
        )
    return [DefaultInfo(files = depset([action_output]))]

consumer = rule(
    implementation = _impl,
    attrs = {
        "binary": attr.label(allow_single_file = True, cfg = "exec", mandatory = True),
        "adapter": attr.label(executable = True, cfg = "exec"),
    },
    toolchains = [windows_actions.toolchain_type],
)
