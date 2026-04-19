# Examples Auto-Run Script for Windows
# Discovers and runs all example files in the examples/ directory,
# capturing output and reporting success/failure for each.

param(
    [string]$ExamplesDir = "examples",
    [string]$PythonCmd = "python",
    [int]$TimeoutSeconds = 60,
    [switch]$StopOnFailure
)

$ErrorActionPreference = "Continue"
$PassCount = 0
$FailCount = 0
$SkipCount = 0
$Results = @()

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Write-Result {
    param([string]$File, [string]$Status, [string]$Detail = "")
    switch ($Status) {
        "PASS" { Write-Host "  [PASS] $File" -ForegroundColor Green }
        "FAIL" { Write-Host "  [FAIL] $File" -ForegroundColor Red }
        "SKIP" { Write-Host "  [SKIP] $File" -ForegroundColor Yellow }
    }
    if ($Detail) {
        Write-Host "         $Detail" -ForegroundColor Gray
    }
}

# Verify examples directory exists
if (-not (Test-Path $ExamplesDir)) {
    Write-Host "ERROR: Examples directory '$ExamplesDir' not found." -ForegroundColor Red
    exit 1
}

# Check for required API keys
$RequiredEnvVars = @("OPENAI_API_KEY")
foreach ($Var in $RequiredEnvVars) {
    if (-not [System.Environment]::GetEnvironmentVariable($Var)) {
        Write-Host "WARNING: Environment variable '$Var' is not set. Some examples may fail." -ForegroundColor Yellow
    }
}

Write-Header "Discovering examples in '$ExamplesDir'"

# Find all Python example files
$ExampleFiles = Get-ChildItem -Path $ExamplesDir -Recurse -Filter "*.py" |
    Where-Object { $_.Name -notmatch "^_" } |
    Sort-Object FullName

if ($ExampleFiles.Count -eq 0) {
    Write-Host "No example files found in '$ExamplesDir'." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($ExampleFiles.Count) example file(s)." -ForegroundColor White

Write-Header "Running examples"

foreach ($File in $ExampleFiles) {
    $RelativePath = $File.FullName.Substring((Get-Location).Path.Length + 1)

    # Check for skip marker in file
    $Content = Get-Content $File.FullName -Raw -ErrorAction SilentlyContinue
    if ($Content -match "# skip-auto-run") {
        $SkipCount++
        $Results += [PSCustomObject]@{ File = $RelativePath; Status = "SKIP"; Reason = "skip-auto-run marker" }
        Write-Result -File $RelativePath -Status "SKIP" -Detail "skip-auto-run marker found"
        continue
    }

    try {
        $Process = Start-Process -FilePath $PythonCmd `
            -ArgumentList $File.FullName `
            -PassThru -NoNewWindow `
            -RedirectStandardOutput "$env:TEMP\example_stdout.txt" `
            -RedirectStandardError "$env:TEMP\example_stderr.txt"

        $Finished = $Process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $Finished) {
            $Process.Kill()
            $FailCount++
            $Results += [PSCustomObject]@{ File = $RelativePath; Status = "FAIL"; Reason = "Timeout after ${TimeoutSeconds}s" }
            Write-Result -File $RelativePath -Status "FAIL" -Detail "Timeout after ${TimeoutSeconds}s"
        } elseif ($Process.ExitCode -eq 0) {
            $PassCount++
            $Results += [PSCustomObject]@{ File = $RelativePath; Status = "PASS"; Reason = "" }
            Write-Result -File $RelativePath -Status "PASS"
        } else {
            $StderrContent = Get-Content "$env:TEMP\example_stderr.txt" -Raw -ErrorAction SilentlyContinue
            $ShortError = if ($StderrContent) { ($StderrContent -split "`n")[0].Trim() } else { "exit code $($Process.ExitCode)" }
            $FailCount++
            $Results += [PSCustomObject]@{ File = $RelativePath; Status = "FAIL"; Reason = $ShortError }
            Write-Result -File $RelativePath -Status "FAIL" -Detail $ShortError
        }
    } catch {
        $FailCount++
        $Results += [PSCustomObject]@{ File = $RelativePath; Status = "FAIL"; Reason = $_.Exception.Message }
        Write-Result -File $RelativePath -Status "FAIL" -Detail $_.Exception.Message
    }

    if ($StopOnFailure -and $FailCount -gt 0) {
        Write-Host "`nStopping on first failure (--StopOnFailure set)." -ForegroundColor Red
        break
    }
}

# Summary
Write-Header "Summary"
Write-Host "  Passed:  $PassCount" -ForegroundColor Green
Write-Host "  Failed:  $FailCount" -ForegroundColor $(if ($FailCount -gt 0) { "Red" } else { "White" })
Write-Host "  Skipped: $SkipCount" -ForegroundColor Yellow
Write-Host ""

if ($FailCount -gt 0) {
    Write-Host "Failed examples:" -ForegroundColor Red
    $Results | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.File): $($_.Reason)" -ForegroundColor Red
    }
    exit 1
}

Write-Host "All examples passed." -ForegroundColor Green
exit 0
