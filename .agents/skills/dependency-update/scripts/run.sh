#!/bin/bash
# Dependency Update Skill
# Checks for outdated dependencies and creates update PRs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

echo "=== Dependency Update Skill ==="
echo "Repo root: $REPO_ROOT"
cd "$REPO_ROOT"

# Check required tools
for tool in python3 pip git; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: Required tool '$tool' not found."
    exit 1
  fi
done

# Check for uv (preferred) or fall back to pip
USE_UV=false
if command -v uv &>/dev/null; then
  USE_UV=true
  echo "Using uv for dependency management"
else
  echo "Using pip for dependency management"
fi

OUTDATED_FILE="/tmp/outdated_deps.txt"
UPDATE_SUMMARY="/tmp/update_summary.txt"
> "$UPDATE_SUMMARY"

echo "--- Checking for outdated dependencies ---"

if [ "$USE_UV" = true ]; then
  uv pip list --outdated 2>/dev/null | tee "$OUTDATED_FILE" || true
else
  pip list --outdated --format=columns 2>/dev/null | tee "$OUTDATED_FILE" || true
fi

if [ ! -s "$OUTDATED_FILE" ]; then
  echo "All dependencies are up to date."
  exit 0
fi

OUTDATED_COUNT=$(tail -n +3 "$OUTDATED_FILE" | wc -l | tr -d ' ')
echo "Found $OUTDATED_COUNT outdated package(s)."

# Parse pyproject.toml to find which packages are direct dependencies
DIRECT_DEPS_FILE="/tmp/direct_deps.txt"
python3 - <<'EOF' > "$DIRECT_DEPS_FILE"
import re, sys
try:
    with open("pyproject.toml") as f:
        content = f.read()
    # Extract dependency names from pyproject.toml
    matches = re.findall(r'["\']?([A-Za-z0-9_\-]+)["\']?\s*[><=!~]', content)
    for m in set(matches):
        print(m.lower())
except FileNotFoundError:
    sys.exit(0)
EOF

echo "--- Direct dependencies identified ---"
cat "$DIRECT_DEPS_FILE"

# Identify outdated direct dependencies
echo "--- Outdated direct dependencies ---" | tee -a "$UPDATE_SUMMARY"
UPDATE_COUNT=0

while IFS= read -r line; do
  # Skip header lines
  [[ "$line" =~ ^Package|^---|- ]] && continue
  [ -z "$line" ] && continue

  PKG_NAME=$(echo "$line" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
  CURRENT=$(echo "$line" | awk '{print $2}')
  LATEST=$(echo "$line" | awk '{print $3}')

  if grep -qi "^${PKG_NAME}$" "$DIRECT_DEPS_FILE" 2>/dev/null; then
    echo "  [DIRECT] $PKG_NAME: $CURRENT -> $LATEST" | tee -a "$UPDATE_SUMMARY"
    UPDATE_COUNT=$((UPDATE_COUNT + 1))
  else
    echo "  [TRANSITIVE] $PKG_NAME: $CURRENT -> $LATEST" | tee -a "$UPDATE_SUMMARY"
  fi
done < <(tail -n +3 "$OUTDATED_FILE")

echo "" | tee -a "$UPDATE_SUMMARY"
echo "Total direct deps to update: $UPDATE_COUNT" | tee -a "$UPDATE_SUMMARY"

# Run safety/audit check if available
echo "--- Security audit ---"
if command -v pip-audit &>/dev/null; then
  pip-audit 2>&1 | tee -a "$UPDATE_SUMMARY" || echo "pip-audit found issues (see above)"
elif [ "$USE_UV" = true ] && uv pip show pip-audit &>/dev/null 2>&1; then
  uv run pip-audit 2>&1 | tee -a "$UPDATE_SUMMARY" || echo "pip-audit found issues (see above)"
else
  echo "pip-audit not installed, skipping security audit."
fi

echo ""
echo "=== Summary ==="
cat "$UPDATE_SUMMARY"
echo ""
echo "Review the above and update pyproject.toml accordingly."
echo "Run 'uv lock' or 'pip-compile' to regenerate lock files after updating."
