@echo off
setlocal
rem The CLI reads mock_infacmd and use_etl_process from the configured properties/environment.
rem ETL choices: PYTHON (default), SP_ORACLE, SP_SNOWFLAKE, IDQ.
rem mock_infacmd selects simulation or live execution.
cd /d "%~dp0.."
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" -m trs_harness.cli %*
) else (
    python -m trs_harness.cli %*
)
exit /b %errorlevel%
