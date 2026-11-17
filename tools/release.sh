#!/bin/sh
# Builds a Release copy of Expenses.app into dist/ and zips it. Run from the workspace root.
set -e
cd "$(dirname "$0")/.."
xcodebuild -project Expenses/Expenses.xcodeproj -scheme Expenses -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build build 2>&1 | tail -3
rm -rf dist && mkdir -p dist
cp -R build/Build/Products/Release/Expenses.app dist/
ditto -c -k --keepParent dist/Expenses.app dist/Expenses.zip
ls -la dist
