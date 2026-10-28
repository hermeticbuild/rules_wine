#!/usr/bin/env bash
# Called by bazel-contrib's release workflow; optional ref supports local dry runs.
set -euo pipefail
tag=${1:?usage: release_prep.sh vVERSION [git-ref]}
ref=${2:-$tag}
root=$(cd "$(dirname "$0")/../.." && pwd)
if [[ ! $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo "Expected a v-prefixed release version, got: $tag" >&2
  exit 1
fi
prefix="rules_wine-${tag#v}"
archive="rules_wine-$tag.tar.gz"
git -C "$root" archive --format=tar --prefix="$prefix/" "$ref" | gzip -n > "$archive"
checksum=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
cat <<EOF
## Bzlmod

After the BCR submission is merged, add:

\`\`\`starlark
bazel_dep(name = "rules_wine", version = "${tag#v}")
wine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")
use_repo(wine, "wine_toolchains")
register_toolchains("@wine_toolchains//:all")
\`\`\`

Requires Bazel 8.5 or newer. Linux/macOS execution compiles the supervisor with
your selected C++17 toolchain. See the README for runtime platform requirements.

Archive SHA-256: \`$checksum\`
EOF
