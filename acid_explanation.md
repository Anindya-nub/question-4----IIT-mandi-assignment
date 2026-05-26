# ACID Explanation

This explanation uses **Transaction Scenario 1** from `transactions.sql`, where a new submission `SUB_TXN_0001` and its related test-result rows `R_TXN_0001` and `R_TXN_0002` are inserted.

## Transaction Used

The transaction performs these related changes:

1. Insert one row into `submissions_txn`.
2. Insert related rows into `test_results_txn`.
3. Commit the transaction only after all related rows are inserted.

## Atomicity

Atomicity means the transaction should be treated as one complete unit.

In this scenario, the submission row and test-result rows belong to the same judging event. It would be incorrect to store `SUB_TXN_0001` without its test-case results, because then the system would show a submission without evidence of how it was judged.

Using `BEGIN TRANSACTION` and `COMMIT` ensures that the insert operations are grouped together. In a stricter production design, if one insert failed, the whole transaction should be rolled back so the database does not keep partial judging data.

## Consistency

Consistency means the transaction should move the database from one valid state to another valid state.

Before inserting `SUB_TXN_0001`, the script checks that:

- student `S0001` exists in `students`
- problem `P0001` exists in `problems`
- submission `SUB_TXN_0001` does not already exist in `submissions_txn`

The related test results use real test cases from problem `P0001`. This keeps the relationship between submission, problem, and test cases logically consistent.

## Isolation

Isolation means one transaction should not interfere with another unfinished transaction.

For example, while `SUB_TXN_0001` is being inserted, another process should not see a half-finished state where the submission exists but the test-result rows are not yet inserted. In a full DBMS with proper isolation levels, other users would see either the old state before the transaction or the final committed state after the transaction.

## Durability

Durability means that once a transaction is committed, the changes should remain saved even if the system stops afterward.

After the `COMMIT`, the rows for `SUB_TXN_0001`, `R_TXN_0001`, and `R_TXN_0002` should remain present in the staging transaction tables. In a production CodeJudge system, durability is important because students expect submitted solutions and evaluation results to be permanently stored after successful submission.

## Why ACID Matters Here

A coding judge system must not lose submissions, create incomplete result records, or show inconsistent scores. ACID transactions protect the reliability of important workflows such as submitting code, running test cases, resolving regrade requests, and correcting scores.
