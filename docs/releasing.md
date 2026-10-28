# Releasing rules_wine

Release only a reviewed commit on `main` with passing **Test** and
**Repository checks** workflows. The Wine runtime archives have their own release
process in `wine-prebuilt`; this repository publishes Bazel rules and the
supervisor source, not another Wine build.

## Local checks

```sh
bazel run //.github/workflows:buildifier.check
e2e/test_runtime.sh
(cd e2e/smoke && bazel test //:x86_64_test)
.github/workflows/check_archive.sh
```

`check_archive.sh` packages **HEAD**, extracts it into a temporary directory and
runs the downstream test there. Commit changes before running it. It uses the
same `release_prep.sh` as the release workflow and leaves the archive, notes and
test workspace at the printed path. On ARM64 Linux/macOS, also run
`//:aarch64_test`; on Windows ARM64 use that target instead of `//:x86_64_test`.
Local Wine tests require an installed C++17 compiler. Full native platform and
Bazel-version coverage runs in GitHub Actions.

## Publish a version

1. Update `MODULE.bazel`'s version and the downstream consumer's `bazel_dep` version
   in a reviewed PR. Keep supported versions and platform requirements in the
   README accurate.
2. Tag the approved commit, for example `git tag v0.1.0 <commit>`, then explicitly
   push it: `git push origin v0.1.0`. There is no scheduled tagging workflow.
3. The release workflow reruns the native matrix, formatting and archive checks.
   The maintained `bazel-contrib` release workflow then tests the consumer,
   creates `rules_wine-v0.1.0.tar.gz`, attests it and uploads a draft release.
4. The maintained `publish-to-bcr` workflow uses `.bcr/` templates to calculate
   source integrity, prepare the registry entry and its attestations, and open a
   draft BCR PR through `hermeticbuild/bazel-central-registry`. It uses the
   organization-provided `BCR_PUBLISH_TOKEN` secret.
5. After BCR submission succeeds, the workflow publishes the GitHub release.
   Review the BCR PR, mark it ready, and address its checks. The module becomes
   available from the BCR only when that PR is merged.

The draft release allows all attestations to be attached before publication,
including when GitHub immutable releases are enabled. If submission fails, fix
the configuration or credentials and rerun the failed jobs while the release is
still a draft. Do not move a published tag or replace a published archive.

For a local packaging dry run, from an empty output directory:

```sh
/path/to/rules_wine/.github/workflows/release_prep.sh v0.1.0 HEAD
```

The optional second argument is a Git ref; an actual release defaults to the tag
itself. Archives contain committed files under `rules_wine-0.1.0/`. Release notes
include the SHA-256; `.bcr/source.template.json` uses the matching archive name
and prefix. The publish workflow handles registry version stamping and integrity.

## BCR coverage and remaining boundaries

`.bcr/presubmit.yml` runs the extracted downstream module on Bazel 8.x and 9.x:

- Ubuntu 24.04 amd64: Windows amd64, action and adapter.
- Ubuntu 24.04 ARM64: Windows ARM64 and amd64/FEX, action and adapter.
- Windows amd64: direct Windows amd64 action.

The shell tests inspect records produced by real Windows programs, including
arguments, generated input, environment and child execution. GitHub's native
matrix additionally covers macOS 26 ARM64 and Windows ARM64. The BCR macOS worker
baseline is not claimed to satisfy Wine's macOS 26.5 deployment minimum, so macOS
Wine execution is not included in the BCR presubmit. These tests do not prove the
minimum Linux glibc or exact macOS deployment baseline.

Before the first release, PR CI establishes formatting, archive layout and local
downstream behavior. Signing, release upload and the actual BCR submission can
only be verified during a real release; they are not exercised by PR workflows.
