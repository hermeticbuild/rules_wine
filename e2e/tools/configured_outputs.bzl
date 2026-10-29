"""Keep artifact checkers native while generating both Windows output ABIs."""

def _platform_impl(_settings, attr):
    return {"//command_line_option:platforms": [str(attr.platform)]}

_platform = transition(
    implementation = _platform_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _impl(ctx):
    named = {"messages.h": ctx.outputs.header, "example_p.c": ctx.outputs.proxy, "rpc_c.c": ctx.outputs.client}
    files = []
    for file in ctx.files.src:
        relative = file.short_path
        if relative.startswith("../"):
            relative = relative.split("/", 2)[2]
        output = named.get(relative) or ctx.actions.declare_file(ctx.label.name + "/" + relative)
        ctx.actions.symlink(output = output, target_file = file)
        files.append(output)
    return [DefaultInfo(files = depset(files))]

configured_outputs = rule(
    implementation = _impl,
    attrs = {
        "src": attr.label(mandatory = True, cfg = _platform),
        "platform": attr.label(mandatory = True),
        "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
    },
    outputs = {"header": "%{name}/messages.h", "proxy": "%{name}/example_p.c", "client": "%{name}/rpc_c.c"},
)
