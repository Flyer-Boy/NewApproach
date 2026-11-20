@echo off
:: The Procurement Assistant web UI: the Python API (api\main.py) serving the built React app at http://localhost:8000.
:: Same governed Cypher as the AI agent and the simulation loops; every PO written here records Source "ui".
:: Needs SIMULATION_MODE=agents in .env and the loops started with run_loops_agents.bat (in full mode the UI explains
:: why it can't write). Keep this file in the project folder (next to .env, api\ and ui\).
cd /d "%~dp0"

if not exist ".env" (
    echo .env not found in %CD% - copy .env.example to .env and fill it in.
    pause
    exit /b 1
)
for /f "usebackq eol=# tokens=1,* delims==" %%A in (".env") do set "%%A=%%B"
if not defined PYTHON set "PYTHON=python"

"%PYTHON%" -c "import neo4j, fastapi, uvicorn" 2>nul
if errorlevel 1 (
    echo.
    echo The Python used here ^("%PYTHON%"^) is missing packages. Install them with:
    echo     "%PYTHON%" -m pip install -r requirements.txt -r requirements-ui.txt
    echo or set PYTHON in .env to a Python that has them.
    pause
    exit /b 1
)
if not exist "ui\dist\index.html" (
    echo.
    echo The UI isn't built yet. Install Node.js 20.19+ or 22.12+, then run once:
    echo     cd ui ^&^& npm install ^&^& npm run build
    pause
    exit /b 1
)

echo Starting the Procurement UI at http://localhost:8000  (SIMULATION_MODE=%SIMULATION_MODE%; Ctrl+C stops it)
start "" "http://localhost:8000"
"%PYTHON%" -m uvicorn api.main:app --host 127.0.0.1 --port 8000
pause
