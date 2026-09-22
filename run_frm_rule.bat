@echo off
setlocal enabledelayedexpansion

rem ==== EDIT THESE TO MATCH YOUR DB ====
set "PGHOST=localhost"
set "PGPORT=5432"
set "PGUSER=postgres"
set "PGDATABASE=cbs_frm"
rem set "PGPASSWORD=yourpassword"
rem ======================================

set "SQLDIR=%~dp0"

where psql >nul 2>nul
if errorlevel 1 (
    echo psql not found on PATH. Install PostgreSQL client tools or add psql.exe's folder to PATH.
    pause
    exit /b 1
)

:menu
cls
echo ============================================
echo   FRM Test Rule Runner  (DB: %PGDATABASE%)
echo ============================================
echo   0. Foundation setup   (run this first)
echo   1. Significant Movement In Inventory
echo   2. Significant Movement In Receivables
echo   3. Default In SMA1
echo   4. Quick SMA
echo   5. Credit Summation vs Account Limit
echo   6. Run ALL (0 through 5, in order)
echo   Q. Quit
echo ============================================
set "CHOICE="
set /p CHOICE=Select option:

if /i "%CHOICE%"=="Q" goto end
if "%CHOICE%"=="0" (call :run 00_foundation.sql) & goto menu
if "%CHOICE%"=="1" (call :run 01_inventory.sql) & goto menu
if "%CHOICE%"=="2" (call :run 02_receivables.sql) & goto menu
if "%CHOICE%"=="3" (call :run 03_default_sma1.sql) & goto menu
if "%CHOICE%"=="4" (call :run 04_quick_sma.sql) & goto menu
if "%CHOICE%"=="5" (call :run 05_credit_summation.sql) & goto menu
if "%CHOICE%"=="6" (
    call :run 00_foundation.sql
    call :run 01_inventory.sql
    call :run 02_receivables.sql
    call :run 03_default_sma1.sql
    call :run 04_quick_sma.sql
    call :run 05_credit_summation.sql
    goto menu
)

echo Invalid choice.
pause
goto menu

:run
echo.
echo ---- Running %~1 ----
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v ON_ERROR_STOP=1 -f "%SQLDIR%%~1"
if errorlevel 1 (
    echo *** FAILED: %~1 ***
) else (
    echo OK: %~1
)
echo.
pause
exit /b

:end
endlocal
exit /b
