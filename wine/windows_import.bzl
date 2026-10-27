"""Optional Windows executable metadata; preserves the original executable path."""

load("//wine/private:cpu.bzl", "guest_cpu")

WindowsExecutableInfo = provider(
    "Optional executable contract, with original artifacts and runfiles.",
    fields = {
        "executable": "Original File or FilesToRunProvider.",
        "file": "Original executable File (never a relocating symlink).",
        "guest_cpu": "Declared x86_64/aarch64 guest, or None when undeclared.",
        "files": "Executable and companion input depset.",
        "runfiles": "Merged original and companion runfiles.",
        "run_environment": "Original RunEnvironmentInfo, when present.",
    },
)

def executable_info(ctx, executable):
    """Normalize a File, FilesToRunProvider, or Target immediately."""
    kind = type(executable)
    if kind == "File":
        file = executable
    elif kind == "FilesToRunProvider":
        file = executable.executable
        if file == None:
            fail("expected an executable FilesToRunProvider")
    elif kind == "Target":
        return target_executable_info(ctx, executable)
    else:
        fail("expected File, FilesToRunProvider, or Target; got {}".format(kind))
    return WindowsExecutableInfo(
        executable = executable,
        file = file,
        guest_cpu = None,
        files = depset([file]),
        runfiles = ctx.runfiles(files = [file]),
        run_environment = None,
    )

def target_executable_info(ctx, target):
    """Normalize a metadata target, ordinary executable target, or single file."""
    if WindowsExecutableInfo in target:
        return target[WindowsExecutableInfo]
    info = target[DefaultInfo]
    executable = info.files_to_run
    if executable.executable == None:
        files = info.files.to_list()
        if len(files) != 1:
            fail("{} must provide an executable, a single file, or WindowsExecutableInfo".format(target.label))
        executable = files[0]
    normalized = executable_info(ctx, executable)
    return WindowsExecutableInfo(
        executable = executable,
        file = normalized.file,
        guest_cpu = None,
        files = depset([normalized.file], transitive = [info.files]),
        runfiles = normalized.runfiles.merge(ctx.runfiles(transitive_files = info.files)).merge_all([info.default_runfiles, info.data_runfiles]),
        run_environment = target[RunEnvironmentInfo] if RunEnvironmentInfo in target else None,
    )

def _impl(ctx):
    original = target_executable_info(ctx, ctx.attr.executable)
    declared = guest_cpu(ctx.attr.guest_cpu.label)
    if original.guest_cpu and original.guest_cpu != declared:
        fail("cannot change declared guest CPU {} to {}".format(original.guest_cpu, declared))
    files = depset(ctx.files.data, transitive = [original.files])
    runfiles = original.runfiles.merge(ctx.runfiles(transitive_files = files))
    return [WindowsExecutableInfo(
        executable = original.executable,
        file = original.file,
        guest_cpu = declared,
        files = depset(transitive = [files, runfiles.files]),
        runfiles = runfiles,
        run_environment = original.run_environment,
    )]

windows_import = rule(
    implementation = _impl,
    attrs = {
        "executable": attr.label(allow_files = True, mandatory = True),
        "guest_cpu": attr.label(mandatory = True, providers = [platform_common.ConstraintValueInfo]),
        "data": attr.label_list(allow_files = True, doc = "Companion default-output files at original paths; does not import dependency runfiles or augment the original executable runfiles tree."),
    },
    doc = "Provider-only metadata; data retains its artifact paths and does not relocate adjacent DLLs.",
)
