"""Forward native tool executables without relocating their installation."""

load("@hermetic_launcher//launcher:lib.bzl", "launcher")

# A tool dependency targets its consumer's executor; finalization has its own.
_TOOLCHAIN = Label("//wine:tools_executable_toolchain_type")

def _impl(ctx):
    info = ctx.toolchains[_TOOLCHAIN].wine_tools
    tool = getattr(info, ctx.attr.tool)
    suffix = ".exe" if ctx.target_platform_has_constraint(ctx.attr._windows[platform_common.ConstraintValueInfo]) else ""
    executable = ctx.actions.declare_file(ctx.label.name + suffix)
    launcher.entrypoint(tool.executable).compile(ctx, output_file = executable)
    return [DefaultInfo(
        executable = executable,
        files = depset([executable]),
        runfiles = ctx.runfiles(transitive_files = info.files).merge(info.runfiles[ctx.attr.tool]),
    )]

wine_tool_binary = rule(
    implementation = _impl,
    executable = True,
    attrs = {
        "tool": attr.string(mandatory = True, values = ["wmc", "wrc", "widl"]),
        "_windows": attr.label(default = "@platforms//os:windows"),
    },
    toolchains = [_TOOLCHAIN, launcher.template_toolchain_type, launcher.finalizer_toolchain_type],
)
