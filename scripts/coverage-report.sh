#!/usr/bin/env bash
# Generates llvm-cov text and lcov reports from a prior `swift test --enable-code-coverage` run.
set -euo pipefail

BIN_PATH="$(swift build --show-bin-path)"
PROFDATA="$BIN_PATH/codecov/default.profdata"

if [[ ! -f "$PROFDATA" ]]; then
  echo "error: coverage profile not found at $PROFDATA" >&2
  echo "       run 'swift test --enable-code-coverage' first" >&2
  exit 1
fi

# The test bundle name differs between toolchains, so locate it rather than hard-coding it.
shopt -s nullglob
BUNDLES=("$BIN_PATH"/*.xctest)
shopt -u nullglob

if [[ ${#BUNDLES[@]} -eq 0 ]]; then
  echo "error: no .xctest bundle found in $BIN_PATH" >&2
  echo "       run 'swift test --enable-code-coverage' first" >&2
  exit 1
fi

# Every test bundle contributes coverage, so every test binary is handed to llvm-cov.
TEST_BINARIES=()
for BUNDLE in "${BUNDLES[@]}"; do
  TEST_BINARY="$BUNDLE/Contents/MacOS/$(basename "$BUNDLE" .xctest)"

  if [[ ! -f "$TEST_BINARY" ]]; then
    echo "error: test binary not found at $TEST_BINARY" >&2
    echo "       run 'swift test --enable-code-coverage' first" >&2
    exit 1
  fi

  echo "using test binary: $TEST_BINARY" >&2
  TEST_BINARIES+=("$TEST_BINARY")
done

# The first binary is the positional argument; each further one is passed with -object.
LLVM_COV_OBJECTS=()
for ((i = 1; i < ${#TEST_BINARIES[@]}; i++)); do
  LLVM_COV_OBJECTS+=(-object "${TEST_BINARIES[$i]}")
done

mkdir -p coverage

xcrun llvm-cov report "${TEST_BINARIES[0]}" \
  ${LLVM_COV_OBJECTS[@]+"${LLVM_COV_OBJECTS[@]}"} \
  -instr-profile "$PROFDATA" \
  -ignore-filename-regex='(\.build|Tests)/' > coverage/coverage-report.txt

xcrun llvm-cov export "${TEST_BINARIES[0]}" \
  ${LLVM_COV_OBJECTS[@]+"${LLVM_COV_OBJECTS[@]}"} \
  -instr-profile "$PROFDATA" \
  -ignore-filename-regex='(\.build|Tests)/' \
  -format=lcov > coverage/coverage.lcov

cat coverage/coverage-report.txt
