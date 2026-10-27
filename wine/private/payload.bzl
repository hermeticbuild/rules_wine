"""Windows compilation transition; never transitions the final output platform."""

load("//wine:windows_import.bzl", "target_executable_info")
load(":cpu.bzl", "check_guest")

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
        "binary": attr.label(allow_files = True, mandatory = True, cfg = payload_transition),
        "target_platform": attr.label(
            providers = [platform_common.PlatformInfo],
            doc = "Windows platform for payload compilation; defaults to the wrapper CPU.",
        ),
        "_payload_platform": attr.label(default = Label("//wine/private:payload_platform"), cfg = payload_transition),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    }

def payload(ctx, runner):
    """Resolve the original executable and validate only explicit CPU metadata."""
    platform = ctx.attr._payload_platform[0][PayloadPlatformInfo]
    if not platform.windows or platform.arch == "unsupported":
        fail("target_platform must be Windows with x86_64 or aarch64 CPU; got Windows={} CPU={}".format(platform.windows, platform.arch))
    binary = target_executable_info(ctx, ctx.attr.binary[0])
    check_guest(binary, runner)
    return binary
