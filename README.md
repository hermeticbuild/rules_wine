# rules_wine

Run Windows build tools with Bazel on Linux, macOS and Windows. `rules_wine`
provides Wine toolchains, an executable wrapper, and an action helper that runs
Windows executables directly when the worker is Windows.

Wine distributions come from
[hermeticbuild/wine-prebuilt](https://github.com/hermeticbuild/wine-prebuilt).
Downloads are pinned by checksum. You can also register your own distribution.

## Setup

Add to `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_wine", version = "0.1.2")

wine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")
use_repo(wine, "wine_toolchains")
register_toolchains("@wine_toolchains//:all")
```

For a local checkout, also add
`local_path_override(module_name = "rules_wine", path = "../rules_wine")`.

Requires Bazel 8.5 or newer. On Linux and macOS, the Wine supervisor is built
from source using your C++17 toolchain. Bazel can use an installed compiler;
for hermetic or remote builds, register your own C++ toolchain. `rules_wine`
does not select one for you. Native Windows actions need no Wine or supervisor.

## Supported platforms

The default toolchains support these combinations:

| Execution platform | Windows executable CPU |
| --- | --- |
| Linux x86_64 | x86_64 |
| Linux ARM64 | ARM64, x86_64 through FEX |
| macOS ARM64 | ARM64, x86_64 through FEX |
| Windows x86_64 | x86_64 |
| Windows ARM64 | ARM64 |

CPU translation is included in the ARM64 Wine distributions; no extra setup is
needed for x86_64 prebuilts. Linux requires glibc 2.17 or newer and a UTF-8 locale.
The macOS runtime declares a 26.5 deployment minimum; it has been tested on later
26.x versions, not on exact 26.5. There is no default Intel macOS distribution.
See [runtime requirements and limitations](docs/runtime.md).

## Wrap an executable

Use `windows_binary` to run a Windows tool on Linux or macOS:

```starlark
load("@rules_wine//wine:windows_binary.bzl", "windows_binary")

windows_binary(
    name = "generator",
    binary = "generator.exe",
)
```

```sh
bazel run //:generator -- --help
```

The wrapper can also be an executable dependency of another rule. It accepts
prebuilt executables or source-built targets; see
[executable adapters](docs/windows-binary.md) for compilation platforms,
runfiles and path arguments.

## Run a tool in a build action

Rule authors can use `windows_actions` for actions that work on all five
execution platforms. Wine handles Linux/macOS; Windows runs the tool directly.
Within a rule implementation:

```starlark
runner = windows_actions.resolve(ctx)
args = ctx.actions.args()
args.add("--output")
windows_actions.add_path(runner, args, output)
windows_actions.run(
    ctx,
    runner = runner,
    executable = ctx.file.tool,
    arguments = [args],
    outputs = [output],
)
```

The rule declares `windows_actions.toolchain_type` and configures its tool for
execution. See the [action guide](docs/actions.md) for a complete rule, source
compilation, optional path mapping and choosing workers to avoid CPU translation.

## Further reading

- [BCR API reference](https://registry.bazel.build/docs/rules_wine) (for releases publishing API docs)
- [Custom Wine distributions and toolchains](docs/toolchains.md)
- [Runtime behavior, isolation and limitations](docs/runtime.md)
- [Tests and contributing](tests/README.md)
- [Maintaining Starlark libraries and API documentation](docs/contributing.md)
- [Releases and BCR publication](docs/releasing.md)

## License

[Apache-2.0](LICENSE). Downloaded Wine distributions retain their own licenses
and source redistribution material.
