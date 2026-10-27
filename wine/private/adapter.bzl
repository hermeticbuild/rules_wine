"""Implementation of the runfiles-preserving executable adapter."""

load("@hermetic_launcher//launcher:lib.bzl", "launcher")
load(":paths.bzl", "runfile_path")
load(":payload.bzl", "payload")

def adapter_impl(ctx):
    """Produce an executable using the default group's adapter toolchain.

    Args:
        ctx: Executable rule context with payload_attrs.

    Returns:
        DefaultInfo for the native executable and complete runfiles.
    """
    runner = ctx.toolchains[Label("//wine:adapter_toolchain_type")].windows
    if runner.backend != "wine":
        fail("windows_binary requires a Wine adapter toolchain")
    binary = payload(ctx, runner)
    executable = ctx.actions.declare_file(ctx.label.name)
    config = ctx.actions.declare_file(executable.basename + ".json", sibling = executable)
    entrypoint = launcher.entrypoint(runner.launcher.executable)
    entrypoint.embedded_args("--config").runfiles(config).embedded_args("--")
    entrypoint.compile(
        ctx,
        output_file = executable,
        cfg = "exec",
    )
    ctx.actions.write(config, json.encode({
        "supported_guest_cpus": runner.supported_guest_cpus,
        "declared_guest_cpu": binary.guest_cpu,
        "payload": runfile_path(ctx, binary.file),
        "runfiles": True,
        "loader": runfile_path(ctx, runner.runtime.loader),
        "runtime_env": runner.runtime.env,
        "server": runfile_path(ctx, runner.runtime.server),
    }))
    runfiles = ctx.runfiles(
        files = [config, executable, runner.launcher.executable],
        transitive_files = runner.runtime.files,
    ).merge_all([binary.runfiles, runner.runfiles])
    providers = [DefaultInfo(files = depset([executable]), executable = executable, runfiles = runfiles)]
    if binary.run_environment != None:
        providers.append(binary.run_environment)
    return providers
