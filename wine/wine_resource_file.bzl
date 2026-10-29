"""Compile Windows resources with native wrc."""

_TOOLS_TOOLCHAIN = Label("//wine:tools_toolchain_type")

def _dirname(file):
    return file.dirname

def _impl(ctx):
    tools = ctx.toolchains[_TOOLS_TOOLCHAIN].wine_tools
    inputs = [ctx.file.src] + ctx.files.hdrs + ctx.files.data
    args = ctx.actions.args()
    args.add_all(["-u", "-O", "res"])
    args.add("--nostdinc")
    args.add_all(inputs + [tools.include], map_each = _dirname, format_each = "-I%s", uniquify = True)
    package = ctx.label.package
    includes = ctx.attr.includes
    workspace_root = ctx.label.workspace_root
    for directory in includes:
        if directory.startswith("/") or (len(directory) > 1 and directory[1] == ":") or "\\" in directory or ".." in directory.split("/"):
            fail("includes entries must be package-relative slash-separated directories without '..': " + directory)
    args.add_all([
        "/".join([part for part in [workspace_root, package, directory] if part]) or "."
        for directory in includes
    ], format_each = "-I%s")

    def generated_roots(file):
        return [
            "/".join([part for part in [file.root.path, workspace_root, package, directory] if part])
            for directory in includes
        ]

    args.add_all([ctx.outputs.out], map_each = generated_roots, allow_closure = True, format_each = "-I%s")
    if tools.nls:
        args.add_all([tools.nls], map_each = _dirname, format_each = "--nls-dir=%s")
    args.add_all(ctx.attr.defines, format_each = "-D%s")
    args.add("-o", ctx.outputs.out)
    args.add(ctx.file.src)
    ctx.actions.run(
        executable = tools.wrc,
        arguments = [args],
        inputs = depset(inputs, transitive = [tools.files]),
        outputs = [ctx.outputs.out],
        toolchain = _TOOLS_TOOLCHAIN,
        mnemonic = "WineResourceCompile",
    )
    return [DefaultInfo(files = depset([ctx.outputs.out]))]

wine_resource_file = rule(
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
        "includes": attr.string_list(doc = "Additional package-relative include directories, searched in both source and generated output roots. Inputs must still be declared in hdrs/data."),
        "out": attr.output(mandatory = True, doc = "Binary .res output."),
    },
    toolchains = [_TOOLS_TOOLCHAIN],
)
