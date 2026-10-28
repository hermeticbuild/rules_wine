"""Pinned default Wine toolchains; custom runtimes use public toolchain rules."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", _http_archive = "http_archive")
load("//wine/private:repositories.bzl", _registration_repository = "registration_repository")

_VERSION = "11.20.1"
_RELEASE = "https://github.com/hermeticbuild/wine-prebuilt/releases/download/" + _VERSION
_DISTRIBUTIONS = {
    "linux_x86_64": struct(
        platform = "linux-amd64",
        sha256 = "ce069b8ea2c8e301890fd96d58cebe3945a4a474776804d1d876692fa20cb49d",
        requirements = "Linux glibc 2.17 or newer and an available UTF-8 locale; see the release manifest and DISTRIBUTION.md.",
    ),
    "linux_aarch64": struct(
        platform = "linux-arm64",
        sha256 = "878ff847e6700b17eddbdc9b4c1bdd29965ddc3f26c0f550cc8347150de9f2a0",
        requirements = "Linux glibc 2.17 or newer and an available UTF-8 locale; bundled FEX for amd64 guests. See the release manifest and DISTRIBUTION.md.",
    ),
    "osx_aarch64": struct(
        platform = "macos-arm64",
        sha256 = "f59e73741f83558fcbef00bc4efcbc760f9e69973cfdf1eff96e9aaafbeedf81",
        requirements = "macOS ARM64, deployment target 26.5; bundled FEX for amd64 guests. Unsigned command-line runtime; see the release manifest and DISTRIBUTION.md.",
    ),
}

def _archive(name, distribution):
    _http_archive(
        name = name,
        urls = ["{}/wine-{}-{}.tar.zst".format(_RELEASE, distribution.platform, _VERSION)],
        sha256 = distribution.sha256,
        build_file_content = "\n".join([
            'package(default_visibility = ["//visibility:public"])',
            'filegroup(name = "loader", srcs = ["bin/wine"])',
            'filegroup(name = "server", srcs = ["bin/wineserver"])',
            'filegroup(name = "files", srcs = glob(["**"]))',
            "",
        ]),
    )

def _impl(ctx):
    registrations = {}
    for key, distribution in sorted(_DISTRIBUTIONS.items()):
        repo = "wine_prebuilt_" + key
        _archive(repo, distribution)
        registrations[key] = {
            "repository": repo,
            "identity": "hermeticbuild Wine {} {}".format(_VERSION, distribution.platform),
            "requirements": distribution.requirements,
        }
    _registration_repository(name = "wine_toolchains", distributions = json.encode(registrations))

    # No tags describe imports; consumers choose whether to use these defaults.
    return ctx.extension_metadata(reproducible = True)

wine = module_extension(
    implementation = _impl,
    doc = """Provide pinned Wine distributions and default Windows runner toolchains.

Import wine_toolchains with use_repo, then register
@wine_toolchains//:all explicitly. This extension has no configuration tags and
does not register toolchains automatically. Custom distributions use
windows_runner_toolchain and native toolchain declarations instead.

Defaults cover Linux x86_64/ARM64, macOS ARM64 and native Windows x86_64/ARM64.
ARM64 Wine distributions include FEX for x86_64 Windows programs. Linux requires
glibc 2.17 or newer and a UTF-8 locale. The macOS distribution declares a 26.5
deployment minimum; see the runtime guide for tested baselines and limitations.
""",
)
