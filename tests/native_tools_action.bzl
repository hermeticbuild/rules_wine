"""Exercise a custom native compiler target's executable runfiles contract."""

load("//wine:tools_toolchain.bzl", "WineToolsInfo")

def _impl(ctx):
    tools = ctx.attr.implementation[WineToolsInfo]
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    args = ctx.actions.args()
    args.add(output)
    ctx.actions.run(
        executable = tools.wrc,
        arguments = [args],
        inputs = tools.files,
        outputs = [output],
        mnemonic = "NativeToolsRunfiles",
    )
    return [DefaultInfo(files = depset([output]))]

native_tools_runfiles = rule(
    implementation = _impl,
    attrs = {
        "implementation": attr.label(mandatory = True, providers = [WineToolsInfo], cfg = "exec"),
    },
)
