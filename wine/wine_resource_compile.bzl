"""Compile Windows resources with native wrc."""

load("//wine/private:tools.bzl", "TOOLS_TOOLCHAIN", "include_args", "nls_args", "preprocessor_args")

def _impl(ctx):
    tools = ctx.toolchains[TOOLS_TOOLCHAIN].wine_tools
    inputs = [ctx.file.src] + ctx.files.hdrs + ctx.files.data
    args = ctx.actions.args()
    args.add_all(["-u", "-O", "res"])
    include_args(args, tools, inputs)
    nls_args(args, tools)
    preprocessor_args(args, ctx.attr.defines)
    args.add("-o", ctx.outputs.out)
    args.add(ctx.file.src)
    ctx.actions.run(
        executable = tools.wrc,
        arguments = [args],
        inputs = depset(inputs, transitive = [tools.files]),
        outputs = [ctx.outputs.out],
        toolchain = TOOLS_TOOLCHAIN,
        mnemonic = "WineResourceCompile",
    )
    return [DefaultInfo(files = depset([ctx.outputs.out]))]

wine_resource_compile = rule(
    implementation = _impl,
    doc = """Compile UTF-8 RC source to a binary RES file without a host SDK.

Declare every included header and resource asset in hdrs and data. Their parent
directories and the bundled Wine headers form the include search path. Generated
files work as ordinary output labels. No C/C++ compilation or linking is added.
Upstream __DATE__ and __TIME__ expand to wall-clock time; avoid them in cached builds.
""",
    attrs = {
        "src": attr.label(allow_single_file = [".rc"], mandatory = True, doc = "UTF-8 resource script."),
        "hdrs": attr.label_list(allow_files = True, doc = "Declared included headers; each parent directory is searched."),
        "data": attr.label_list(allow_files = True, doc = "Declared resource assets; each parent directory is searched."),
        "defines": attr.string_list(doc = "Preprocessor definitions, NAME or NAME=VALUE."),
        "out": attr.output(mandatory = True, doc = "Binary .res output."),
    },
    toolchains = [TOOLS_TOOLCHAIN],
)
