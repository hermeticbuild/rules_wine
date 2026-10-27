"""Low-level Windows actions using one resolved execution-group context."""

load("//wine:windows_import.bzl", "executable_info")
load("//wine/private:cpu.bzl", "check_guest")

_TOOLCHAIN_TYPE = Label("//wine:runner_toolchain_type")

def wine_path(file):
    """Args.map_each callback for Wine-only executable adapter consumers.

    Pass this function to Args.add_all; do not call it during analysis.
    For runner-based actions, use windows_actions.add_path instead.

    Args:
        file: File supplied by Args during command-line expansion.

    Returns:
        A JSON-escaped Wine path marker containing the action-mapped path.
    """
    return "{windows_path:" + json.encode(file.path) + "}"

def _resolve(ctx, *, exec_group = "default"):
    """Bind a runner to the execution group declaring its toolchain type.

    Args:
        ctx: The consuming rule context.
        exec_group: Group declaring windows_actions.toolchain_type.

    Returns:
        Context for run/add_path, containing WindowsRunnerInfo as windows and the
        action's exec_group. Capabilities do not select a different executor.
    """
    toolchains = ctx.toolchains if exec_group == "default" else ctx.exec_groups[exec_group].toolchains
    return struct(
        windows = toolchains[_TOOLCHAIN_TYPE].windows,
        exec_group = None if exec_group == "default" else exec_group,
    )

def _add_path(runner, args, file, format = "%s"):
    """Append a File path, deferring mapping and Wine encoding until execution.

    Use this for command-line arguments, not markers inside payload response
    files. Tree artifacts are passed as directory paths rather than expanded.

    Args:
        runner: Context returned by windows_actions.resolve.
        args: Args object receiving the argument.
        file: File or tree artifact. Pass ordinary strings with Args.add instead.
        format: Surrounding option syntax, e.g. /out:%s.
    """
    args.add_all(
        [file],
        map_each = wine_path if runner.windows.backend == "wine" else None,
        format_each = format,
        expand_directories = False,
    )

def _configuration(record):
    # Called by Args under the consuming action's path mapper. Never serialize
    # execution paths in a separate write action: its mapping can differ.
    return json.encode({
        "supported_guest_cpus": record.supported_guest_cpus,
        "declared_guest_cpu": record.declared_guest_cpu,
        "loader": record.loader.path,
        "server": record.server.path,
        "payload": record.payload.path,
        "env": record.env,
        "runtime_env": record.runtime_env,
    })

def _run(
        ctx,
        *,
        runner,
        executable,
        outputs,
        arguments = [],
        inputs = [],
        env = {},
        runtime_files = [],
        tools = [],
        mnemonic = "WindowsRun",
        progress_message = None,
        **kwargs):
    action_group = runner.exec_group
    runner = runner.windows
    binary = executable_info(ctx, executable)
    check_guest(binary, runner)
    executable = binary.executable
    payload = binary.file
    input_set = depset(transitive = [inputs if type(inputs) == "depset" else depset(inputs), binary.files, binary.runfiles.files])

    # The wrapped executable remains a tool when the supervisor replaces it.
    # Lists can carry FilesToRunProvider; depsets carry Files.
    if type(tools) == "depset" and type(executable) == "File":
        tools = depset([executable], transitive = [tools])
    else:
        tools = [executable] + (tools.to_list() if type(tools) == "depset" else tools)
    if runner.backend == "native":
        # No process adapter for Windows actions. Explicit path markers are not
        # needed on Windows; use Args.add(File) for platform-neutral arguments.
        ctx.actions.run(
            executable = executable,
            arguments = arguments,
            inputs = depset(runtime_files, transitive = [input_set]),
            outputs = outputs,
            env = env,
            tools = tools,
            exec_group = action_group,
            toolchain = _TOOLCHAIN_TYPE,
            mnemonic = mnemonic,
            progress_message = progress_message,
            **kwargs
        )
        return

    config = ctx.actions.args()
    config.add_all([struct(
        supported_guest_cpus = runner.supported_guest_cpus,
        declared_guest_cpu = binary.guest_cpu,
        loader = runner.runtime.loader,
        server = runner.runtime.server,
        payload = payload,
        env = env,
        runtime_env = runner.runtime.env,
    )], map_each = _configuration)
    config.set_param_file_format("multiline")
    config.use_param_file("%s", use_always = True)
    ctx.actions.run(
        executable = runner.launcher,
        arguments = ["--config", config, "--"] + arguments,
        inputs = depset([payload] + runtime_files, transitive = [input_set, runner.runtime.files]),
        outputs = outputs,
        # These describe the Windows payload. A custom native launcher must
        # discover its own FilesToRunProvider runfiles before starting it.
        env = {
            key: value
            for key, value in env.items()
            if key not in ["RUNFILES_DIR", "RUNFILES_MANIFEST_FILE", "RUNFILES_MANIFEST_ONLY"]
        },
        tools = tools,
        exec_group = action_group,
        toolchain = _TOOLCHAIN_TYPE,
        mnemonic = mnemonic,
        progress_message = progress_message,
        **kwargs
    )

windows_actions = struct(run = _run, add_path = _add_path, resolve = _resolve, toolchain_type = _TOOLCHAIN_TYPE)
