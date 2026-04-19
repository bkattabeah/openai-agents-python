#!/bin/bash
# examples-auto-run skill script
# Automatically discovers and runs all examples in the repository,
# reporting which pass and which fail.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
EXAMPLES_DIR="${REPO_ROOT}/examples"
RESULTS_FILE="${REPO_ROOT}/.agents/skills/examples-auto-run/results.md"
PASS=0
FAIL=0
SKIP=0
FAILED_EXAMPLES=()

echo "# Examples Auto-Run Results" > "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"
echo "Run at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

if [ ! -d "$EXAMPLES_DIR" ]; then
  echo "ERROR: examples directory not found at $EXAMPLES_DIR"
  exit 1
fi

# Ensure dependencies are installed
cd "$REPO_ROOT"
if [ -f "pyproject.toml" ]; then
  echo "Installing project dependencies..."
  pip install -e ".[dev]" --quiet 2>&1 || pip install -e . --quiet 2>&1
fi

# Find all runnable example files
mapfile -t EXAMPLE_FILES < <(find "$EXAMPLES_DIR" -name "*.py" | sort)

if [ ${#EXAMPLE_FILES[@]} -eq 0 ]; then
  echo "No example files found in $EXAMPLES_DIR"
  echo "No examples found." >> "$RESULTS_FILE"
  exit 0
fi

echo "Found ${#EXAMPLE_FILES[@]} example file(s). Running..."
echo "## Results" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"
echo "| Example | Status | Notes |" >> "$RESULTS_FILE"
echo "|---------|--------|-------|" >> "$RESULTS_FILE"

for example in "${EXAMPLE_FILES[@]}"; do
  rel_path="${example#$REPO_ROOT/}"

  # Skip examples that require interactive input or special env vars not set
  if grep -qE 'input\(|getpass\.' "$example" 2>/dev/null; then
    echo "  SKIP  $rel_path (requires interactive input)"
    echo "| \`$rel_path\` | ⏭ SKIP | requires interactive input |" >> "$RESULTS_FILE"
    SKIP=$((SKIP + 1))
    continue
  fi

  # Check for required env vars declared in the file
  if grep -qE 'os\.environ\[|os\.getenv' "$example" 2>/dev/null; then
    missing_vars=0
    while IFS= read -r var; do
      var_name=$(echo "$var" | grep -oP '(?<=[\[\(]["\x27])[A-Z_]+(?=["\x27][\]\)])' | head -1)
      if [ -n "$var_name" ] && [ -z "${!var_name:-}" ]; then
        missing_vars=$((missing_vars + 1))
      fi
    done < <(grep -E 'os\.environ\[|os\.getenv' "$example")
    if [ "$missing_vars" -gt 0 ]; then
      echo "  SKIP  $rel_path (missing env vars)"
      echo "| \`$rel_path\` | ⏭ SKIP | missing required env vars |" >> "$RESULTS_FILE"
      SKIP=$((SKIP + 1))
      continue
    fi
  fi

  # Run example with a timeout
  echo -n "  RUN   $rel_path ... "
  set +e
  output=$(cd "$REPO_ROOT" && timeout 30 python "$example" 2>&1)
  exit_code=$?
  set -e

  if [ $exit_code -eq 0 ]; then
    echo "PASS"
    echo "| \`$rel_path\` | ✅ PASS | |" >> "$RESULTS_FILE"
    PASS=$((PASS + 1))
  elif [ $exit_code -eq 124 ]; then
    echo "TIMEOUT"
    echo "| \`$rel_path\` | ⏱ TIMEOUT | exceeded 30s |" >> "$RESULTS_FILE"
    FAIL=$((FAIL + 1))
    FAILED_EXAMPLES+=("$rel_path (timeout)")
  else
    echo "FAIL (exit $exit_code)"
    short_error=$(echo "$output" | tail -3 | tr '\n' ' ' | cut -c1-120)
    echo "| \`$rel_path\` | ❌ FAIL | \`$short_error\` |" >> "$RESULTS_FILE"
    FAIL=$((FAIL + 1))
    FAILED_EXAMPLES+=("$rel_path")
  fi
done

# Summary
echo "" >> "$RESULTS_FILE"
echo "## Summary" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"
echo "- ✅ Passed: $PASS" >> "$RESULTS_FILE"
echo "- ❌ Failed: $FAIL" >> "$RESULTS_FILE"
echo "- ⏭ Skipped: $SKIP" >> "$RESULTS_FILE"

echo ""
echo "=============================="
echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "=============================="

if [ ${#FAILED_EXAMPLES[@]} -gt 0 ]; then
  echo "Failed examples:"
  for f in "${FAILED_EXAMPLES[@]}"; do
    echo "  - $f"
  done
  echo ""
  echo "Full results written to: $RESULTS_FILE"
  exit 1
fi

echo "All runnable examples passed."
echo "Full results written to: $RESULTS_FILE"
