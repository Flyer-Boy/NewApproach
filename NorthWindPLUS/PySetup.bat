@echo off
:: Set your environment variables
SET NEO4J_DATABASE= 
SET NEO4J_PASSWORD= 
SET NEO4J_URI= 
SET NEO4J_USER= 

:: Open 8 windows, each running a paused command prompt session waiting for user to start them
start "Customer Order Loop" cmd /k "set /p =Press ENTER to start the Customer Order Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test.py --loop customer-order --rate 60 & "
start "PO Creation Loop" cmd /k "set /p =Press ENTER to start the PO Createion Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test.py --loop po-creation --rate 0.5 &"
start "PO Vetting Loop #1" cmd /k "set /p =Press ENTER to start the PO Vetting Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test.py --loop po-vetting --rate 30 & "
start "PO Vetting Loop #2" cmd /k "set /p =Press ENTER to start the PO Vetting Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test.py --loop po-vetting --rate 30 & "
start "RFQ Creation and Vetting Loop" cmd /k "set /p =Press ENTER to start the RFQ creation and Vetting Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test.py --loop rfq-vetting --rate 30 &"
start "Warehouse restock and Finance Loop" cmd /k "set /p =Press ENTER to start the Warehouse restock and Finance Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test.py --loop warehouse-finance --rate 20 & "
start "Customer Order fulfillment Loop #1" cmd /k "set /p =Press ENTER to start the Customer Order fulfillment Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test.py --loop order-fulfillment --rate 40 &"
start "Customer Order fulfillment Loop #2" cmd /k "set /p =Press ENTER to start the Customer Order fulfillment Loop (Press Ctrl+C to stop the Loop): & python NorthwindPlus_Stress_Test.py --loop order-fulfillment --rate 40 &"
