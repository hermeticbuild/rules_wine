"""Run Windows executables through native Wine on Linux/macOS platforms."""

load("//wine/private:adapter.bzl", "adapter_impl")
load("//wine/private:payload.bzl", "payload_attrs")

windows_binary = rule(
    implementation = adapter_impl,
    executable = True,
    attrs = payload_attrs(),
    toolchains = [
        "//wine:adapter_toolchain_type",
        "@hermetic_launcher//launcher:finalizer_toolchain_type",
        "@hermetic_launcher//launcher:template_exec_toolchain_type",
    ],
    doc = "Adapt a Windows executable using the toolchain matching the adapter's target OS/CPU.",
)
