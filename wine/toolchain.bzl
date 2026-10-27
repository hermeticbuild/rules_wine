"""Windows runner providers and user-authored toolchain implementation."""

load("//wine/private:cpu.bzl", "guest_cpu")

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
    "Execution contract for Windows guests on a native runtime.",
    fields = {
        "supported_guest_cpus": "Supported Windows CPUs, normalized to x86_64/aarch64.",
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
        supported_guest_cpus = [guest_cpu(cpu.label) for cpu in ctx.attr.supported_guest_cpus],
        backend = ctx.attr.backend,
        launcher = launcher.files_to_run if launcher else None,
        runtime = runtime,
        runfiles = launcher.default_runfiles.merge_all([launcher.data_runfiles]) if launcher else ctx.runfiles(),
    )
    return [info, platform_common.ToolchainInfo(windows = info)] + ([runtime] if runtime else [])

windows_runner_toolchain = rule(
    implementation = _impl,
    attrs = {
        "supported_guest_cpus": attr.label_list(mandatory = True, allow_empty = False, providers = [platform_common.ConstraintValueInfo]),
        "backend": attr.string(mandatory = True, values = ["native", "wine"]),
        "launcher": attr.label(executable = True, cfg = "exec"),
        "loader": attr.label(allow_single_file = True, cfg = "exec"),
        "server": attr.label(allow_single_file = True, cfg = "exec"),
        "files": attr.label(cfg = "exec"),
        "identity": attr.string(),
        "requirements": attr.string(),
        "env": attr.string_dict(),
    },
)
