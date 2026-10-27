"""Adapt Windows executables with native Linux/macOS Wine runtimes."""

load("//wine/private:adapter.bzl", "adapter_impl")
load("//wine/private:payload.bzl", "payload_attrs")

_windows_binary = rule(
    implementation = adapter_impl,
    executable = True,
    attrs = dict(payload_attrs(), _use_auto_exec_groups = attr.bool(default = False)),
    toolchains = [
        "//wine:adapter_toolchain_type",
        "@hermetic_launcher//launcher:finalizer_toolchain_type",
        "@hermetic_launcher//launcher:template_exec_toolchain_type",
    ],
    doc = "Adapt a Windows executable using the toolchain matching the adapter's target OS/CPU.",
)

def windows_binary(name, target_platform = None, **kwargs):
    """Build source tools for Windows on the wrapper CPU; inspect prebuilt CPUs at runtime.

    Args:
        name: Adapter target name.
        target_platform: Optional explicit Windows compilation platform.
        **kwargs: binary and ordinary executable rule attributes.
    """
    _windows_binary(
        name = name,
        target_platform = target_platform if target_platform != None else select({
            Label("@platforms//cpu:x86_64"): Label("//platforms:windows_x86_64"),
            Label("@platforms//cpu:aarch64"): Label("//platforms:windows_aarch64"),
        }),
        **kwargs
    )
