# Multi-guest Wine runtimes

## Objective and status

Make native Wine distributions with multiple Windows guest CPUs usable through simple Bazel APIs. Ordinary executable inputs remain supported; explicit payload metadata is optional. Separate the executor CPU, Wine's native CPU, and Windows payload CPU.

This is the revised execution plan following the main-thread discussion on 2026-10-27. The dedicated Astra high correctness review is complete and its corrections are incorporated below. The user subsequently authorized implementation by a separate Astra high agent, starting with removal of wine.prebuilt in its own PR and stacking the remaining changes on top. Implementation is in the dedicated worktree recorded in the progress log.

The project is unreleased: choose a clean API without compatibility shims for obsolete APIs. Preserve useful behavior, not old spelling.

## Scope and agreed direction

- Windows guests: amd64/x86_64 and ARM64/aarch64 only. No i386 in this change.
- Native Linux amd64, Linux ARM64 and macOS ARM64 Wine distributions; native Windows amd64/ARM64 direct actions.
- Preserve Bazel 8.5 and Bazel 9 support, lazy Args/path mapping, runfiles, lifecycle and isolation behavior.
- No QEMU integration, Rosetta, windows_run, windows_test, or edits to neighboring projects.
- Default source compilation should follow the executor CPU, with an explicit Windows-platform override.
- Prebuilts can remain plain files; do not assume their CPU matches the executor.
- Optional payload declarations permit earlier errors and explicit contracts.
- The extension supplies pinned first-party defaults only. Custom acquisition uses ordinary repository rules plus public toolchain declarations, not wine.prebuilt override tags.
- Explicit registration remains required. Merely adding bazel_dep must not register Windows runners.
- Advanced users can constrain consuming actions/execution groups to native-CPU remote workers.
- No automatic executor reselection based on payload providers or PE inspection.
- Declared incompatibility may fail during analysis; undeclared-file incompatibility can only be checked at execution. The latter is the recommended tradeoff for wrapper-free declarations and must be highlighted in the review report.

## Original implementation and defects corrected

The original implementation paths were:

- wine/toolchain.bzl: WindowsRunnerInfo.arch conflates executor and guest CPU.
- wine/private/registrations.bzl: two generic types, runner and adapter; native-platform registrations.
- wine/private/payload.bzl: optional payload platform transition, validating against runner.arch.
- wine/private/adapter.bzl: wrapper, config/runfiles, supervisor invocation.
- wine/actions.bzl: low-level actions, native Windows passthrough, deferred path encoding.
- wine/runtime/supervisor.cc: rejects guest != supervisor CPU; validates both Wine and PE against the same arch.
- wine/extension/wine.bzl: Kron4ek Linux amd64 default plus custom archive tags/override precedence.
- MODULE.bazel: Wine registration is dev-only; LLVM dependency/toolchain registration is currently non-dev. Do not silently change compiler ownership in this migration.

The invariant after this change is: Wine and wineserver match the executor-native supervisor; the PE payload matches a guest supported by that Wine distribution. Guest CPU need not equal executor CPU.

## Consumer API examples

Examples describe the implemented public contract.

### Default setup

```starlark
bazel_dep(name = "rules_wine", version = "...")

wine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")
use_repo(wine, "wine_toolchains")
register_toolchains("@wine_toolchains//:all")
```

Expected initial defaults:

| Executor | Windows guests exposed | Route |
| --- | --- | --- |
| Linux amd64 | amd64 | Native Wine |
| Linux ARM64 | ARM64, amd64 | Native Wine / bundled FEX |
| macOS ARM64 | ARM64, amd64 | Native Wine / bundled FEX |
| Windows amd64 | amd64 | Direct execution |
| Windows ARM64 | ARM64 | Direct execution |

Five runner registrations and three Wine adapter registrations. No native Windows adapter in this migration. No macOS Intel default; consumers can provide a custom runtime. Do not advertise i386 merely because an archive contains it. Explicit registration/subset selection must remain possible; dependencies must not force permissive defaults on advanced consumers.

### Ordinary source-built tool

```starlark
cc_binary(
    name = "generator_impl",
    srcs = ["generator.cc"],
)

windows_binary(
    name = "generator",
    binary = "generator_impl",
)
```

Consumed through an executable attribute with cfg = "exec", the wrapper is configured for the consumer's executor. Its payload is compiled for a supplied Windows platform with the same CPU. On Linux amd64 it builds Windows amd64; on Linux/macOS ARM64 it builds Windows ARM64. No separate provider wrapper required.

For bazel run, the wrapper's configured target platform normally follows the local host. Registration of remote workers alone does not make a foreign wrapper run locally.

Implementation for Bazel 8.5: keep the existing exec-configured wrapper boundary; a public macro supplies a CPU-constraint select for the payload-platform attribute, and the internal rule applies an outgoing transition to that chosen Windows platform. The review confirmed outgoing transitions receive resolved attribute values, so this is compatible with 8.5 without transition composition. Prototype this graph before full implementation. Use repository-bound Label constants for internal select keys and platform labels. Do not inspect arbitrary platform providers in a transition or infer executor CPU from legacy --cpu. Mapping supported CPU constraints to supplied Windows platform labels is explicit declaration data.

An explicit override remains:

```starlark
windows_binary(
    name = "generator",
    binary = "generator_impl",
    target_platform = "//platforms:windows_amd64",
)
```

This builds amd64 even on an ARM64 executor, requiring an amd64-capable runtime. Supplied default Windows platforms do not automatically preserve arbitrary custom SDK/ABI constraints. Explicit target_platform is the escape hatch, and a suitable Windows compiler toolchain must exist.

### Ordinary prebuilt

```starlark
windows_binary(
    name = "generator",
    binary = "generator-amd64.exe",
)
```

The file remains amd64 under every configuration. At execution the supervisor reads its PE machine, checks the runtime capability set, and invokes Wine. No metadata target required. On ARM64 Wine/FEX this may run amd64 code; on amd64 Wine it runs natively.

Never infer a prebuilt's ABI from the wrapper or payload configuration. Repository/prebuilt targets returning DefaultInfo may also contain fixed binaries; being a target instead of a source File does not prove compilation occurred. The Windows transition affects every target dependency, including an import whose select() chooses a file. Only a literal fixed file is configuration-independent. A selected Windows platform proves the requested configuration, not the PE machine: do not turn PayloadPlatformInfo.arch into an implicit payload declaration. No separate no-transition mode is promised initially; add one only if a concrete consumer requires preserving an import's incoming configuration.

### Explicit payload contract

```starlark
windows_import(
    name = "generator_payload",
    executable = "generator-amd64.exe",
    guest_cpu = "@platforms//cpu:x86_64",
)

windows_binary(
    name = "generator",
    binary = "generator_payload",
)
```

Optional WindowsExecutableInfo records the actual declared guest CPU and preserves the original executable File/FilesToRunProvider, runfiles and applicable RunEnvironmentInfo. Unsupported declared pairs fail during analysis. Wine execution also checks the actual PE against the declaration.

windows_import is a provider-only metadata target, not an executable wrapper: Bazel rejects DefaultInfo(executable=...) forwarding an executable owned by another target. windows_binary.binary therefore cannot require executable=True; accept and normalize an ordinary executable/source file or the typed provider, rejecting other inputs explicitly. Do not create an executable symlink just to satisfy the attribute: that can change the path used for adjacent DLL lookup.

For companion files, support an explicit data label list of default-output files, preserving artifact paths, adding files to action inputs, and exposing their normal artifact keys in wrapper runfiles. Preserve the original executable runfiles, but do not import data targets' transitive runfiles or augment the original FilesToRunProvider tree. Never copy/rearrange DLLs or claim data entries automatically become adjacent to the PE. Preserve the original FilesToRunProvider when available; raw files carry explicitly declared runtime inputs/runfiles through the metadata provider.

No mandatory windows_executable source wrapper: windows_binary already owns the source compilation transition. Explicit payload declarations are not allowed to relabel an incompatible file silently.

### Low-level Windows actions

Keep executable= accepting File, FilesToRunProvider, or Target. Normalize these documented input types immediately. A Target carrying WindowsExecutableInfo binds the declaration to the executable; pass ctx.attr.tool directly rather than extracting the provider. Do not add a separate metadata argument that could describe a different executable. No metadata target is required for ordinary calls.

```starlark
runner = windows_actions.resolve(ctx)
args = ctx.actions.args()
args.add("--output")
windows_actions.add_path(runner, args, output)
windows_actions.run(
    ctx,
    runner = runner,
    executable = ctx.attr.tool[DefaultInfo].files_to_run,
    arguments = [args],
    outputs = [output],
)
```

This helper invokes an already-configured Windows executable; it cannot recompile dependencies during rule implementation. cfg = "exec" on a plain cc_binary still builds for the executor OS. Source-building rule authors need a Windows dependency transition, or consume windows_binary through an ordinary action. Do not promise implicit source configuration inside windows_actions.run.

Optional metadata is validated in analysis. With no metadata, Wine inspects the PE at execution. Native Windows actions stay direct; undeclared incompatibility is handled by Windows itself, not by adding a supervisor or extra validation action.

### Custom runtimes without extension overrides

A consumer acquires its archive with http_archive or another repository rule, exposes loader/server/files, then declares:

```starlark
windows_runner_toolchain(
    name = "company_wine_impl",
    backend = "wine",
    supported_guest_cpus = ["@platforms//cpu:aarch64"],
    launcher = "@rules_wine//wine/runtime:supervisor",
    loader = "@company_wine//:loader",
    server = "@company_wine//:server",
    files = "@company_wine//:files",
    identity = "Company ARM64 Wine",
    requirements = "Company runtime requirements",
)

toolchain(
    name = "company_wine",
    toolchain_type = "@rules_wine//wine:runner_toolchain_type",
    toolchain = ":company_wine_impl",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
    ],
)
```

Register this explicitly. For windows_binary, additionally register the adapter type using the same implementation and the existing target-and-exec platform constraints. Document both forms completely; no framework or extra type per CPU.

The extension no longer arbitrates per-platform overrides from transitive modules. Remove obsolete tag/override code and tests. Custom users can omit the default extension/registration altogether. Keep http_archive internally for the default pinned downloads.

### Explicit native-CPU RBE placement

For a rule using the default execution group:

```starlark
generate(
    name = "arm64_output",
    tool = "generator_arm64",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
    ],
)
generate(
    name = "amd64_output",
    tool = "generator_amd64",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)
```

With appropriate remote platforms registered, each action selects a matching executor and native Wine route. Platform exec_properties must match the RBE scheduler's actual worker properties; constraints alone do not provision or route remote workers.

Apply placement to the consuming action's execution group, not merely to the dependency's target_compatible_with. Named groups are available when other actions in the rule need different placement. For a wrapper tool, its dependency uses cfg = config.exec("windows") and its action uses exec_group = "windows", toolchain = None; both sides must agree. Low-level runner actions instead keep their runner toolchain association and use windows_actions.resolve(ctx, exec_group = "windows"). Generic reusable rules must not hardcode a guest CPU.

The standard distributions suffice to run a same-CPU initial payload natively even when they include FEX. This is not a guarantee that a different-CPU child cannot use FEX. Strict process-tree no-emulation policies require a restricted runtime or separately demonstrated enforcement, outside this scope.

## Internal contracts

- Retain runner_toolchain_type for action execution and adapter_toolchain_type for the produced wrapper's runtime platform.
- Explicitly disable automatic execution groups on the internal adapter rule via _use_auto_exec_groups=False, preserving one jointly resolved platform for adapter, exec launcher template and finalizer. Current target/exec adapter constraints alone do not align independent automatic groups: an exec template could otherwise produce a different OS/CPU wrapper. Do not globally disable AEGs or change ordinary consuming rules. Verify the minimal strategy against the launcher API before considering a broader target-template redesign.
- Replace overloaded runner.arch with supported guest capabilities. Native platform matching remains in registrations.
- Proposed public CPU representation: constraint labels for x86_64/aarch64, validated and normalized through one explicit mapping to runtime PE identifiers. Do not scatter mappings or imply arbitrary labels mean arbitrary supported ABIs.
- Supervisor config carries supported guests and an optional declared guest. Inspect the actual PE, reject unsupported machines/declared mismatches before launching Wine.
- Validate ELF/Mach-O Wine and server against the supervisor's native CPU, not the guest CPU. Preserve format checks, teardown, environment/prefix isolation and exit behavior.
- Native Windows defaults remain same-CPU declarations; do not infer Windows-on-ARM emulation support.
- Keep one default runtime per executor pair. Capability lists do not participate in toolchain resolution.
- Preserve FilesToRunProvider runfiles, RunEnvironmentInfo forwarding where applicable, DLL adjacency and lazy Args serialization. No file-content reads in repository rules for generated payloads, filename inference, or eager execution-path strings.

## Decisions and release gates

1. The source graph was prototyped and then tested on Bazel 8.5 and 9.3: custom execution platforms, explicit target_platform, configuration-dependent imports, and real wrapper/payload machine headers with AEGs on and off. CPU constraint selects are explicit; no opaque platform-name inference.
2. Optional metadata signature and import ownership are settled above: provider-only import, original executable/runfiles retained, executable= accepts File, FilesToRunProvider, or Target. No additional consumer decision is needed for this correction.
3. Confirm acceptance of execution-time errors for undeclared prebuilts. The user accepted analysis errors for known mismatches and requested the simpler metadata-free default; do not claim all failures can occur in analysis.
4. Public default archives: gate resolved. On 2026-10-27 the user explicitly authorized publishing wine-prebuilt 11.20.1, and the main agent made that release non-draft without replacing any of its 38 assets. Anonymous checksum downloads for all three runtime archives succeeded. Use the public release URLs and verify the actual archives; prior same-commit CI artifacts have different hashes. The macOS unsigned/not-notarized status remains documented in the release notes.
5. Record exact verified archive hashes/layouts and host requirements. Linux glibc 2.17+ and locale requirements; macOS imposed deployment target 26.5 is distinct from build SDK and tested OS. Do not claim an older OS or exact-minimum runtime proof without evidence.
6. Preserve the adapter's target-and-exec affinity and fix its AEG alignment as specified above. Cross-building an adapter for an unrelated runtime platform is separate work; do not simply remove exec constraints.
7. README updates for this implementation were explicitly approved in the main thread on 2026-10-27. The user authorizes the implementation PR stack and release publication. No merging into main is authorized.

## Implementation sequence for the later agent

1. Reinspect Git state, plan review results and applicable instructions. Use an isolated branch/worktree for the implementation subagent; report it before editing. Apply Bazel skill for implementation.
2. Prove the source-default graph on Bazel 8.5 and 9: custom executor platform, default Windows CPU mapping, explicit override, prebuilt file unaffected. Inspect action/toolchain graphs and PE outputs.
3. Implement capability declarations and runtime checks, preserving native Windows direct actions and path/runfiles contracts.
4. Implement simple windows_binary defaults and optional windows_import/provider; settle low-level optional metadata handling and migrate existing callers.
5. Simplify the extension to verified first-party defaults; keep custom public toolchains, remove override composition. Respect the release gate.
6. Update examples/docs with approved README edits; format Starlark with buildifier and changed C++ with clang-format.
7. Run acceptance checks, collect exact evidence, commit task-owned changes in reviewable commits, and report limitations. Respect main-thread push permissions; do not merge or alter main without direction.

## Acceptance checks

| Scenario | Required observation |
| --- | --- |
| Bare amd64 PE on ARM64 macOS/Linux Wine/FEX | Runs; CPU detected from PE, no metadata wrapper |
| Source default on each supported Unix executor CPU | Windows PE CPU matches wrapper runtime platform CPU |
| Explicit Windows amd64 source platform on ARM64 executor | Builds amd64 and runs through supported Wine/FEX |
| Fixed prebuilt behind an executable target | Configuration does not mislabel it as executor-native |
| Prebuilt target using select() | Windows transition's effect is explicit; detected PE CPU is not inferred from configuration |
| Provider-only import of executable with adjacent DLLs | Original executable path/FTR/runfiles retained, no ownership violation or synthetic executable |
| AEG flag on/off with opposite-platform-first registration | Wrapper executable format/CPU matches its runtime platform; inspect wrapper as well as PE |
| Single-guest custom Wine + declared mismatch | Analysis error naming payload, runtime and supported guests |
| Single-guest custom Wine + undeclared mismatch | Clear runtime error before Wine startup |
| Incorrect explicit PE declaration | Wine-side runtime rejection of actual PE mismatch |
| Native Windows actions | Direct executable action graph; declared mismatch checked, no supervisor |
| Different final-product CPU | Does not constrain the Windows build tool's CPU |
| Runfiles, companion DLLs, argument/Unicode/exit behavior | Preserved for wrappers and direct action API |
| Optional path mapping off/on/collision fallback | Lazy paths and declared action inputs remain correct |
| RBE platform selection with both CPU platforms | Generated action chooses requested native CPU without provider-driven reselection |
| Missing compatible executor | Clear resolution/compatibility failure, no local-emulation fallback promise |
| Default setup versus custom-only registration | No forced default registration or unwanted override resolution |
| Unsupported PE / i386 through Wine | Explicit rejection; no accidental advertised support |
| Undeclared executable through native Windows action | OS determines execution; no promise to reject every unadvertised machine type |

Use real fixtures and existing meaningful tests. Demonstrate baseline same-CPU rejection before fixing it where feasible. Test packaged runtimes, not installed host Wine; inspect selected platforms, action inputs and output PE machines in addition to successful commands. State any unavailable executor coverage precisely. Full path isolation or no-emulation descendant enforcement is not implied.

## Research and evidence

- [Bazel toolchain resolution](https://bazel.build/extending/toolchains): providers cannot trigger executor reselection.
- [Bazel execution groups](https://bazel.build/extending/exec-groups): separately resolved platform/toolchain contexts for action groups.
- [Transition composition backport to 8.8](https://github.com/bazelbuild/bazel/pull/30330) and [9.2](https://github.com/bazelbuild/bazel/pull/29888): newer option, not available at the preserved 8.5 minimum.
- [Bazel 8.5 outgoing transition attributes](https://github.com/bazelbuild/bazel/blob/8.5.0/site/en/extending/config.md#defining-defining): resolved attributes permit the proposed macro/select boundary.
- [Bazel 8.5 executable ownership check](https://github.com/bazelbuild/bazel/blob/8.5.0/src/main/java/com/google/devtools/build/lib/analysis/starlark/StarlarkRuleConfiguredTargetUtil.java#L553-L559): metadata imports cannot forward another rule's executable through DefaultInfo.executable.
- [Automatic execution groups](https://bazel.build/extending/auto-exec-groups) and [hermetic-launcher template selection](https://github.com/hermeticbuild/hermetic-launcher/blob/v0.0.16/launcher/private/rules/lib.bzl): template and runtime platform alignment must be explicit.
- Neighboring rules_qemu user-mode extension supplies pinned defaults without arbitrary archive override tags; its system-mode tag is not a custom archive API.
- Neighboring wine-prebuilt manifest/tests define actual distributions; inspect them and release state rather than assuming uniform guest support.

## Progress log

- Original plan from side conversation reviewed in main thread.
- 2026-10-27: revised for ordinary executable inputs, automatic source defaults, optional metadata, defaults-only extension, custom toolchains and explicit RBE placement. Recorded error-timing tradeoff and draft-release gate.
- 2026-10-27: dedicated gpt-6-astra high read-only review returned conditional go. Incorporated provider-only import ownership, the low-level typed executable path, adapter AEG alignment, configuration-sensitive import semantics, and native Windows validation limits. No build/runtime prototype was performed during the review.
- Recommendation: proceed with the graph prototype after main-thread report/decision; defer implementation to a distinct Astra high agent. Public defaults remain gated on release availability. No implementation, commit or push performed.
- 2026-10-27: user authorized implementation, release publication, first PR removing wine.prebuilt, and remaining stacked PRs. Published https://github.com/hermeticbuild/wine-prebuilt/releases/tag/11.20.1; verified public checksum access and unchanged successful source workflow 40412084456 at 86f74a5c8bc92849f9784774510d74e6cd9e0cf2.
- Implementation agent: gpt-6-astra high, branch cerisier/remove-wine-prebuilt-tag, worktree /Users/corentinkerisit/.codex/worktrees/wine-runtime-stack/rules_wine. Root main checkout remains unchanged except this requested plan. README updates explicitly approved.

## Implementation evidence (2026-10-27)

- User approved README edits and implementation/pushes in the main thread.
- First stack PR removes `wine.prebuilt`; commit `18d9a34`. Extension and custom-only public toolchain consumer checks passed on Bazel 8.5/9.3 as applicable.
- Source graph prototype on both Bazel 8.5 and 9.3 demonstrated resolved macro CPU selects through the outgoing Windows transition after a consumer exec transition, plus an explicit Windows x86_64 override on an ARM64 wrapper.
- Metadata imports preserve original executable ownership, runfiles and environment. `data` is deliberately limited to companion default-output files; it does not import dependency runfiles or augment the original FilesToRunProvider runfiles tree. This keeps the action and wrapper contracts consistent without synthetic executables or manifests.
- Baseline supervisor from `18d9a34`, compiled natively on macOS ARM64, rejected the amd64 fixture with `CPU translation is unsupported`. Updated supervisor runs that same PE with the published macOS 11.20.1 runtime; fixture JSON records `child-ok`.
- Generic API checks passed: Starlark graph suites on Bazel 8.5/9.3, Linux x86_64 runtime integration (3 tests), default-source wrapper, typed DLL action and imported DLL wrapper.
- Release archive SHA-256 values and root-level bin/wine + bin/wineserver layout verified against public downloads. Linux manifests advertise glibc 2.17 plus UTF-8 locale; macOS deployment 26.5, SDK 26.5 and prior tested OS 26.6.2 are separate facts. Rules intentionally expose no i386 guest even where Linux archives contain it.

- Implementation review refined the low-level API: `executable=` accepts File, FilesToRunProvider, or Target. Pass `ctx.attr.tool` for a `windows_import`; provider membership on Target is exact. Bazel reports custom provider instances as `struct`, so accepting bare provider instances would require structural or reconstruction checks. The simpler Target boundary avoids that machinery and also preserves ordinary executable targets' files/runfiles. This replaced the initial bare-provider proposal; the main contract above reflects the implemented Target boundary.

## Completed implementation and checks

- PR #2 removed extension tags and transitive override composition, retaining custom-only public toolchains. The user merged it as `d3c7a6a`; the implementation stack was rebased onto that main revision without modifying the main checkout.
- PR #3 (`cerisier/multi-guest-wine-runtimes`, commit `3b998b8`) implements capability declarations, execution-time PE detection, source defaults and metadata imports. Known declarations fail in analysis; undeclared Wine payloads are checked before initialization; native Windows remains direct.
- `e2e/test_adapter_platforms.sh` passed on Bazel 8.5.0 and 9.3.1. Both native Linux CPUs, AEG enabled/disabled, opposite-platform-first registration, real ELF wrapper/PE payload machine inspection, explicit x86_64 override, and selected/fixed prebuilts passed.
- `e2e/test_starlark.sh` passed on both Bazel versions, including native Windows direct actions and declared mismatch, runfiles/sidecars/environment forwarding, typed imports, separate action groups, and missing compatible executors.
- Published 11.20.1 defaults expose five runners and three adapters. Linux ARM64/amd64 guest actions execute on native workers; ARM64's bare amd64 PE, amd64 source override, typed and wrapper adjacent-DLL cases all report successful child execution.
- The native macOS consumer passed on macOS 26.5.2 with Bazel 9.3.1 and SDK 26.5 override: default ARM64 source, explicit amd64 source and bare amd64 PE all execute. Every wrapper is Mach-O ARM64; source PE headers are ARM64 and amd64 as requested. AEG enabled/disabled preserves wrapper CPU. Both custom-only toolchains and the default extension registration passed.
- macOS prefix initialization prints a `virtual_alloc_first_teb` assertion. Bare published Wine reproduces the same message and returns zero; independent ARM64 and amd64 fixtures then run successfully. This is an existing distribution bootstrap caveat. No runtime result on exact minimum macOS 26.5 or native Windows is claimed.

- Final first-party checks passed: extension checks on Bazel 8.5/9.3; native Linux multi-guest/action-platform matrix on both; mapped/unmapped/collision paths and argv on both; Linux lifecycle/layout/argv integration on 9.3 (3/3). Source and runtime changes passed narrow reviews, buildifier, clang-format and diff whitespace checks.
- Native Windows and Intel macOS execution, exact macOS 26.5 minimum, quarantined-download Gatekeeper acceptance and process-tree no-emulation enforcement remain outside demonstrated coverage. Linux release manifests declare glibc 2.17 compatibility; rules integration ran on Ubuntu 24.04 rather than re-proving the old-libc qualification.
