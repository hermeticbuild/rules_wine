"""Native Wine developer tools, independent of Windows program execution."""

WineToolsInfo = provider(
    "Native wmc, wrc and widl with their declared compiler input data.",
    fields = {
        "wmc": "Native message compiler FilesToRunProvider, preserving executable runfiles.",
        "wrc": "Native resource compiler FilesToRunProvider, preserving executable runfiles.",
        "widl": "Native IDL compiler FilesToRunProvider, preserving executable runfiles.",
        "files": "Complete tools distribution depset, preserving installation layout.",
        "include": "A header File whose parent is the bundled include directory.",
        "nls": "locale.nls File, or None for native Windows tools.",
        "typelibs": "Target CPU to bundled stdole2.tlb File dictionary.",
    },
)

def _impl(ctx):
    info = WineToolsInfo(
        wmc = ctx.attr.wmc[DefaultInfo].files_to_run,
        wrc = ctx.attr.wrc[DefaultInfo].files_to_run,
        widl = ctx.attr.widl[DefaultInfo].files_to_run,
        files = depset(
            [ctx.executable.wmc, ctx.executable.wrc, ctx.executable.widl, ctx.file.include, ctx.file.x86_64_typelib, ctx.file.aarch64_typelib] + ([ctx.file.nls] if ctx.file.nls else []),
            transitive = [ctx.attr.files[DefaultInfo].files],
        ),
        include = ctx.file.include,
        nls = ctx.file.nls,
        typelibs = {"x86_64": ctx.file.x86_64_typelib, "aarch64": ctx.file.aarch64_typelib},
    )
    return [info, platform_common.ToolchainInfo(wine_tools = info)]

wine_tools_toolchain = rule(
    implementation = _impl,
    doc = """Define a native Wine tools distribution.

Wrap this implementation in a native toolchain declaration using
@rules_wine//wine:tools_toolchain_type and executor OS/CPU constraints. All three
executables must run directly on that executor. No Wine runner is used.
Supply the complete distribution in files, preserving its relative paths.
The headers are compiler inputs, not a C/C++ Windows SDK.
""",
    attrs = {
        "wmc": attr.label(executable = True, allow_single_file = True, cfg = "exec", mandatory = True, doc = "Native wmc executable."),
        "wrc": attr.label(executable = True, allow_single_file = True, cfg = "exec", mandatory = True, doc = "Native wrc executable."),
        "widl": attr.label(executable = True, allow_single_file = True, cfg = "exec", mandatory = True, doc = "Native widl executable."),
        "files": attr.label(cfg = "exec", mandatory = True, doc = "All tools distribution files, including headers, IDLs, typelibs and Unix NLS data."),
        "include": attr.label(allow_single_file = True, cfg = "exec", mandatory = True, doc = "Header directly inside the distribution's include/wine/windows directory, normally windows.h."),
        "nls": attr.label(allow_single_file = True, cfg = "exec", doc = "Bundled share/wine/nls/locale.nls. Omit for native Windows tools."),
        "x86_64_typelib": attr.label(allow_single_file = [".tlb"], cfg = "exec", mandatory = True, doc = "Bundled lib/wine/x86_64-windows/stdole2.tlb."),
        "aarch64_typelib": attr.label(allow_single_file = [".tlb"], cfg = "exec", mandatory = True, doc = "Bundled lib/wine/aarch64-windows/stdole2.tlb."),
    },
)
