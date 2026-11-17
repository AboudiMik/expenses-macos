#!/bin/sh
# Builds a Release copy of Expenses.app (minimum macOS 15.0) into dist/, zips it,
# and assembles the reviewer bundle dist/Expenses-Abdulghani-Mikati.zip. Run from anywhere.
set -e
cd "$(dirname "$0")/.."
xcodebuild -project Expenses/Expenses.xcodeproj -scheme Expenses -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build MACOSX_DEPLOYMENT_TARGET=15.0 build 2>&1 | tail -3
rm -rf dist && mkdir -p dist/submission/samples
cp -R build/Build/Products/Release/Expenses.app dist/
ditto -c -k --norsrc --keepParent dist/Expenses.app dist/Expenses.zip

cp -R dist/Expenses.app dist/submission/
cp docs/REPORT.pdf docs/README.pdf tools/submission/START-HERE.txt dist/submission/
cp tools/samples/*.pdf dist/submission/samples/
ls tools/eval_images/*.png | head -3 | xargs -I{} cp {} dist/submission/samples/
(cd dist && ditto -c -k --norsrc --keepParent submission Expenses-Abdulghani-Mikati.zip)
ls -la dist
