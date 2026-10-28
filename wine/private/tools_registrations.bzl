"""Executor-selected native developer tools registrations."""

load("//wine:tools_toolchain.bzl", "wine_tools_toolchain")

# This declares a complete generated package, with platform-derived names.
# buildifier: disable=unnamed-macro
def register_tools(distributions):
    """Declare native tools implementations and registrations.

    Args:
        distributions: Archive repository names keyed by executor OS and CPU.
    """
    for key, repository in sorted(distributions.items()):
        os, _, arch = key.partition("_")
        prefix = "@" + repository + "//:"
        suffix = ".exe" if os == "windows" else ""
        wine_tools_toolchain(
            name = key + "_impl",
            wmc = prefix + "bin/wmc" + suffix,
            wrc = prefix + "bin/wrc" + suffix,
            widl = prefix + "bin/widl" + suffix,
            include = prefix + "include/wine/windows/windows.h",
            files = prefix + "files",
            nls = None if os == "windows" else prefix + "share/wine/nls/locale.nls",
            x86_64_typelib = prefix + "lib/wine/x86_64-windows/stdole2.tlb",
            aarch64_typelib = prefix + "lib/wine/aarch64-windows/stdole2.tlb",
        )
        native.toolchain(
            name = key,
            toolchain = key + "_impl",
            toolchain_type = "@rules_wine//wine:tools_toolchain_type",
            exec_compatible_with = ["@platforms//os:" + os, "@platforms//cpu:" + arch],
        )
