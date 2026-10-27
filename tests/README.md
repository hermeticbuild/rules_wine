# Testing and maintenance

Run from the repository root. The `remote` config uses a native Linux x86_64
BuildBuddy executor with Ubuntu 24.04; authentication belongs in your user config.
For a native local Linux worker, omit `--config=remote`.

## Behavior checks

```sh
bazel test //tests:integration --config=remote
bazel build //tests:generate //tests:adapter_tool \
  //tests:param_file \
  //tests:additional_tools //tests:default_group //tests:default_group_tools \
  //tests:external_tools //tests:distinct_actions \
  --config=remote
bazel test //tests:argv_test --config=remote --noenable_runfiles
```

These use independent Windows executables to check output generation, DLL loading,
child processes, argument preservation, and generated/external data. The lifecycle
test checks concurrent private
prefixes, cancellation ownership, descendant cleanup, exit status, architecture
rejection, and unchanged input files. The layout test creates real symlinks because
remote execution can materialize ordinary runfiles and hide local layout bugs.
The argv regression passes arguments through the generated launcher and asserts
exact records for spaces, empty strings, Unicode, literal dollar/location strings,
opaque options and leading `--config`/`--` arguments. Invocation arguments belong
to the consumer; the adapter has no expression-expansion API. A source-built
Windows consumer uses the standard C++ runfiles
library through `windows_actions.run` with its `FilesToRunProvider` to verify
apparent-repository mapping and alias-only runfiles. Bazel supplies the runfiles
layout; the ruleset does not write a replacement manifest.

Inspect the generated JSON files as well as the test results. Use `bazel aquery`
to inspect executables, platforms, declared tools and inputs. Native actions must
invoke the PE directly without Wine inputs:

```sh
bazel aquery //tests:generate --config=remote \
  --extra_execution_platforms=//platforms:windows_x86_64
```

## Consumers and Bazel versions

```sh
(cd e2e/smoke && bazel build //:generate --config=remote)
jq -e '.args | index("external-consumer") != null' e2e/smoke/bazel-bin/external.json
jq -e '.args | index("adapter-consumer") != null' e2e/smoke/bazel-bin/adapter.json
e2e/test_custom_archive.sh /absolute/path/to/wine-11.0-amd64-wow64.tar.xz SHA256
e2e/test_starlark.sh
e2e/test_adapter_platforms.sh
e2e/test_extension.sh
e2e/test_path_mapping.sh
```

The consumer exercises the public module setup, action helper and binary adapter.
The script tests a custom
archive through `http_archive`; supplying an incorrect checksum must fail fetching.
Keep fixture compilers and test helpers out of production dependency paths.
The Starlark and extension scripts retain their temporary workspaces for
inspection. Each accepts an optional ruleset checkout path. The extension checks
pinned defaults, shared extension usage, rejection of removed tags, native Windows
runners, and switching between ordinary and dev-only usage. The custom archive
consumer registers public toolchains without loading the default extension.
The Starlark script checks distinct Aa/BB actions, aliases under `select()`, executable sidecar outputs,
an external executable's data and expected payload-platform analysis errors.
It also inspects the same adapter under x86_64 and ARM64 target platforms,
checking supported guests and rejecting declared mismatches. Undeclared fixed
prebuilts are not relabeled by the payload platform. Provider-only imports retain
original paths, environment and runfiles; explicit companion files retain their
artifact paths. ARM64 checks inspect graphs without executing the synthetic runtime.
The adapter platform script builds real Windows source payloads and ELF adapters
for Linux x86_64 and ARM64 on native remote workers, with automatic execution
groups both on and off and opposite-CPU-first platform registration. It inspects
wrapper and PE machine types, explicit platform overrides, and fixed versus
configuration-selected prebuilts.
The execution-group regression selects ARM64 Wine and x86_64 native Windows
within one rule under both target CPUs. It checks the execution platforms, Wine
configuration CPU, and backend-specific path arguments. A fixed-x86 action
selects x86 execution even with an ARM64 target, and fails when only ARM64
execution is available. The new public context API fails to load against
`dbba164`, which still exposes architecture-specific runner types.

Bazel 8.5.0 and 9.3.1 have been exercised. With Bazelisk, set
`USE_BAZEL_VERSION` when running the common suite. Add `--lockfile_mode=off` to
root-workspace commands when checking another Bazel major version to avoid
rewriting the checked-in lockfile into that version's format.

The path-mapping script runs real Wine actions with mapping enabled and disabled,
including source-built Windows runfiles fixtures, executable adapters, generated
PE and data paths, Unicode/braces, literal environment escaping and payload
parameter files. Split-configured inputs with colliding mapped paths must trigger
Bazel's unmapped fallback and preserve both inputs. Output records assert the
paths actually seen by the Windows program; `aquery` checks action-owned JSON
parameter files. Each run uses an isolated output base and preserves logs and
records under the printed temporary directory. Run it with
`USE_BAZEL_VERSION=8.5.0` and `USE_BAZEL_VERSION=9.3.1`.
On baseline `fc1913e`, `//tests:param_file` fails with
`--experimental_output_paths=strip --modify_execution_info=WindowsRun=+supports-path-mapping`
because the supervisor receives the unmapped configuration path.

Path mapping is opt-in per consuming action. Ordinary environment strings and
paths embedded in arbitrary input/output files are not mapped. The tests exercise
Bazel-generated response files, not a generic Wine response-file translator.
Native Windows mapping runtime and cross-configuration cache reuse remain unverified.

For the downstream smoke consumer, enable mapping with
`--experimental_output_paths=strip '--modify_execution_info=WindowsRun|WineAdapterConsumer=+supports-path-mapping'`.
Keep command-line opt-in scoped to these actions: the generic `Action` mnemonic
also selects dependency actions, including LLVM actions that are not mapping-safe.

## Source build and fixture maintenance

```sh
tests/compile_platforms.sh --config=remote
tests/update_fixtures.sh --config=remote
(cd tests/fixture && shasum -a 256 -c SHA256SUMS)
```

The supervisor builds from source for each executor and is not checked in. Fixture
maintenance uses Bazel's declared compiler/toolchain for PE executables and the
companion DLL. Lifecycle and argv verifiers build from source in the actual test
execution configuration; no verifier binary is checked in. Keep fixture sources
and checked-in Windows test binaries in sync.

The supervisor uses `rules_cc`'s runfiles library for discovery and manifest
parsing. Its `EnvVars()` are forwarded to the payload, with Wine path conversion.
`hermetic_launcher` resolves the supervisor/configuration and forwards argv.
Explicit action environment, Windows path markers and Wine lifecycle management
remain supervisor responsibilities. The supervisor is Linux/macOS-only; its
cross-compilation check covers those four OS/CPU combinations.

## Verification boundaries

The public Wine 11.20.1 archives are pinned by SHA-256 and preserve their complete
installation layout. Linux distributions declare glibc 2.17 plus an available
UTF-8 locale; these rules' native x86_64 and ARM64 remote tests use Ubuntu 24.04.
Tests on newer workers do not re-establish the declared minimum libc version.

Exercise both Linux defaults on native workers with:

```sh
bazel build --config=remote --extra_execution_platforms=//platforms:remote_linux_x86_64,//platforms:remote_linux_aarch64 //tests:generate //tests:generate_arm64
jq -e '.child == "child-ok"' bazel-bin/tests/generate.json bazel-bin/tests/generate_arm64.json
```

Native Windows and Intel macOS execution remain untested. Windows
action graphs verify selection and inputs, not runtime behavior. Native local Linux
sandbox execution remains unverified.

The source-built C++ runfiles fixture runs through both a direct
`FilesToRunProvider` action and `windows_binary` as an action tool. Both verify
external-repository mapping and alias-only data. The adapter case fails against
`4ff2f7e` because its supervisor did not export the discovered runfiles environment.
The layout test also exercises a manifest whose payload entry points outside the
runfiles directory, verifying that adjacent DLL lookup retains the logical layout.

The pinned `@llvm` 0.7.6 macOS SDK URL returns 403. Both macOS supervisor
architectures were cross-compiled with a temporary root-module `osx.from_archive`
override using [Apple's SDK 26.5 package](https://swcdn.apple.com/content/downloads/33/19/140-17812-A_21ZLMMLY4E/zu3xwktttpoe71qiawhzgzvqss6rovawsa/CLTools_macOSNMOS_SDK.pkg).
The package was found through `hermetic-llvm`'s `tools/update_osx_sdk.py` catalog
parser, downloaded with HTTP 200, and its embedded SDK version and SHA-256 verified:
`debe353b27a13cd678b26ab216a040acf07b62c0639d8ac522df4ca07d121eb2`.
For the override, set `type = "pkg"` and
`strip_prefix = "Payload/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"`.
This verification does not update the pinned LLVM dependency's default SDK URL;
downstream macOS builds need the override until that dependency is updated.

The published macOS ARM64 archive runs independent ARM64 fixtures through Bazel
on macOS 26.5.2 with the SDK override above. The release manifest records SDK 26.5,
deployment target 26.5 and publisher-tested OS 26.6.2 separately; exact-minimum
26.5 execution is not proven.

Fresh prefixes emit Wine's `virtual_alloc_first_teb` assertion. The same archive
reproduces it without the supervisor; initialization and tested ARM64 programs
still succeed. Gatekeeper acceptance of quarantined downloads is unverified.
Although the ARM64 archives bundle FEX, this revision retains same-CPU execution.
