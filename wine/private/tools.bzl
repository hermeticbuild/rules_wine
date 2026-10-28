"""Shared native compiler arguments; keep directory paths lazy for path mapping."""

TOOLS_TOOLCHAIN = Label("//wine:tools_toolchain_type")

def _dirname(file):
    return file.dirname

def include_args(ctx, args, tools, files, output):
    """Disable host includes and add directories of declared compiler inputs.

    Args:
        ctx: Generating rule context with package-relative includes.
        args: Action Args receiving deferred include paths.
        tools: Selected WineToolsInfo.
        files: Declared source, header, import and asset Files.
        output: Action output File providing its mapped generated root.
    """
    args.add("--nostdinc")
    args.add_all(files + [tools.include], map_each = _dirname, format_each = "-I%s", uniquify = True)
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

    args.add_all([output], map_each = generated_roots, allow_closure = True, format_each = "-I%s")

def nls_args(args, tools):
    """Use the distribution's declared NLS data on Unix."""
    if tools.nls:
        args.add_all([tools.nls], map_each = _dirname, format_each = "--nls-dir=%s")

def typelib_args(args, files):
    """Search only explicitly supplied typelib directories with --nostdinc."""
    args.add_all(files, map_each = _dirname, format_each = "-L%s", uniquify = True)

def preprocessor_args(args, defines):
    """Add caller preprocessor definitions."""
    args.add_all(defines, format_each = "-D%s")
