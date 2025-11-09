@echo off
chcp 65001 >nul 2>&1
REM Get the absolute path of the script directory
set "SCRIPT_DIR=%~dp0"
REM Remove trailing backslash if present
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Add the project local Zig compiler path to the front of PATH
set "ZIG_PATH=%SCRIPT_DIR%\zig-x86_64-windows-0.15.2"
set "PATH=%ZIG_PATH%;%PATH%"

REM Note: This script modifies PATH only in the current command prompt session.
REM To use it in PowerShell, run: cmd /k env.bat
REM Or use env.ps1 instead for PowerShell.

REM Verify Zig version is 0.15.2
set "REQUIRED_VERSION=0.15.2"

REM Check if zig.exe exists
if not exist "%ZIG_PATH%\zig.exe" (
    echo Error: zig.exe not found! >&2
    echo   Please ensure %ZIG_PATH%\zig.exe exists >&2
    exit /b 1
)

REM Get Zig version
for /f "delims=" %%i in ('"%ZIG_PATH%\zig.exe" version 2^>nul') do set "ACTUAL_VERSION=%%i"

if "%ACTUAL_VERSION%"=="" (
    echo Error: Unable to get Zig version! >&2
    echo   Please ensure %ZIG_PATH%\zig.exe is executable >&2
    exit /b 1
)

if "%ACTUAL_VERSION%" NEQ "%REQUIRED_VERSION%" (
    echo Warning: Zig version mismatch! >&2
    echo   Required version: %REQUIRED_VERSION% >&2
    echo   Actual version: %ACTUAL_VERSION% >&2
    echo   Please ensure %ZIG_PATH%\zig.exe has the correct version >&2
    exit /b 1
) else (
    echo [OK] Zig version verified: %ACTUAL_VERSION%
)

