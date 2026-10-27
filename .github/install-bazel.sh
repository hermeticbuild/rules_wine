#!/usr/bin/env bash
# Install the matrix's pinned native Bazel, including native Windows ARM64.
set -euo pipefail
case "$RUNNER_OS" in
  Linux) os=linux; suffix= ;;
  macOS) os=darwin; suffix= ;;
  Windows) os=windows; suffix=.exe ;;
esac
case "$RUNNER_ARCH" in
  X64) cpu=x86_64 ;;
  ARM64) cpu=arm64 ;;
esac
mkdir -p "$RUNNER_TEMP/bazel"
cd "$RUNNER_TEMP/bazel"
name="bazel-$USE_BAZEL_VERSION-$os-$cpu$suffix"
url="https://github.com/bazelbuild/bazel/releases/download/$USE_BAZEL_VERSION/$name"
curl --fail --location --retry 3 "$url" -o "$name"
curl --fail --location --retry 3 "$url.sha256" -o "$name.sha256"
if [[ $RUNNER_OS == macOS ]]; then
  shasum -a 256 -c "$name.sha256"
else
  sha256sum -c "$name.sha256"
fi
mv "$name" "bazel$suffix"
chmod +x "bazel$suffix"
echo "$RUNNER_TEMP/bazel" >> "$GITHUB_PATH"
