"""Synthetic executables and alias-only data for graph/configuration checks."""

load("@rules_wine//wine:actions.bzl", "windows_actions")

def _stub_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(out, "#!/bin/sh\nexit 0\n", is_executable = True)
    files = [out]
    if ctx.attr.sidecar:
        sidecar = ctx.actions.declare_file(ctx.label.name + ".json")
        ctx.actions.write(sidecar, "{}")
        files.append(sidecar)
    return [DefaultInfo(
        executable = out,
        files = depset(files),
        runfiles = ctx.runfiles(files = ctx.files.data + files).merge_all([target[DefaultInfo].default_runfiles for target in ctx.attr.data]),
    ), RunEnvironmentInfo(environment = {"FIXTURE_VALUE": "binary-owned environment"})]

stub = rule(
    implementation = _stub_impl,
    executable = True,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "sidecar": attr.bool(),
    },
)

def _collision_impl(ctx):
    runner = windows_actions.resolve(ctx)
    outputs = []
    for name in ["Aa", "BB"]:
        out = ctx.actions.declare_file(name)
        windows_actions.run(
            ctx,
            runner = runner,
            executable = ctx.file.binary,
            arguments = [name],
            outputs = [out],
            env = {"DISTINCT": name},
        )
        outputs.append(out)
    return [DefaultInfo(files = depset(outputs))]

collision = rule(
    implementation = _collision_impl,
    attrs = {
        "binary": attr.label(allow_single_file = True, mandatory = True),
    },
    toolchains = [windows_actions.toolchain_type],
)

def _symlink_data_impl(ctx):
    return [DefaultInfo(files = depset(), runfiles = ctx.runfiles(root_symlinks = {"alias.txt": ctx.file.src}))]

symlink_data = rule(
    implementation = _symlink_data_impl,
    attrs = {
        "src": attr.label(allow_single_file = True, mandatory = True),
    },
)

def _typed_action_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".out")
    windows_actions.run(
        ctx,
        runner = windows_actions.resolve(ctx),
        executable = ctx.attr.tool,
        outputs = [output],
    )
    return [DefaultInfo(files = depset([output]))]

typed_action = rule(
    implementation = _typed_action_impl,
    attrs = {"tool": attr.label(mandatory = True)},
    toolchains = [windows_actions.toolchain_type],
)
