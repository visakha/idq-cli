@echo off
setlocal enabledelayedexpansion

:: ==========================================
:: CONFIGURATION
:: ==========================================
set "INFA_HOME=C:\Informatica\10.5.0\server\bin"
set "DOMAIN=Domain_Prod"
set "DIS_SERVICE=DIS_DataQuality"
set "USER_NAME=Administrator"
set "PASSWORD=MySecurePassword123"
set "APPLICATION=App_ETL_Master"
set "WORKFLOW=wf_Cleanse_Customer_Data"

:: Navigate to the Informatica installation path containing infacmd.bat
cd /d "%INFA_HOME%"

:: ==========================================
:: 1. KICK OFF THE IDQ WORKFLOW
:: ==========================================
echo [%time%] Starting IDQ Workflow: %WORKFLOW% in Application: %APPLICATION%...

for /f "tokens=*" %%i in ('infacmd.bat wfs startWorkflow -dn %DOMAIN% -sn %DIS_SERVICE% -un %USER_NAME% -pd %PASSWORD% -a %APPLICATION% -wf %WORKFLOW%') do (
    set "START_OUTPUT=%%i"
    echo !START_OUTPUT!
)

:: Extracting Workflow Run ID if needed, or monitor directly by application and workflow name.
:: Note: infacmd wfs getWorkflowStatus tracks execution status.

:: ==========================================
:: 2. MONITORING LOOP (POLL EVERY 15 SECONDS)
:: ==========================================
echo.
echo [%time%] Beginning polling loop...
:POLL_LOOP

:: Fetch current status
set "CURRENT_STATUS=UNKNOWN"
for /f "tokens=*" %%s in ('infacmd.bat wfs getWorkflowStatus -dn %DOMAIN% -sn %DIS_SERVICE% -un %USER_NAME% -pd %PASSWORD% -a %APPLICATION% -wf %WORKFLOW%') do (
    set "CURRENT_STATUS=%%s"
)

echo [%time%] Current Status: %CURRENT_STATUS%

:: Check for terminal execution states
if /i "%CURRENT_STATUS%"=="COMPLETED" (
    echo [SUCCESS] Workflow %WORKFLOW% finished successfully.
    goto :END_SCRIPT
)
if /i "%CURRENT_STATUS%"=="FAILED" (
    echo [ERROR] Workflow %WORKFLOW% failed! Check DIS logs.
    exit /b 1
)
if /i "%CURRENT_STATUS%"=="ABORTED" (
    echo [WARNING] Workflow %WORKFLOW% was aborted manually or timed out.
    exit /b 2
)
if /i "%CURRENT_STATUS%"=="CANCELLED" (
    echo [WARNING] Workflow %WORKFLOW% was cancelled.
    exit /b 3
)

:: Wait 15 seconds before checking again
timeout /t 15 /nobreak >nul
goto :POLL_LOOP

:END_SCRIPT
endlocal
echo [%time%] Process execution complete.
