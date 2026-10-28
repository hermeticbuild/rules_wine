#!/usr/bin/env bash
# Exercise the release layout without creating a tag or publishing anything.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/rules-wine-release.XXXXXX")
echo "Archive verification: $scratch"
cd "$scratch"
bash "$root/.github/workflows/release_prep.sh" v0.0.0-ci HEAD > release-notes.md
tar -tzf rules_wine-v0.0.0-ci.docs.tar.gz | LC_ALL=C sort > actual-docs.txt
printf '%s\n' \
  wine/actions.doc_extract.binaryproto \
  wine/extension/wine.doc_extract.binaryproto \
  wine/toolchain.doc_extract.binaryproto \
  wine/windows_binary.doc_extract.binaryproto > expected-docs.txt
diff -u expected-docs.txt actual-docs.txt
tar -xzf rules_wine-v0.0.0-ci.tar.gz
cd rules_wine-0.0.0-ci
test -f LICENSE
test -f .bcr/presubmit.yml
test -f .bcr/source.template.json
test -f wine/runtime/supervisor.cc
cd e2e/smoke
trap 'bazel --nosystem_rc --nohome_rc shutdown >/dev/null 2>&1' EXIT
bazel --nosystem_rc --nohome_rc test //:x86_64_test --lockfile_mode=off "$@"
