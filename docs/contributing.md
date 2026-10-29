# Maintaining the Starlark API

Document public functions in their docstrings, rules and extensions in `doc`,
and attributes in `attr.*(doc = ...)`. Keep examples and platform explanations
in the guides; the generated reference describes signatures and contracts.

After changing `.bzl` files or their `load()` dependencies:

The root test suite needs a Linux executor; see the [test prerequisites](../tests/README.md)
for native and remote execution commands.

```sh
bazel run //tools/gazelle:update
bazel run //tools/gazelle:check
bazel test //...
```

Gazelle runs only the Skylib Starlark plugin and only scans `wine/`. Its generated
`bzl_library` declarations use bazel-lib, which creates `starlark_doc_extract`
targets in public packages. Extraction checks the declared load dependencies.
`docs/BUILD.bazel` selects the public entry points included in the release.
When adding one, update that list and the archive check's expected file list.
To package the reference locally, run `bash docs/package.sh /tmp/rules_wine.docs.tar.gz`.

Two dependency lists use Gazelle's `# keep`: the launcher library has an upstream
`lib_bzl` target name that the plugin cannot infer, and Bazel's `http.bzl` needs
its transitive source files listed explicitly. Update those lists when their
loads change; documentation extraction checks them as well.

Gazelle and its plugin are dev dependencies, with their BUILD loads confined to
`tools/gazelle`. Downstream builds do not need the generator or its Go toolchain.
bazel-lib is a regular dependency because `wine/` BUILD files load its macro.

The docs archive contains binary protobufs consumed by the BCR UI. To inspect a
page locally without installing a renderer, build its text representation:

```sh
bazel build //wine:actions.doc_extract.textproto
cat bazel-bin/wine/actions.doc_extract.textproto
```

CI checks that Gazelle produces no changes and builds the release docs on Bazel
8 and 9. Release preparation extracts documentation from the committed source
archive, then publishes both archives with provenance attestations. See
[releasing](releasing.md) and the
[BCR documentation format](https://github.com/bazelbuild/bazel-central-registry/blob/main/docs/stardoc.md).

For runtime changes, see [the test suite](../tests/README.md).
