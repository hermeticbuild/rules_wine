"""Generate explicitly selected IDL outputs with native widl."""

load("//wine/private:tools.bzl", "TOOLS_TOOLCHAIN", "include_args", "preprocessor_args", "typelib_args")

_KINDS = {"header": "-h", "typelib": "-t", "client": "-c", "server": "-s", "proxy": "-p", "iid": "-u"}

def _impl(ctx):
    tools = ctx.toolchains[TOOLS_TOOLCHAIN].wine_tools
    if ctx.target_platform_has_constraint(ctx.attr._x86_64[platform_common.ConstraintValueInfo]):
        cpu = "x86_64"
    elif ctx.target_platform_has_constraint(ctx.attr._aarch64[platform_common.ConstraintValueInfo]):
        cpu = "aarch64"
    else:
        fail("wine_idl_compile supports target CPUs x86_64 and aarch64")
    outputs = []
    inputs = [ctx.file.src] + ctx.files.imports
    for kind, flag in _KINDS.items():
        output = getattr(ctx.outputs, kind)
        if not output:
            continue
        outputs.append(output)
        args = ctx.actions.args()
        args.add_all(["-b", cpu + "-w64-mingw32", "-Oif", flag])
        include_args(ctx, args, tools, inputs, output)
        typelib_args(args, [file for file in ctx.files.imports if file.extension == "tlb"] + [tools.typelibs[cpu]])
        preprocessor_args(args, ctx.attr.defines)
        if kind != "header" and ctx.outputs.header:
            args.add("-H", ctx.outputs.header.basename)
        args.add("-o", output)
        args.add(ctx.file.src)
        ctx.actions.run(
            executable = tools.widl,
            arguments = [args],
            inputs = depset(inputs, transitive = [tools.files]),
            outputs = [output],
            toolchain = TOOLS_TOOLCHAIN,
            mnemonic = "WineIdlCompile",
        )
    if not outputs:
        fail("select at least one IDL output: " + ", ".join(_KINDS))
    return [DefaultInfo(files = depset(outputs))]

wine_idl_compile = rule(
    implementation = _impl,
    doc = """Generate selected headers, type libraries or C source files from IDL.

The configured target CPU selects the Windows output ABI (x86_64 or aarch64),
independently of the executor CPU. Every output is an explicit output label;
select at least one. Declare imported IDLs, headers and typelibs in imports.
Bundled Wine IDLs and the matching stdole2.tlb are available without a host SDK.
Generated C uses interpreter stubs (-Oif) and includes the selected header's basename, or the input basename.h if
header is omitted. Consumers own include paths, C compilation and linking.
Upstream __DATE__ and __TIME__ expand to wall-clock time; avoid them in cached builds.
""",
    attrs = {
        "src": attr.label(allow_single_file = [".idl"], mandatory = True, doc = "IDL source."),
        "imports": attr.label_list(allow_files = [".idl", ".h", ".tlb"], doc = "Imported IDLs, headers and type libraries; each parent directory is searched."),
        "defines": attr.string_list(doc = "Preprocessor definitions, NAME or NAME=VALUE."),
        "includes": attr.string_list(doc = "Additional package-relative include directories, searched in both source and generated output roots. Imported inputs must still be declared in imports."),
        "header": attr.output(doc = "Generated header (-h)."),
        "typelib": attr.output(doc = "Generated type library (-t)."),
        "client": attr.output(doc = "Generated client C stub (-c)."),
        "server": attr.output(doc = "Generated server C stub (-s)."),
        "proxy": attr.output(doc = "Generated proxy C source (-p)."),
        "iid": attr.output(doc = "Generated interface identifiers C source (-u)."),
        "_x86_64": attr.label(default = "@platforms//cpu:x86_64"),
        "_aarch64": attr.label(default = "@platforms//cpu:aarch64"),
    },
    toolchains = [TOOLS_TOOLCHAIN],
)
