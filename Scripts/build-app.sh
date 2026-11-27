#!/bin/sh
set -eu

project=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project"

swift build --arch arm64 --configuration release >&2
bin=$(swift build --arch arm64 --configuration release --show-bin-path)
bundle="$project/.build/omiyaIME.app"
rm -rf "$bundle"

mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$project/Bundle/Info.plist" "$bundle/Contents/Info.plist"
cp "$project/Bundle/Resources/"*.tiff "$project/Bundle/Resources/"*.png "$bundle/Contents/Resources/"
cp -R "$project/Bundle/Resources/"*.lproj "$bundle/Contents/Resources/"
cp "$bin/omiyaIME" "$bundle/Contents/MacOS/omiyaIME"
plutil -lint "$bundle/Contents/Info.plist" >&2
if [ -n "${OMIYAIME_MOZC_DIR:-}" ]; then
    cp "$OMIYAIME_MOZC_DIR/omiya-mozc" "$bundle/Contents/MacOS/"
    cp "$OMIYAIME_MOZC_DIR/mozc.data" "$OMIYAIME_MOZC_DIR/Mozc-LICENSE.txt" \
        "$OMIYAIME_MOZC_DIR/Mozc-dictionary-terms.txt" "$OMIYAIME_MOZC_DIR/Mozc-third-party-notices.txt" \
        "$bundle/Contents/Resources/"
    helper="$bundle/Contents/MacOS/omiya-mozc"
    if [ -n "${OMIYAIME_SIGNING_IDENTITY:-}" ]; then
        codesign --force --options runtime --timestamp --sign "$OMIYAIME_SIGNING_IDENTITY" "$helper"
    else
        codesign --force --sign - "$helper"
    fi
    codesign --verify --strict "$helper"
fi
if [ -n "${OMIYAIME_SIGNING_IDENTITY:-}" ]; then
    codesign --options runtime --timestamp --sign "$OMIYAIME_SIGNING_IDENTITY" "$bundle"
else
    codesign --sign - "$bundle"
fi
codesign --verify --strict "$bundle"
printf '%s\n' "$bundle"
