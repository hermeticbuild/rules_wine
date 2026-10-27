"""Pinned default Wine toolchains; custom runtimes use public toolchain rules."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//wine/private:repositories.bzl", "registration_repository")

_DEFAULT = struct(
    urls = ["https://github.com/Kron4ek/Wine-Builds/releases/download/11.0/wine-11.0-amd64-wow64.tar.xz"],
    sha256 = "39574efa1132c3ca0d5c77dd2eddbe4a49cca0d6cc2c290ff4924493a1c40314",
    integrity = "",
    strip_prefix = "wine-11.0-amd64-wow64",
    loader = "bin/wine",
    server = "bin/wineserver",
    files = ["**"],
    arch = "x86_64",
    exec_os = "linux",
    env = {},
    identity = "Kron4ek Wine 11.0 amd64 WoW64",
    requirements = "Linux glibc ELF interpreter; glibc, libm, libgcc_s; optional subsystem libraries depend on payload. See README.md.",
)

def _archive(name, distribution):
    http_archive(
        name = name,
        urls = distribution.urls,
        sha256 = distribution.sha256,
        integrity = distribution.integrity,
        strip_prefix = distribution.strip_prefix,
        build_file_content = "\n".join([
            'package(default_visibility = ["//visibility:public"])',
            'filegroup(name = "loader", srcs = [{}])'.format(repr(distribution.loader)),
            'filegroup(name = "server", srcs = [{}])'.format(repr(distribution.server)),
            'filegroup(name = "files", srcs = glob({}))'.format(repr(distribution.files)),
            "",
        ]),
    )

def _impl(ctx):
    distributions = {"linux_x86_64": _DEFAULT}
    registrations = {}
    for key, distribution in sorted(distributions.items()):
        repo = "wine_prebuilt_" + key
        _archive(repo, distribution)
        registrations[key] = {
            "repository": repo,
            "identity": distribution.identity,
            "requirements": distribution.requirements,
            "env": distribution.env,
        }
    registration_repository(name = "wine_toolchains", distributions = json.encode(registrations))

    # No tags describe imports; consumers choose whether to use these defaults.
    return ctx.extension_metadata(reproducible = True)

wine = module_extension(
    implementation = _impl,
)
