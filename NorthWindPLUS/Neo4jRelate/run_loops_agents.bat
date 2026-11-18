@echo off
:: AGENTS mode: starts five NorthWind PLUS simulation loops, each in its own window, paused until you press ENTER.
:: PO creation and PO resubmission are done by a Procurement Assistant with the agent (notebook, or
:: agent\agent.py --as-employee 16 --mode agents), so the PO Creation loop isn't started and PO Vetting runs with --no-resubmit.
:: Set SIMULATION_MODE=agents in .env. For the full six-loop simulation, use run_loops_full.bat.
:: Keep this file in the project folder (next to .env and model\).
:: --rate is executions per minute; these rates let vetting and fulfillment keep up with new customer orders.
cd /d "%~dp0"

:: Credentials come from .env (NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD, NEO4J_DATABASE), so this file holds no secrets.
:: Lines starting with # are skipped. Write .env lines as NAME=value, with no spaces around "=" and no quotes.
if not exist ".env" (
    echo .env not found in %CD% - copy .env.example to .env and fill it in.
    pause
    exit /b 1
)
for /f "usebackq eol=# tokens=1,* delims==" %%A in (".env") do set "%%A=%%B"

:: Which Python runs the loops: PYTHON in .env (for example the full path to an Anaconda or venv python.exe), else
:: the first "python" on PATH. It needs the packages in requirements.txt (the loops use the neo4j driver).
if not defined PYTHON set "PYTHON=python"
"%PYTHON%" -c "import neo4j" 2>nul
if errorlevel 1 (
    echo.
    echo The Python used here ^("%PYTHON%"^) can't import the neo4j driver.
    echo Either install the requirements into it:   "%PYTHON%" -m pip install -r requirements.txt
    echo or set PYTHON in .env to a Python that has them, e.g. PYTHON=C:\Users\you\anaconda3\python.exe
    echo or start this file from an Anaconda Prompt with that environment active.
    pause
    exit /b 1
)

start "Customer Order Loop" cmd /k "set /p =Press ENTER to start the Customer Order Loop (Ctrl+C stops it): & "%PYTHON%" model\NorthwindPlus_Stress_Test.py --loop customer-order --rate 6"
start "PO Vetting Loop" cmd /k "set /p =Press ENTER to start the PO Vetting Loop (Ctrl+C stops it): & "%PYTHON%" model\NorthwindPlus_Stress_Test.py --loop po-vetting --rate 12 --no-resubmit"
start "RFQ Creation and Vetting Loop" cmd /k "set /p =Press ENTER to start the RFQ Creation and Vetting Loop (Ctrl+C stops it): & "%PYTHON%" model\NorthwindPlus_Stress_Test.py --loop rfq-vetting --rate 12"
start "Warehouse Restock and Finance Loop" cmd /k "set /p =Press ENTER to start the Warehouse Restock and Finance Loop (Ctrl+C stops it): & "%PYTHON%" model\NorthwindPlus_Stress_Test.py --loop warehouse-finance --rate 12"
start "Customer Order Fulfillment Loop" cmd /k "set /p =Press ENTER to start the Customer Order Fulfillment Loop (Ctrl+C stops it): & "%PYTHON%" model\NorthwindPlus_Stress_Test.py --loop order-fulfillment --rate 12"
