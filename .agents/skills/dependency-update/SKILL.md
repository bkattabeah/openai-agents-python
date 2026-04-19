# Dependency Update Skill

This skill automates the process of checking for outdated dependencies and creating pull requests to update them.

## What it does

1. Scans `pyproject.toml` and `requirements*.txt` files for dependencies
2. Checks for newer versions available on PyPI
3. Runs the test suite to verify compatibility
4. Summarizes findings with recommended updates

## When to use

- Scheduled dependency audits
- Before major releases
- When security advisories mention outdated packages
- Routine maintenance cycles

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `check_only` | No | `false` | Only report outdated deps, do not modify files |
| `include_dev` | No | `true` | Include dev/test dependencies in the check |
| `min_severity` | No | `patch` | Minimum update type to flag: `patch`, `minor`, `major` |

## Outputs

- A markdown report listing all outdated packages
- Updated dependency files (if `check_only` is false)
- Exit code `0` if all deps are up-to-date, `1` if updates are available

## Usage

```bash
bash .agents/skills/dependency-update/scripts/run.sh
```

Or on Windows:

```powershell
.agents/skills/dependency-update/scripts/run.ps1
```

## Requirements

- Python 3.9+
- `pip` available on PATH
- Internet access to reach PyPI

## Notes

- The skill respects version constraints defined in `pyproject.toml`.
- It will not suggest updates that violate existing version pins.
- When `include_dev` is enabled, extras such as `[dev]` and `[test]` are included.
