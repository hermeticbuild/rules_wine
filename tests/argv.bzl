"""Regression consumers: argv records, action identity and full runfiles."""

load("//wine:actions.bzl", "windows_actions")

def _runfile_path(ctx, file):
    return file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path

def _records_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name)
    config = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.symlink(output = executable, target_file = ctx.executable._verify, is_executable = True)
    ctx.actions.write(config, json.encode({
        _runfile_path(ctx, target[DefaultInfo].files.to_list()[0]): json.decode(expected)
        for target, expected in ctx.attr.records.items()
    }))
    return [DefaultInfo(
        executable = executable,
        runfiles = ctx.runfiles(
            files = [config, ctx.executable._verify],
            transitive_files = depset(transitive = [target[DefaultInfo].files for target in ctx.attr.records]),
        ),
    )]

argv_record_test = rule(
    implementation = _records_impl,
    test = True,
    attrs = {
        "records": attr.label_keyed_string_dict(mandatory = True),
        "_verify": attr.label(default = "//tests:argv_verify", executable = True, cfg = config.exec("test")),
    },
    exec_groups = {
        "test": exec_group(exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"]),
    },
)

def _custom_tools_impl(_settings, _attr):
    return {"//command_line_option:extra_toolchains": [str(Label("//tests:native_executable_runfiles_registration"))]}

_custom_tools = transition(
    implementation = _custom_tools_impl,
    inputs = [],
    outputs = ["//command_line_option:extra_toolchains"],
)

custom_tools_record_test = rule(
    implementation = _records_impl,
    test = True,
    attrs = {
        "records": attr.label_keyed_string_dict(mandatory = True, cfg = _custom_tools),
        "_verify": attr.label(default = "//tests:argv_verify", executable = True, cfg = config.exec("test")),
        "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
    },
    exec_groups = {"test": exec_group(exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"])},
)

def _mapping_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name)
    config = ctx.actions.declare_file(ctx.label.name + ".json")
    files = ctx.files.mapped + ctx.files.collision + ctx.files.param + ctx.files.distinct
    ctx.actions.symlink(output = executable, target_file = ctx.executable._verify, is_executable = True)
    ctx.actions.write(config, json.encode({
        "mapping": ctx.attr.mapped_paths,
        "mapped": _runfile_path(ctx, ctx.file.mapped),
        "collision": _runfile_path(ctx, ctx.file.collision),
        "param": _runfile_path(ctx, ctx.file.param),
        "distinct": [_runfile_path(ctx, file) for file in ctx.files.distinct],
    }))
    return [DefaultInfo(executable = executable, runfiles = ctx.runfiles(files = files + [config, ctx.executable._verify]))]

mapping_record_test = rule(
    implementation = _mapping_impl,
    test = True,
    attrs = {
        "mapped": attr.label(allow_single_file = True, mandatory = True),
        "collision": attr.label(allow_single_file = True, mandatory = True),
        "param": attr.label(allow_single_file = True, mandatory = True),
        "distinct": attr.label(mandatory = True),
        "mapped_paths": attr.bool(),
        "_verify": attr.label(default = "//tests:argv_verify", executable = True, cfg = config.exec("test")),
    },
    exec_groups = {"test": exec_group(exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"])},
)

def _two_actions_impl(ctx):
    runner = windows_actions.resolve(ctx)
    outputs = []
    for name in ["Aa", "BB"]:
        output = ctx.actions.declare_file(ctx.label.name + "/" + name)
        args = ctx.actions.args()
        args.add("--output")
        windows_actions.add_path(runner, args, output)
        args.add(name)
        windows_actions.run(
            ctx,
            runner = runner,
            executable = ctx.file.binary,
            arguments = [args],
            env = {"FIXTURE_VALUE": name},
            outputs = [output],
        )
        outputs.append(output)
    return [DefaultInfo(files = depset(outputs))]

two_actions = rule(
    implementation = _two_actions_impl,
    attrs = {
        "binary": attr.label(allow_single_file = True, cfg = "exec", mandatory = True),
    },
    toolchains = [windows_actions.toolchain_type],
    exec_compatible_with = ["@platforms//cpu:x86_64"],
)

def _aliases_impl(ctx):
    return [DefaultInfo(
        files = depset(),
        runfiles = ctx.runfiles(
            symlinks = {"logical/data.txt": ctx.file.src},
            root_symlinks = {"root-alias.txt": ctx.file.src},
        ),
    )]

alias_data = rule(
    implementation = _aliases_impl,
    attrs = {
        "src": attr.label(allow_single_file = True, mandatory = True),
    },
)
