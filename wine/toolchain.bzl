"""Windows runner providers and user-authored toolchain implementation."""

WineRuntimeInfo = provider(
    "Immutable Wine distribution built for the selected executor.",
    fields = {
        "loader": "Native Wine ELF/Mach-O loader File; installation layout preserved.",
        "server": "Matching wineserver File.",
        "files": "Complete immutable distribution depset.",
        "identity": "Distribution/version provenance.",
        "requirements": "Host library requirements, not inferred hermeticity.",
        "env": "Distribution loader environment; {loader_dir} and {server_dir} placeholders.",
    },
)
WindowsRunnerInfo = provider(
    "Execution contract for Windows payloads.",
    fields = {
        "arch": "Native executor architecture; Wine may support additional payload CPUs.",
        "backend": "wine or native.",
        "launcher": "Linux/macOS Wine supervisor FilesToRunProvider, or None for direct native actions.",
        "runtime": "WineRuntimeInfo or None.",
        "runfiles": "Complete executor-native launcher runfiles.",
    },
)

def _impl(ctx):
    runtime = None
    if ctx.attr.backend == "wine":
        if not ctx.executable.launcher:
            fail("wine backend requires launcher")
        if not ctx.file.loader or not ctx.file.server:
            fail("wine backend requires loader and server")
        runtime = WineRuntimeInfo(
            loader = ctx.file.loader,
            server = ctx.file.server,
            files = depset(
                [ctx.file.loader, ctx.file.server],
                transitive = [ctx.attr.files[DefaultInfo].files] if ctx.attr.files else [],
            ),
            identity = ctx.attr.identity,
            requirements = ctx.attr.requirements,
            env = ctx.attr.env,
        )
    elif ctx.attr.launcher or ctx.file.loader or ctx.file.server or ctx.attr.files:
        fail("native backend must not depend on a launcher or Wine")
    launcher = ctx.attr.launcher[DefaultInfo] if ctx.attr.launcher else None
    info = WindowsRunnerInfo(
        arch = ctx.attr.arch,
        backend = ctx.attr.backend,
        launcher = launcher.files_to_run if launcher else None,
        runtime = runtime,
        runfiles = launcher.default_runfiles.merge_all([launcher.data_runfiles]) if launcher else ctx.runfiles(),
    )
    return [info, platform_common.ToolchainInfo(windows = info)] + ([runtime] if runtime else [])

windows_runner_toolchain = rule(
    implementation = _impl,
    doc = """Define a Windows runner implementation for native execution or Wine.

Wrap this target in native toolchain declarations with constraints matching the
executor OS/CPU. Use runner_toolchain_type for windows_actions and
adapter_toolchain_type for windows_binary. The adapter registration additionally
constrains the target platform to match the executor.

Wine distributions must preserve their installation layout and include all
runtime files. This rule supplies no CPU emulator itself; guest CPU support is
determined by the supplied Wine distribution. Native runners execute payloads
directly and must omit Wine files and launcher.
""",
    attrs = {
        "arch": attr.string(
            mandatory = True,
            values = ["x86_64", "aarch64"],
            doc = "Executor CPU, matching the registration's platform constraints; not the Windows guest CPU.",
        ),
        "backend": attr.string(
            mandatory = True,
            values = ["native", "wine"],
            doc = "Use native for Windows executors or wine for Linux/macOS executors.",
        ),
        "launcher": attr.label(
            executable = True,
            cfg = "exec",
            doc = "Wine supervisor executable, normally @rules_wine//wine/runtime:supervisor. Required for wine; omit for native.",
        ),
        "loader": attr.label(
            allow_single_file = True,
            cfg = "exec",
            doc = "Native Wine loader file. Required for wine; omit for native.",
        ),
        "server": attr.label(
            allow_single_file = True,
            cfg = "exec",
            doc = "Matching wineserver file. Required for wine; omit for native.",
        ),
        "files": attr.label(
            cfg = "exec",
            doc = "Complete Wine installation files, preserving paths relative to loader/server. Omit for native.",
        ),
        "identity": attr.string(doc = "Distribution/version description exposed through WineRuntimeInfo."),
        "requirements": attr.string(doc = "Host library/OS requirements for consumers to inspect; not enforced by this rule."),
        "env": attr.string_dict(doc = "Wine runtime environment, taking precedence over payload env. {loader_dir} and {server_dir} expand at execution time. Reserved lifecycle variables cannot be set here."),
    },
)
