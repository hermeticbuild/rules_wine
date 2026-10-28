# Runtime behavior and limitations

## Distribution requirements

The defaults use [Wine 11.20.1](https://github.com/hermeticbuild/wine-prebuilt/releases/tag/11.20.1),
with archives pinned by SHA-256. Linux needs glibc 2.17 or newer and an available
UTF-8 locale. Additional Windows subsystems may require host libraries beyond
the console workloads exercised by the tests.

The macOS ARM64 runtime declares a 26.5 deployment target. Its release was built
and tested on macOS 26.6.2; the Bazel wrappers also ran on 26.5.2. These are
different facts from proving execution on exact 26.5. The distribution is
unsigned and is not a notarized application. Intel macOS requires a custom
runtime and has not been execution-tested.

ARM64 distributions include FEX for x86_64 Windows programs. Linux x86_64 to
Windows ARM64 is not supported by the default Wine build. There is no Rosetta or
QEMU fallback, and i386 is outside the tested contract. Wine determines payload
CPU support; unsupported payloads fail inside Wine.

## Isolation and process lifecycle

Each invocation creates a private prefix, home/cache/temp directories and a fresh
Wine server. Mono/Gecko and menu-builder integration are disabled. The pinned
loader/server paths are explicit. Initial setup has a 60-second deadline;
prefix-scoped server stop/wait each have a 5-second deadline. Linux cancellation
kills the payload process group, stops the owned server, reaps children, then
removes scratch state. Cleanup errors are reported without replacing the payload
result. Exit statuses 0–255 pass through on Unix; signals use 128+signal. Wine's
CLI can truncate full Windows statuses before the Unix supervisor receives them;
lossless full Windows exit reporting is not supplied. Native Windows actions
retain the native process interface.

Prefix isolation is not a security sandbox. No shared/prepared prefixes,
winetricks, machine Wine, shell utilities or Python are in the production runtime.
Stronger filesystem/process/network isolation, immutable prefix seeds, GUI/.NET,
coverage and workers remain future work. See [testing and maintenance](../tests/README.md)
for the verification commands and platform gaps.

## Supervisor and dependencies

The supervisor is compiled from source for the selected execution platform. No
supervisor binary is checked in. `tests/compile_platforms.sh --config=remote` checks
the four Linux/macOS cross-compilation targets;
`tests/update_fixtures.sh --config=remote` rebuilds development-only fixtures,
which are not consumer dependencies. Production C++ dependencies provide Bazel
runfiles and JSON parsing. The development LLVM toolchain is not inherited by
consumers. The `hermetic_launcher` bootstrap uses published binaries, so consumers
do not need Rust.

## Known runtime caveats

The published macOS runtime prints a `virtual_alloc_first_teb` assertion during
fresh prefix initialization. This also occurs with bare Wine; initialization and
independently compiled ARM64 fixtures still return success. Intel macOS execution
remains unverified. Local Windows actions run without path mapping: Bazel 8/9 have
no local Windows sandbox strategy supporting mapped actions. Mapping on a Windows
remote executor remains unverified.
