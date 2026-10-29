# Tests and maintenance

The root suite and each downstream module expose ordinary Bazel tests. Run from
the repository root:

```sh
bazel test //... --lockfile_mode=off
(cd e2e/smoke && bazel test //... --lockfile_mode=off)
(cd e2e/tools && bazel test //... --lockfile_mode=off)
(cd e2e/tools_caller && bazel test //... --lockfile_mode=off)
(cd e2e/starlark && bazel test //... --lockfile_mode=off)
(cd e2e/custom_runtime && bazel test //... --lockfile_mode=off)
```

The root and custom-runtime suites require Linux x86_64 execution. The smoke and
tools modules run on all five supported native executors. The Starlark module
analyzes synthetic platforms without executing their placeholder programs.

For root tests from another host, use the configured Linux remote worker:

```sh
bazel test //... --config=remote --platforms=//platforms:linux_x86_64 --lockfile_mode=off
```

BuildBuddy authentication belongs in your user configuration. Native E2E checks
use local execution to verify the actual executor and its published archives.

## Coverage

| Suite | Contract |
| --- | --- |
| Root | Wine lifecycle and cancellation ownership; DLL adjacency; exact arguments; direct and adapter runfiles; custom native compiler runfiles; generated paths and parameter files; both Windows RPC compilation ABIs |
| `e2e/smoke` | Downstream runtime setup; action and executable-adapter APIs; generated input/output paths, arguments, environment and child execution |
| `e2e/tools` | Compiler-free native message/resource/IDL generation; output contents; declared generated imports/assets; both output ABIs; Make variables and executable tools |
| `e2e/tools_caller` | The same native generation from an external repository, including package-relative generated include roots |
| `e2e/starlark` | Custom runtime/provider contracts, payload-platform errors, execution groups, executable tool selection independent of its build executor, input validation |
| `e2e/custom_runtime` | A consumer-owned checksum-pinned archive and public toolchain registrations without the default Wine extension |

Root tests and the runtime consumer explicitly select LLVM as a development
compiler. The tools modules do not select a C/C++ compiler; their artifact
checkers use Bash and standard shell utilities. Native Windows tests require
Git Bash. CI's dependency-graph check additionally uses jq.

The tools checkers remain native to the executor while their dependencies generate
x86_64 and ARM64 Windows outputs. Generated RPC C is compiled only in the root
suite, using the same IDL source as the downstream tools tests. The ARM64 compile
fixture defines `__RPC_WIN64__` because MinGW's `rpc.h` omits ARM64 from that test.

## CI and path mapping

GitHub Actions runs both native consumers on Linux x86_64/ARM64, macOS ARM64 and
Windows x86_64/ARM64, with Bazel 8.5.0 and 9.3.1. Linux/macOS ARM64 execute both
ARM64 and x86_64 Windows payloads; other executors use their native payload CPU.
Windows exercises direct actions; Linux/macOS also exercise the executable adapter.

The runtime test checks the fixture's PE machine and compares Bazel's configured
CPU with the CI matrix's expected CPU, passed through `RULES_WINE_EXPECTED_CPU`.
Local Linux and macOS tests also compare the configured CPU with `uname -m`.
Local Windows tests verify the PE and runtime output; Git Bash's own architecture
is not reliable when it runs under x86_64 emulation on ARM64.

The two Linux x86_64 jobs also run the root, Starlark, external-tools and custom
archive suites. They verify optional path mapping with:

```sh
bazel test //tests:argv_test //tests:mapping_test --config=mapped --lockfile_mode=off
(cd e2e/smoke && bazel test //... --config=mapped --lockfile_mode=off)
(cd e2e/tools && bazel test //... --config=mapped --lockfile_mode=off)
(cd e2e/tools_caller && bazel test //... --config=mapped --lockfile_mode=off)
```

The mapped root test checks collision fallback as well as the paths observed by
the Windows program. Ordinary environment strings and file contents remain
opaque. Mapping configurations scope opt-in to the ruleset's action mnemonics.

Two expected-failure builds remain explicit CI checks: a resource with an
undeclared asset and an IDL with an undeclared import. These exercise actual
sandbox exclusion; analysis tests cannot catch an expected compiler action
failure through a normal test dependency. All other assertions belong to Bazel
test targets, and no test launches another Bazel invocation.

Mapping is tested on Linux with both Bazel versions. Native macOS mapping is not
part of the routine matrix. Local Windows has no mapping-capable sandbox;
native Windows mapped execution requires a suitable remote worker and remains
unverified. Cross-configuration cache reuse is not claimed.

Formatting and extracted release-archive checks remain separate. Both Bazel
versions build the published API documentation and run the extracted downstream
consumer. BCR's platform subset and publication steps are documented in
[releasing](../docs/releasing.md).

## Fixture maintenance

```sh
tests/update_fixtures.sh --config=remote
(cd tests/fixture && shasum -a 256 -c SHA256SUMS)
tests/compile_platforms.sh --config=remote
```

The fixture update script rebuilds checked-in Windows payloads and the companion
DLL with the declared toolchain. Keep their sources and binaries in sync.
The supervisor and test verifiers build from source. The optional cross-compile
script also checks Intel macOS compilation for custom runtimes; CI does not
claim Intel macOS execution.

The native matrix does not establish minimum glibc or exact macOS deployment
requirements. See [runtime limitations](../docs/runtime.md) and
[native tools](../docs/tools.md) for the supported distribution boundaries.
