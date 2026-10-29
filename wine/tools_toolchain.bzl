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
        "runfiles": "Tool name to executable runfiles dictionary.",
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
        runfiles = {
            name: getattr(ctx.attr, name)[DefaultInfo].default_runfiles.merge(getattr(ctx.attr, name)[DefaultInfo].data_runfiles)
            for name in ["wmc", "wrc", "widl"]
        },
    )
    return [
        info,
        platform_common.ToolchainInfo(wine_tools = info),
        platform_common.TemplateVariableInfo({
            "WINE_WMC": info.wmc.executable.path,
            "WINE_WRC": info.wrc.executable.path,
            "WINE_WIDL": info.widl.executable.path,
        }),
        DefaultInfo(files = info.files),
    ]

def _attrs(cfg):
    return {
        "wmc": attr.label(executable = True, allow_single_file = True, cfg = cfg, mandatory = True, doc = "Native wmc executable."),
        "wrc": attr.label(executable = True, allow_single_file = True, cfg = cfg, mandatory = True, doc = "Native wrc executable."),
        "widl": attr.label(executable = True, allow_single_file = True, cfg = cfg, mandatory = True, doc = "Native widl executable."),
        "files": attr.label(cfg = cfg, mandatory = True, doc = "All tools distribution files, including headers, IDLs, typelibs and Unix NLS data."),
        "include": attr.label(allow_single_file = True, cfg = cfg, mandatory = True, doc = "Header directly inside the distribution's include/wine/windows directory, normally windows.h."),
        "nls": attr.label(allow_single_file = True, cfg = cfg, doc = "Bundled share/wine/nls/locale.nls. Omit for native Windows tools."),
        "x86_64_typelib": attr.label(allow_single_file = [".tlb"], cfg = cfg, mandatory = True, doc = "Bundled lib/wine/x86_64-windows/stdole2.tlb."),
        "aarch64_typelib": attr.label(allow_single_file = [".tlb"], cfg = cfg, mandatory = True, doc = "Bundled lib/wine/aarch64-windows/stdole2.tlb."),
    }

wine_tools_toolchain = rule(
    implementation = _impl,
    doc = """Define a native Wine tools distribution.

Wrap this implementation in a native toolchain declaration using
@rules_wine//wine:tools_toolchain_type and executor OS/CPU constraints. All three
executables must run directly on that executor. No Wine runner is used.
Supply the complete distribution in files, preserving its relative paths.
The headers are compiler inputs, not a C/C++ Windows SDK.

Resolved genrules can use WINE_WMC, WINE_WRC and WINE_WIDL make variables.
Each is a raw executable path without flags; quote it in shell commands.
DefaultInfo supplies the complete distribution. Custom executables that need
runfiles must also appear in genrule.tools to materialize those runfiles.
""",
    attrs = _attrs("exec"),
)

wine_tools_executable_toolchain = rule(
    implementation = _impl,
    doc = """Define tools for the wmc, wrc and widl executable labels.

Wrap with a native toolchain declaration using
@rules_wine//wine:tools_executable_toolchain_type and target_compatible_with
constraints describing where these executables run. Dependencies remain in the
configured target platform, which is the consuming action's executor when used
as a tool. Use wine_tools_toolchain separately for generation rules and genrules.
""",
    attrs = _attrs("target"),
)
