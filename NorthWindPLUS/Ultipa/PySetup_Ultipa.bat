@echo off
:: ============================================================================
::  NorthWind PLUS - Ultipa GQLDB stress test launcher
::  Opens 8 windows, each paused until you press ENTER, then runs one loop of
::  NorthwindPlus_Stress_Test_Ultipa.py. Press Ctrl+C in a window to stop its
::  loop; it prints a summary (executions, retries, errors, no_op, rate).
::
::  Run this from the folder that holds NorthwindPlus_Stress_Test_Ultipa.py.
::  The windows opened by "start" inherit the variables set below.
:: ============================================================================

:: ---- Connection settings (fill these in) -----------------------------------
:: The SET "NAME=value" form keeps trailing spaces out of the values.
:: Note: the password is stored here in plain text -- don't share or commit this file with it filled in.
SET "ULTIPA_HOSTS=your-host:443"
SET "ULTIPA_USER="
SET "ULTIPA_PASSWORD="

:: Graph the loops work on. Must be the graph run_gql_script.py loaded
:: (and the one selected in the Ultipa console when you check results).
SET "ULTIPA_GRAPH=NorthWindPLUS"

:: Per-query deadline in seconds (the driver's own default is 30).
:: Your trial instance's gateway also cuts any request off at about 60 seconds (HTTP 504),
:: so values above 60 only help on an instance without that limit.
SET "ULTIPA_TIMEOUT=60"

:: TLS: 0 = plain connection (what your port 443 instance needs), 1 = encrypted.
SET "ULTIPA_TLS=0"

:: ---- Quick pre-flight check --------------------------------------------------
:: Fails early if Python can't find the Ultipa driver (pip install ultipa, 6.x).
python -c "import gqldb, importlib.metadata as m; print('Ultipa driver', m.version('ultipa'), '- graph', '%ULTIPA_GRAPH%', 'on', '%ULTIPA_HOSTS%')"
IF ERRORLEVEL 1 (
    echo.
    echo The Ultipa Python driver is not installed for this Python. Run:
    echo     python -m pip install --upgrade ultipa
    pause
    exit /b 1
)

:: ---- Open the 8 loop windows ---------------------------------------------------
:: --rate is executions per minute (same rates as the Neo4j PySetup.bat).
:: Two windows each for PO Vetting and Order Fulfillment run the same loop concurrently --
:: that's the concurrency test: watch the "retries" count rise (conflicts caught and retried),
:: and run the data-quality queries at the end of the GQL script to confirm nothing slipped through.
start "Customer Order Loop" cmd /k "set /p =Press ENTER to start the Customer Order Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test_Ultipa.py --loop customer-order --rate 60"
start "PO Creation Loop" cmd /k "set /p =Press ENTER to start the PO Creation Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test_Ultipa.py --loop po-creation --rate 1"
start "PO Vetting Loop #1" cmd /k "set /p =Press ENTER to start the PO Vetting Loop #1 (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test_Ultipa.py --loop po-vetting --rate 30"
start "PO Vetting Loop #2" cmd /k "set /p =Press ENTER to start the PO Vetting Loop #2 (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test_Ultipa.py --loop po-vetting --rate 30"
start "RFQ Creation and Vetting Loop" cmd /k "set /p =Press ENTER to start the RFQ Creation and Vetting Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test_Ultipa.py --loop rfq-vetting --rate 30"
start "Warehouse restock and Finance Loop" cmd /k "set /p =Press ENTER to start the Warehouse restock and Finance Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test_Ultipa.py --loop warehouse-finance --rate 20"
start "Customer Order fulfillment Loop #1" cmd /k "set /p =Press ENTER to start the Customer Order fulfillment Loop #1 (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test_Ultipa.py --loop order-fulfillment --rate 40"
start "Customer Order fulfillment Loop #2" cmd /k "set /p =Press ENTER to start the Customer Order fulfillment Loop #2 (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test_Ultipa.py --loop order-fulfillment --rate 40"

:: ---- Tips ----------------------------------------------------------------------------
:: * Debug one loop's exact GQL without connecting:
::       python NorthwindPlus_Stress_Test_Ultipa.py --loop po-vetting --print-queries
:: * Run for a fixed time instead of until Ctrl+C: add  --duration 600  (seconds) to a loop.
:: * OCC_TOUCH (top of NorthwindPlus_Stress_Test_Ultipa.py): True writes an OCCVersion counter on the node
::   each guarded action used to lock in the Neo4j version (the stand-in for apoc.lock.nodes).