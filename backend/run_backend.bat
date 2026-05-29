@echo off
setlocal

set "ROOT=%~dp0"
set "PYTHON=%ROOT%.venv\Scripts\python.exe"

if not exist "%PYTHON%" (
  echo Python interpreter not found: %PYTHON%
  exit /b 1
)

cd /d "%ROOT%"
"%PYTHON%" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
