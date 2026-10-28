"""Pinned default Wine toolchains; custom runtimes use public toolchain rules."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", _http_archive = "http_archive")
load("//wine/private:repositories.bzl", _registration_repository = "registration_repository")
load("//wine/private:tools_repositories.bzl", _tools_registration_repository = "tools_registration_repository")

_VERSION = "11.20.2"
_RELEASE = "https://github.com/hermeticbuild/wine-prebuilt/releases/download/" + _VERSION
_DISTRIBUTIONS = {
    "linux_x86_64": struct(
        platform = "linux-amd64",
        sha256 = "5fb0f5f32a305873337e0202638acc64f59690c7a0184a6ea6a0164a79e31dc7",
        requirements = "Linux glibc 2.17 or newer and an available UTF-8 locale; see the release manifest and DISTRIBUTION.md.",
    ),
    "linux_aarch64": struct(
        platform = "linux-arm64",
        sha256 = "50e51562481c49ac4b602b69177da77d247ef83caee8b22bb0e669399ba61a10",
        requirements = "Linux glibc 2.17 or newer and an available UTF-8 locale; bundled FEX for amd64 guests. See the release manifest and DISTRIBUTION.md.",
    ),
    "osx_aarch64": struct(
        platform = "macos-arm64",
        sha256 = "7e51f722abfa9601ee0deb795f946490fa59a1c306e6d114493d8e4b8ccf3b6f",
        requirements = "macOS ARM64, deployment target 26.5; bundled FEX for amd64 guests. Unsigned command-line runtime; see the release manifest and DISTRIBUTION.md.",
    ),
}
_TOOLS = {
    "linux_x86_64": ("linux-amd64", "7d9b5025d68d196fdfae93f6e6e76e39f14cc16626ed2ba9bf27f3cda3449566"),
    "linux_aarch64": ("linux-arm64", "ec69e14e85538be41c1f4be58ad69a6e28e933d57ebfdaee011d393ab2c63a02"),
    "osx_aarch64": ("macos-arm64", "7826fbdd92d060859c9a09c5cab5ef6a5a5ecff298408fc802c5a0dc4e0d9615"),
    "windows_x86_64": ("windows-amd64", "e4c977932c601da08d8dc1fc000575bfc3bd965856ec0c3070bfb3ac37aa3f45"),
    "windows_aarch64": ("windows-arm64", "c6ff889049132d4b583eb0b836f1b48411945297f00eb7f387f881c2e3555876"),
}

def _tools_archive(name, platform, sha256):
    suffix = ".exe" if platform.startswith("windows-") else ""
    exports = [
        "bin/" + tool + suffix
        for tool in ["wmc", "wrc", "widl"]
    ] + [
        "include/wine/windows/windows.h",
        "lib/wine/x86_64-windows/stdole2.tlb",
        "lib/wine/aarch64-windows/stdole2.tlb",
    ] + (["share/wine/nls/locale.nls"] if not suffix else [])
    _http_archive(
        name = name,
        urls = ["{}/wine-tools-{}-{}.tar.zst".format(_RELEASE, platform, _VERSION)],
        sha256 = sha256,
        build_file_content = "\n".join([
            'package(default_visibility = ["//visibility:public"])',
            "exports_files(" + repr(exports) + ")",
            'filegroup(name = "files", srcs = glob(["**"]))',
            "",
        ]),
    )

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
    tools = {}
    for key, (platform, sha256) in sorted(_TOOLS.items()):
        repo = "wine_tools_prebuilt_" + key
        _tools_archive(repo, platform, sha256)
        tools[key] = repo
    _tools_registration_repository(name = "wine_tools_toolchains", distributions = json.encode(tools))

    # No tags describe imports; consumers choose whether to use these defaults.
    return ctx.extension_metadata(reproducible = True)

wine = module_extension(
    implementation = _impl,
    doc = """Provide pinned Wine runtimes and independently registered native developer tools.

Import wine_toolchains with use_repo, then register
@wine_toolchains//:all explicitly. This extension has no configuration tags and
does not register toolchains automatically. Custom distributions use
windows_runner_toolchain and native toolchain declarations instead.

Import wine_tools_toolchains and explicitly register @wine_tools_toolchains//:all
to use native wmc, wrc and widl. This tools-only setup needs no Windows runner,
Wine runtime, FEX, supervisor or C++ compiler. Custom tools distributions use
wine_tools_toolchain and native toolchain declarations.

Defaults cover Linux x86_64/ARM64, macOS ARM64 and native Windows x86_64/ARM64.
ARM64 Wine distributions include FEX for x86_64 Windows programs. Linux requires
glibc 2.17 or newer and a UTF-8 locale. The macOS distribution declares a 26.5
deployment minimum; see the runtime guide for tested baselines and limitations.
""",
)
