"""Declarative runner registrations shared by generated repositories."""

load("//wine:toolchain.bzl", "windows_runner_toolchain")

# This declares a complete generated package, with platform-derived names.
# buildifier: disable=unnamed-macro
def register_runners(distributions):
    """Declare direct runner and executable adapter registrations.

    Args:
        distributions: Distribution metadata keyed by executor OS and CPU.
    """
    for arch in ["x86_64", "aarch64"]:
        for os in ["windows", "linux", "osx"]:
            key = os + "_" + arch
            distribution = distributions.get(key)
            if os != "windows" and not distribution:
                continue
            is_native = os == "windows"
            runtime = {} if is_native else dict(distribution)
            if not is_native:
                repo = runtime.pop("repository")
                runtime.update({
                    "loader": "@" + repo + "//:loader",
                    "server": "@" + repo + "//:server",
                    "files": "@" + repo + "//:files",
                })
            windows_runner_toolchain(
                name = key + "_impl",
                supported_guest_cpus = ["@platforms//cpu:" + arch],
                backend = "native" if is_native else "wine",
                launcher = None if is_native else "@rules_wine//wine/runtime:supervisor",
                **runtime
            )
            constraints = ["@platforms//os:" + os, "@platforms//cpu:" + arch]
            for kind in (["runner"] if is_native else ["runner", "adapter"]):
                native.toolchain(
                    name = key if kind == "runner" else key + "_" + kind,
                    toolchain = key + "_impl",
                    toolchain_type = "@rules_wine//wine:adapter_toolchain_type" if kind == "adapter" else "@rules_wine//wine:runner_toolchain_type",
                    exec_compatible_with = constraints,
                    target_compatible_with = constraints if kind == "adapter" else [],
                )
