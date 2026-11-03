#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quick-port-layout.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" macos/QuickPort.swift scripts/LayoutTests.swift -o "$TEST_DIR/layout-tests"
"$TEST_DIR/layout-tests"
