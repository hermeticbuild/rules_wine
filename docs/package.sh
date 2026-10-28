#!/usr/bin/env bash
# Build the BCR API reference from this checkout; no Markdown renderer required.
set -euo pipefail
archive=${1:?usage: docs/package.sh /path/to/docs.tar.gz [bazel-build-options...]}
shift
archive=$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
bazel build //docs:api "$@" >&2
files=$(mktemp)
bazel cquery //docs:api "$@" --output=starlark \
  --starlark:expr='"\n".join(sorted([f.short_path for f in target.files.to_list()]))' > "$files"
tar -czf "$archive" -C "$(bazel info bazel-bin "$@")" -T "$files"
echo "API documentation: $archive" >&2
