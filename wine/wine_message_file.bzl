"""Compile message definitions with native wmc."""

_TOOLS_TOOLCHAIN = Label("//wine:tools_toolchain_type")

def _dirname(file):
    return file.dirname

def _outputs(name, output_format, header):
    return {"default_header": name + ".h"} if output_format == "rc" and not header else {}

def _impl(ctx):
    tools = ctx.toolchains[_TOOLS_TOOLCHAIN].wine_tools
    args = ctx.actions.args()
    args.add_all(["-O", ctx.attr.output_format, "-U"])
    if ctx.attr.unicode:
        args.add("-u")
    outputs = [ctx.outputs.out]
    if ctx.attr.output_format == "rc":
        header = ctx.outputs.header or ctx.outputs.default_header
        args.add("-i")
        args.add("-H", header)
        outputs.append(header)
    elif ctx.outputs.header:
        fail("wmc res mode does not emit a header; omit header or use output_format = rc")
    if tools.nls:
        args.add_all([tools.nls], map_each = _dirname, format_each = "--nls-dir=%s")
    args.add("-o", ctx.outputs.out)
    args.add(ctx.file.src)
    ctx.actions.run(
        executable = tools.wmc,
        arguments = [args],
        inputs = depset([ctx.file.src], transitive = [tools.files]),
        outputs = outputs,
        toolchain = _TOOLS_TOOLCHAIN,
        mnemonic = "WineMessageCompile",
    )
    return [DefaultInfo(files = depset(outputs))]

wine_message_file = rule(
    implementation = _impl,
    doc = """Compile a message table to RC plus header, or directly to RES.

The default rc mode emits out and an implicit name.h output label. Message
tables are inline (-i), so no content-dependent .bin files are written. The res
mode emits only out: upstream wmc does not generate a header in that mode.
Message tables use Unicode output (-U). Input defaults to the source codepage;
set unicode for UTF-16 input (-u), not UTF-8.
""",
    attrs = {
        "src": attr.label(allow_single_file = [".mc"], mandatory = True, doc = "Message definitions."),
        "out": attr.output(mandatory = True, doc = "Output RC or RES file, matching output_format."),
        "header": attr.output(doc = "RC mode header output; defaults to name.h. Not available in res mode."),
        "output_format": attr.string(default = "rc", values = ["rc", "res"], doc = "rc emits a header and inline RC; res emits only a binary resource."),
        "unicode": attr.bool(doc = "Read UTF-16 input. This is wmc -u, not wrc's UTF-8 option."),
    },
    outputs = _outputs,
    toolchains = [_TOOLS_TOOLCHAIN],
)
