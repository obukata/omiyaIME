#!/bin/sh
set -eu

project=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
revision=04d909a1a4a3fc59769a53697ceac67e68606681
if [ "$#" -ne 1 ] || ! git -C "$1" cat-file -e "$revision^{commit}" 2>/dev/null; then
    printf '%s\n' "Supply a local Mozc checkout containing $revision." >&2
    exit 1
fi

mkdir -p "$project/.build"
work=$(mktemp -d "$project/.build/mozc.XXXXXXXX")
mkdir "$work/source" "$work/output"
git -C "$1" archive --output="$work/upstream.tar" "$revision"
tar -xf "$work/upstream.tar" -C "$work/source"
cd "$work/source"
git apply --check "$project/Mozc/disable-file-history.patch"
git apply "$project/Mozc/disable-file-history.patch"
git apply --check "$project/Mozc/symbol-rewriter-visibility.patch"
git apply "$project/Mozc/symbol-rewriter-visibility.patch"
cp "$project/Mozc/worker.cc" src/converter/omiya_mozc_worker.cc
printf '\n' >> src/converter/BUILD.bazel
cat "$project/Mozc/worker-target.bazel" >> src/converter/BUILD.bazel

cd src
python3 build_tools/update_deps.py --noqt >&2
bazelisk build --macos_cpus=arm64 --macos_minimum_os=26.0 //converter:omiya-mozc //data_manager/oss:mozc.data >&2
cp bazel-bin/converter/omiya-mozc bazel-bin/data_manager/oss/mozc.data "$work/output/"
cp ../LICENSE "$work/output/Mozc-LICENSE.txt"
cp data/dictionary_oss/README.txt "$work/output/Mozc-dictionary-terms.txt"
bazel_out=$(CDPATH='' cd bazel-out && pwd -P)
external_dir="${bazel_out%/*}/external"
{
    for notice in abseil-cpp+/LICENSE protobuf+/LICENSE protobuf+/third_party/utf8_range/LICENSE zlib+/LICENSE; do
        printf '\n--- %s ---\n\n' "$notice"
        cat "$external_dir/$notice"
    done
} > "$work/output/Mozc-third-party-notices.txt"
printf '%s\n' "$work/output"
