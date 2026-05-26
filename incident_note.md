# Reliability Incident Note

## Incident Title

Accidental mass update of submission statuses due to missing `WHERE` clause.

## What Went Wrong

A developer intended to correct one invalid submission status from `OK` to `Accepted` for submission `SUB000208`. The correct safe query should have been:

```sql
UPDATE submissions_stage
SET status = 'Accepted'
WHERE submission_id = 'SUB000208'
  AND status = 'OK';
```

However, the developer accidentally ran a query like this:

```sql
UPDATE submissions
SET status = 'Accepted';
```

This query has no `WHERE` clause, so it would update every row in the original `submissions` table.

## What Data Could Be Affected

The `submissions` table contains judge outcomes for student code submissions. A mass update could incorrectly mark all submissions as `Accepted`, including submissions that were actually:

- `Wrong Answer`
- `Runtime Error`
- `Compilation Error`
- `Time Limit Exceeded`
- invalid raw statuses such as `OK`

This would corrupt grades, leaderboard results, success-rate reports, problem analytics, and regrade decisions.

## How the Issue Could Be Detected

The issue could be detected using audit queries such as:

```sql
SELECT status, COUNT(*) AS submission_count
FROM submissions
GROUP BY status;
```

If every row suddenly has `status = 'Accepted'`, the distribution would look suspicious. Another useful check is to compare the current status distribution with a backup or earlier staging copy.

```sql
SELECT submission_id, status
FROM submissions
WHERE status <> 'Accepted'
LIMIT 20;
```

If this returns zero rows after a mass update, it is a strong warning that the table may have been accidentally overwritten.

## How Rollback, Backups, or Transactions Could Help

If the developer had run the update inside a transaction first, the mistake could be reversed immediately:

```sql
BEGIN TRANSACTION;
UPDATE submissions
SET status = 'Accepted';
-- Validation shows too many rows changed.
ROLLBACK;
```

If the transaction was already committed, recovery would require restoring from a backup or reconstructing the correct statuses from an audit table, staging copy, or raw CSV re-import.

## Preventive Measures

1. Never run `UPDATE` or `DELETE` on original imported tables during testing.
2. First run a `SELECT` with the same `WHERE` clause to verify the affected rows.
3. Use staging tables such as `submissions_stage` before modifying important data.
4. Use transactions and validate row counts before `COMMIT`.
5. Add constraints and controlled values in the clean schema so invalid statuses cannot be inserted later.
6. Keep regular backups before repair scripts are executed.
7. Use code review for all destructive operations, especially updates to `submissions`, `students`, `enrollments`, and `test_results`.

## Specific CodeJudge Impact

In CodeJudge, submission status directly affects student performance records. If all rows in `submissions` were changed to `Accepted`, then queries such as success rate per problem, average score per student, top attempted problems, and regrade decisions would become misleading. This is why every update in `safe_updates.sql` uses a specific ID and the previous invalid value in the `WHERE` clause.
