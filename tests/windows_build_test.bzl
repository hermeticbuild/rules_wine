"""Compile the RPC fixture for a Windows ABI; keep the test executable native."""

def _windows_impl(_settings, attr):
    return {"//command_line_option:platforms": [str(attr.platform)]}

_windows = transition(
    implementation = _windows_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(executable, "#!/bin/sh\nexit 0\n", is_executable = True)
    return [DefaultInfo(executable = executable, runfiles = ctx.runfiles(files = ctx.files.library))]

windows_build_test = rule(
    implementation = _impl,
    test = True,
    attrs = {
        "library": attr.label(mandatory = True, cfg = _windows),
        "platform": attr.label(mandatory = True),
        "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
    },
    exec_groups = {"test": exec_group(exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"])},
)
