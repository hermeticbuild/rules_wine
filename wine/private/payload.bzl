"""Optional compilation transition; never transitions the final output platform."""

PayloadPlatformInfo = provider(
    "Platform facts in the payload's optional compilation configuration.",
    fields = ["windows", "arch"],
)

def _transition_impl(settings, attr):
    platforms = [str(attr.target_platform)] if attr.target_platform else settings["//command_line_option:platforms"]
    return {"//command_line_option:platforms": platforms}

payload_transition = transition(
    implementation = _transition_impl,
    inputs = ["//command_line_option:platforms"],
    outputs = ["//command_line_option:platforms"],
)

def _check(ctx):
    arch = "unsupported"
    if ctx.target_platform_has_constraint(ctx.attr._x86[platform_common.ConstraintValueInfo]):
        arch = "x86_64"
    elif ctx.target_platform_has_constraint(ctx.attr._arm[platform_common.ConstraintValueInfo]):
        arch = "aarch64"
    return [PayloadPlatformInfo(
        windows = ctx.target_platform_has_constraint(ctx.attr._windows[platform_common.ConstraintValueInfo]),
        arch = arch,
    )]

payload_platform = rule(
    implementation = _check,
    attrs = {
        "_windows": attr.label(default = "@platforms//os:windows"),
        "_x86": attr.label(default = "@platforms//cpu:x86_64"),
        "_arm": attr.label(default = "@platforms//cpu:aarch64"),
    },
)

def payload_attrs():
    return {
        "binary": attr.label(
            executable = True,
            allow_files = True,
            mandatory = True,
            cfg = payload_transition,
            doc = "Windows executable file or executable target; its runfiles are included in the wrapper.",
        ),
        "target_platform": attr.label(
            providers = [platform_common.PlatformInfo],
            doc = "Optional Windows compilation platform for binary. Its CPU must match the wrapper's CPU; omit for prebuilts.",
        ),
        "_payload_platform": attr.label(default = Label("//wine/private:payload_platform"), cfg = payload_transition),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    }

def payload(ctx, arch):
    """Resolve a PE executable and preserve its runfiles.

    Args:
        ctx: Consuming rule context with payload_attrs.
        arch: Declared payload CPU to validate after an optional transition.

    Returns:
        Executable File and merged runfiles in a struct.
    """
    target = ctx.attr.binary[0]
    if ctx.attr.target_platform:
        platform = ctx.attr._payload_platform[0][PayloadPlatformInfo]
        if not platform.windows or platform.arch != arch:
            fail("target_platform must be Windows/{}; got Windows={} CPU={}".format(
                arch,
                platform.windows,
                platform.arch,
            ))
    info = target[DefaultInfo]
    executable = info.files_to_run.executable
    runfiles = ctx.runfiles(
        transitive_files = depset([executable], transitive = [info.files]),
    ).merge_all([info.default_runfiles, info.data_runfiles])
    return struct(
        file = executable,
        runfiles = runfiles,
        run_environment = target[RunEnvironmentInfo] if RunEnvironmentInfo in target else None,
    )
