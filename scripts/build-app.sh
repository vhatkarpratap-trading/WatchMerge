#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
build_cache="/private/tmp/mergewatch-clang-cache"
swift_cache="/private/tmp/mergewatch-swift-cache"

cd "$root"
env CLANG_MODULE_CACHE_PATH="$build_cache" SWIFT_MODULECACHE_PATH="$swift_cache" swift build --disable-sandbox

app="$root/dist/MergeWatch.app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/debug/MergeWatch" "$app/Contents/MacOS/MergeWatch"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/PkgInfo" "$app/Contents/PkgInfo"
codesign --force --sign - "$app"

echo "Built $app"
