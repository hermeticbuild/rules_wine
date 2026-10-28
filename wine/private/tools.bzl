"""Shared native compiler arguments; keep directory paths lazy for path mapping."""

TOOLS_TOOLCHAIN = Label("//wine:tools_toolchain_type")

def _dirname(file):
    return file.dirname

def include_args(args, tools, files):
    """Disable host includes and add directories of declared compiler inputs."""
    args.add("--nostdinc")
    args.add_all(files + [tools.include], map_each = _dirname, format_each = "-I%s", uniquify = True)

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
