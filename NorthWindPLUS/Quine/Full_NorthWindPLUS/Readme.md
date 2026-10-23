This is the full import and extended model of the NorthWindPLUS database implementation into Quine Graph

- The northwind-plus-quine-batch.sh file will import and create the full Graph
- The NorthwindPlus_Stress_Test_Quine.py is the simulation loop:

  Two modes:
    --mode sq      with the standing queries registered (register-standing-queries.sh):
                   only the outside world runs here -- customer-order, order-fulfillment,
                   rfq-submission (suppliers), rfq-fulfillment (goods arrive), and the slow
                   threshold-recalibration job. Reorder, vetting, submission, RFQ vetting and
                   closure happen inside Quine as standing queries.
    --mode loops   the original six loops, no standing queries.
    (default --mode auto: sq if the nw-* standing queries are registered, else loops)

Run every loop of the mode in one process (labelled, combined log; Ctrl+C stops all):
    python3 NorthwindPlus_Stress_Test_Quine.py --check
    python3 NorthwindPlus_Stress_Test_Quine.py --rates customer-order=12,rfq-submission=8 --check

Or one loop on its own, exactly like the original:
    python3 NorthwindPlus_Stress_Test_Quine.py --loop customer-order --rate 6

Options:
    --mode M           sq | loops | auto (see above)
    --loop NAME        run only this loop (default: every loop of the mode)
    --rate N           executions per minute for --loop (default 6)
    --rates a=N,b=N    per-loop rates (defaults below; 0 disables a loop)
    --overprice F      sq mode: share of RFQs quoted above budget (default 0.15)
    --duration S       stop after S seconds
    --check            when the loops stop, run the data-quality invariants
    --check-only       just run the invariants and exit
    --quine URL        Quine base URL (default $QUINE_URL or http://localhost:8080)

The graph must already be loaded with northwind-plus-quine-batch.sh (which
creates the LowStocK Collection).

- The register-standing-queries.sh file will register the Quine standing queries that will automate part of the loop
- The northwind-plus-quine-recommendations.sh is optional if you want to run the recommendation engine. Run it on demand, after northwind-plus-quine-batch.sh

