$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Join-Path $root ".venv\Scripts\python.exe"

if (-not (Test-Path $python)) {
    throw "Python interpreter not found: $python"
}

Set-Location $root
& $python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
