"""Run Windows executables through native Wine on Linux/macOS platforms."""

load("//wine/private:adapter.bzl", _adapter_impl = "adapter_impl")
load("//wine/private:payload.bzl", _payload_attrs = "payload_attrs")

windows_binary = rule(
    implementation = _adapter_impl,
    executable = True,
    attrs = _payload_attrs(),
    toolchains = [
        "//wine:adapter_toolchain_type",
        "@hermetic_launcher//launcher:finalizer_toolchain_type",
        "@hermetic_launcher//launcher:template_exec_toolchain_type",
    ],
    doc = """Wrap a Windows executable for use with bazel run or as another rule's tool.

The wrapper runs on Linux/macOS using the Wine toolchain matching its configured
target OS/CPU. As a dependency configured with cfg = "exec", that is the consuming
action's execution platform. Native Windows actions should use windows_actions.run.

The payload's runfiles and RunEnvironmentInfo are preserved. Prebuilt payloads
use the selected Wine runtime's supported guest CPUs. For source-built payloads,
target_platform optionally selects a Windows compilation platform; its CPU must
match the wrapper's CPU. This rule does not register a C++ compiler.
""",
)
