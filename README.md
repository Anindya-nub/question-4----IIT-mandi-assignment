# question-4----IIT-mandi-assignment
This repository contains the Part 4 solution for the CodeJudge SQL/DBMS assignment.

The main focus of this part is safe database modification. The original imported CSV tables are **not modified directly**. Every data-modification script first creates staging/copy tables and then performs `UPDATE`, `DELETE`, `INSERT`, `COMMIT`, `ROLLBACK`, or `SAVEPOINT` operations on those staging tables only.

## Files

| File | Purpose |
|---|---|
| `safe_updates.sql` | Safe update operations with before/after `SELECT` queries and safe `WHERE` clauses. |
| `safe_deletes.sql` | Safe delete operations performed only on staging copies, with rejected-row preservation. |
| `transactions.sql` | Transaction examples using `BEGIN`, `COMMIT`, `ROLLBACK`, and `SAVEPOINT`. |
| `acid_explanation.md` | Explanation of ACID properties using one transaction from `transactions.sql`. |
| `incident_note.md` | Reliability incident note for a risky update/delete operation. |

## DBMS Assumption

The scripts are written for the raw SQLite-style database created from the provided CSV files. The raw loader imports all CSV columns as text columns. Therefore, numeric comparisons use `CAST(...)` where needed.

## Safety Approach

1. Original raw tables such as `students`, `submissions`, `enrollments`, and `test_results` are treated as read-only.
2. Staging tables such as `students_stage`, `submissions_stage`, and `submissions_txn` are created using `CREATE TABLE ... AS SELECT ...`.
3. Deletes copy affected rows into rejected/audit tables before deletion.
4. Updates use specific IDs and current-value checks in the `WHERE` clause.
5. Transaction scripts show expected final state using validation `SELECT` statements.

## How to Run

Run each file separately on a copy of the imported database:

```bash
sqlite3 codejudge_raw.db < safe_updates.sql
sqlite3 codejudge_raw.db < safe_deletes.sql
sqlite3 codejudge_raw.db < transactions.sql
```

The scripts can also be opened in DB Browser for SQLite and run section by section.
