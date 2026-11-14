@echo off
:: Starts the six NorthWind PLUS simulation loops, each in its own window, paused until you press ENTER.
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

start "Customer Order Loop" cmd /k "set /p =Press ENTER to start the Customer Order Loop (Ctrl+C stops it): & python model\NorthwindPlus_Stress_Test.py --loop customer-order --rate 6"
start "PO Creation Loop" cmd /k "set /p =Press ENTER to start the PO Creation Loop (Ctrl+C stops it): & python model\NorthwindPlus_Stress_Test.py --loop po-creation --rate 1"
start "PO Vetting Loop" cmd /k "set /p =Press ENTER to start the PO Vetting Loop (Ctrl+C stops it): & python model\NorthwindPlus_Stress_Test.py --loop po-vetting --rate 12"
start "RFQ Creation and Vetting Loop" cmd /k "set /p =Press ENTER to start the RFQ Creation and Vetting Loop (Ctrl+C stops it): & python model\NorthwindPlus_Stress_Test.py --loop rfq-vetting --rate 12"
start "Warehouse Restock and Finance Loop" cmd /k "set /p =Press ENTER to start the Warehouse Restock and Finance Loop (Ctrl+C stops it): & python model\NorthwindPlus_Stress_Test.py --loop warehouse-finance --rate 12"
start "Customer Order Fulfillment Loop" cmd /k "set /p =Press ENTER to start the Customer Order Fulfillment Loop (Ctrl+C stops it): & python model\NorthwindPlus_Stress_Test.py --loop order-fulfillment --rate 12"
