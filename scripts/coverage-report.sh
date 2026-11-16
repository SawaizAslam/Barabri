#!/usr/bin/env bash
# Generates llvm-cov text and lcov reports from a prior `swift test --enable-code-coverage` run.
set -euo pipefail

BIN_PATH="$(swift build --show-bin-path)"
PROFDATA="$BIN_PATH/codecov/default.profdata"
TEST_BINARY="$BIN_PATH/BarabriCoreTests.xctest/Contents/MacOS/BarabriCoreTests"

if [[ ! -f "$PROFDATA" ]]; then
  echo "error: coverage profile not found at $PROFDATA" >&2
  echo "       run 'swift test --enable-code-coverage' first" >&2
  exit 1
fi

if [[ ! -f "$TEST_BINARY" ]]; then
  echo "error: test binary not found at $TEST_BINARY" >&2
  echo "       run 'swift test --enable-code-coverage' first" >&2
  exit 1
fi

mkdir -p coverage

xcrun llvm-cov report "$TEST_BINARY" \
  -instr-profile "$PROFDATA" \
  -ignore-filename-regex='(\.build|Tests)/' > coverage/coverage-report.txt

xcrun llvm-cov export "$TEST_BINARY" \
  -instr-profile "$PROFDATA" \
  -ignore-filename-regex='(\.build|Tests)/' \
  -format=lcov > coverage/coverage.lcov

cat coverage/coverage-report.txt
