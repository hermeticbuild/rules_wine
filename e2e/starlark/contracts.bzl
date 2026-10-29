"""Public provider, execution-platform and input contracts, checked in analysis."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_wine//wine:toolchain.bzl", "WindowsRunnerInfo")

def _settings(platform = "audit_exec", runners = ["runner"], executors = ["audit_exec"]):
    return {
        "//command_line_option:platforms": [str(Label("//:" + platform))],
        "//command_line_option:extra_execution_platforms": [str(Label("//:" + value)) for value in executors],
        "//command_line_option:extra_toolchains": [str(Label("//:" + value)) for value in runners],
    }

def _actions_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    inputs = [file.short_path for action in actions for file in action.inputs.to_list()]
    for expected in ctx.attr.inputs:
        asserts.true(env, any([value.endswith(expected) for value in inputs]), "missing declared input " + expected)
    for forbidden in ctx.attr.forbidden_inputs:
        asserts.false(env, any([forbidden in value for value in inputs]), "unexpected input " + forbidden)
    return analysistest.end(env)

_action_attrs = {"inputs": attr.string_list(), "forbidden_inputs": attr.string_list()}

def _runtime_impl(ctx):
    env = analysistest.begin(ctx)
    runner = analysistest.target_under_test(env)[WindowsRunnerInfo]
    asserts.true(env, "launcher_data" in [file.basename for file in runner.runfiles.files.to_list()])
    asserts.equals(env, "launcher.sh", runner.launcher.executable.basename)
    return analysistest.end(env)

runtime_inputs_test = analysistest.make(_runtime_impl, config_settings = _settings())
generated_runtime_test = analysistest.make(_actions_impl, attrs = _action_attrs, config_settings = _settings(runners = ["generated_runner"]))
sidecar_runtime_test = analysistest.make(_actions_impl, attrs = _action_attrs, config_settings = _settings(runners = ["sidecar_runner"]))
native_inputs_test = analysistest.make(_actions_impl, attrs = _action_attrs, config_settings = _settings(runners = ["native_runner"], executors = ["audit_windows"]))

def _adapter_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    info = target[DefaultInfo]
    files = [file.basename for file in info.default_runfiles.files.to_list()]
    aliases = [link.path for link in info.default_runfiles.root_symlinks.to_list()]
    asserts.true(env, "launcher_data" in files, "custom launcher data omitted")
    asserts.true(env, "alias.txt" in aliases, "alias-only payload data omitted")
    asserts.equals(env, "binary-owned environment", target[RunEnvironmentInfo].environment["FIXTURE_VALUE"])
    return analysistest.end(env)

adapter_test = analysistest.make(_adapter_impl, config_settings = _settings(runners = ["adapter"]))
adapter_arm64_test = analysistest.make(_adapter_impl, config_settings = _settings(platform = "audit_arm64", runners = ["adapter_arm64"], executors = ["audit_arm64"]))

def _external_impl(ctx):
    env = analysistest.begin(ctx)
    files = [file.basename for file in analysistest.target_under_test(env)[DefaultInfo].default_runfiles.files.to_list()]
    asserts.true(env, "LICENSE" in files, "external executable's mapped repository data omitted")
    asserts.true(env, "launcher_data" in files, "custom launcher data omitted")
    return analysistest.end(env)

external_adapter_test = analysistest.make(_external_impl, config_settings = _settings(runners = ["adapter"]))

def _neutral_impl(ctx):
    env = analysistest.begin(ctx)
    files = analysistest.target_under_test(env)[DefaultInfo].files.to_list()
    asserts.true(env, any([file.extension == "res" for file in files]))
    return analysistest.end(env)

neutral_resource_test = analysistest.make(_neutral_impl, config_settings = {"//command_line_option:platforms": [str(Label("@native_tools_consumer//:unsupported_cpu"))]})

def _failure_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.message)
    return analysistest.end(env)

_failure_attrs = {"message": attr.string(mandatory = True)}
payload_failure_test = analysistest.make(_failure_impl, attrs = _failure_attrs, expect_failure = True, config_settings = _settings(runners = ["adapter"]))
arm64_payload_failure_test = analysistest.make(_failure_impl, attrs = _failure_attrs, expect_failure = True, config_settings = _settings(platform = "audit_arm64", runners = ["adapter_arm64"], executors = ["audit_arm64"]))
tool_failure_test = analysistest.make(_failure_impl, attrs = _failure_attrs, expect_failure = True)
unsupported_idl_test = analysistest.make(_failure_impl, attrs = _failure_attrs, expect_failure = True, config_settings = {"//command_line_option:platforms": [str(Label("@native_tools_consumer//:unsupported_cpu"))]})

def _groups_impl(ctx):
    env = analysistest.begin(ctx)
    actions = {action.mnemonic: action for action in analysistest.target_actions(env)}
    wine = actions["WineFixture"].argv
    native = actions["NativeFixture"].argv
    asserts.true(env, any(["{windows_path:" in value for value in wine]))
    asserts.false(env, any(["{windows_path:" in value for value in native]))
    asserts.equals(env, "aarch64", json.decode(wine[2])["arch"])
    asserts.false(env, "--config" in native)
    return analysistest.end(env)

groups_test = analysistest.make(_groups_impl, config_settings = _settings(runners = ["runner_arm64", "native_runner"], executors = ["audit_arm64", "audit_windows"]))
groups_arm64_test = analysistest.make(_groups_impl, config_settings = _settings(platform = "audit_arm64", runners = ["runner_arm64", "native_runner"], executors = ["audit_arm64", "audit_windows"]))

def _fixed_impl(ctx):
    env = analysistest.begin(ctx)
    actions = [action for action in analysistest.target_actions(env) if action.mnemonic == "WindowsRun"]
    for action in actions:
        asserts.equals(env, "x86_64", json.decode(action.argv[2])["arch"])
    asserts.equals(env, 2, len(actions))
    return analysistest.end(env)

fixed_execution_test = analysistest.make(_fixed_impl, config_settings = _settings(platform = "audit_arm64", runners = ["runner_arm64", "runner"], executors = ["audit_arm64", "audit_exec"]))

def _selection_impl(ctx):
    env = analysistest.begin(ctx)
    arguments = [arg for action in analysistest.target_actions(env) for arg in (action.argv or [])]
    asserts.true(env, any([value.endswith("/messages.mc") for value in arguments]))
    asserts.false(env, any([value.endswith("/unicode.rc") for value in arguments]))
    return analysistest.end(env)

def _selection_settings(executor):
    return {
        "//command_line_option:platforms": [str(Label("//selection:selection_a"))],
        "//command_line_option:extra_execution_platforms": [str(Label("//selection:" + executor)), str(Label("//selection:selection_a"))],
        "//command_line_option:extra_toolchains": [str(Label("//selection:selection_registration_a")), str(Label("//selection:selection_registration_b"))],
    }

selection_test = analysistest.make(_selection_impl, config_settings = _selection_settings("selection_b"))
selection_arm64_test = analysistest.make(_selection_impl, config_settings = _selection_settings("selection_arm"))

def contract_tests():
    """Checks public runtime and native toolchain configuration contracts."""
    runtime_inputs_test(name = "runtime_inputs_test", target_under_test = "implementation")
    generated_runtime_test(name = "generated_runtime_test", target_under_test = "collision", inputs = ["built_loader.sh"])
    sidecar_runtime_test(name = "sidecar_runtime_test", target_under_test = "collision", inputs = ["sidecar_launcher.json"])
    native_inputs_test(name = "native_inputs_test", target_under_test = "collision", forbidden_inputs = ["launcher_data", "supervisor", "wine.json"])
    adapter_test(name = "adapter_test", target_under_test = "data_adapter")
    adapter_arm64_test(name = "adapter_arm64_test", target_under_test = "data_adapter")
    external_adapter_test(name = "external_adapter_test", target_under_test = "@caller//:mapped")
    payload_failure_test(name = "wrong_platform_test", target_under_test = "wrong_platform", message = "target_platform must be Windows/x86_64")
    payload_failure_test(name = "wrong_cpu_test", target_under_test = "wrong_cpu", message = "target_platform must be Windows/x86_64")
    arm64_payload_failure_test(name = "wrong_arm64_platform_test", target_under_test = "apparent_platform", message = "target_platform must be Windows/aarch64")
    groups_test(name = "groups_test", target_under_test = "grouped_actions")
    groups_arm64_test(name = "groups_arm64_test", target_under_test = "grouped_actions")
    fixed_execution_test(name = "fixed_execution_test", target_under_test = "fixed_action")
    selection_test(name = "selection_test", target_under_test = "@rules_wine//wine:widl")
    selection_arm64_test(name = "selection_arm64_test", target_under_test = "@rules_wine//wine:widl")
    for target in ["absolute_include", "absolute_windows_include"]:
        tool_failure_test(name = target + "_test", target_under_test = "@native_tools_consumer//:" + target, message = "includes entries must be package-relative")
    unsupported_idl_test(name = "unsupported_idl_test", target_under_test = "@native_tools_consumer//:interfaces", message = "supports target CPUs x86_64 and aarch64")
    for target in ["resources", "message_res"]:
        neutral_resource_test(name = target + "_neutral_test", target_under_test = "@native_tools_consumer//:" + target)
