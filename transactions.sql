-- CodeJudge Part 4 — Transaction Scenarios
-- DBMS: SQLite-compatible SQL
-- Safety rule: Transaction examples use *_txn staging tables only.

PRAGMA foreign_keys = OFF;

DROP TABLE IF EXISTS submissions_txn;
DROP TABLE IF EXISTS test_results_txn;
DROP TABLE IF EXISTS enrollments_txn;
DROP TABLE IF EXISTS regrade_requests_txn;

CREATE TABLE submissions_txn AS SELECT * FROM submissions;
CREATE TABLE test_results_txn AS SELECT * FROM test_results;
CREATE TABLE enrollments_txn AS SELECT * FROM enrollments;
CREATE TABLE regrade_requests_txn AS SELECT * FROM regrade_requests;

-- ============================================================
-- TRANSACTION SCENARIO 1: Commit a new submission and its test results
-- Business idea:
-- A student submits a Python solution for problem P0001. The submission row and
-- its test-result rows should be inserted together. If one insert failed in a
-- stricter database, the whole transaction should fail to avoid half-created data.
-- Expected final state after COMMIT:
-- SUB_TXN_0001 exists in submissions_txn and related result rows exist in test_results_txn.
-- ============================================================

BEGIN TRANSACTION;

INSERT INTO submissions_txn (
    submission_id,
    student_id,
    problem_id,
    contest_id,
    language,
    submitted_at,
    status,
    score,
    runtime_ms
)
SELECT
    'SUB_TXN_0001',
    'S0001',
    'P0001',
    '',
    'Python',
    '2026-05-27 10:00:00',
    'Accepted',
    '75',
    '120'
WHERE EXISTS (SELECT 1 FROM students WHERE student_id = 'S0001')
  AND EXISTS (SELECT 1 FROM problems WHERE problem_id = 'P0001')
  AND NOT EXISTS (SELECT 1 FROM submissions_txn WHERE submission_id = 'SUB_TXN_0001');

INSERT INTO test_results_txn (
    result_id,
    submission_id,
    test_case_id,
    result_status,
    runtime_ms,
    memory_kb,
    awarded_points
)
SELECT
    'R_TXN_0001',
    'SUB_TXN_0001',
    test_case_id,
    'Passed',
    '12',
    '1024',
    points
FROM test_cases
WHERE problem_id = 'P0001'
ORDER BY CAST(case_no AS INTEGER)
LIMIT 1;

INSERT INTO test_results_txn (
    result_id,
    submission_id,
    test_case_id,
    result_status,
    runtime_ms,
    memory_kb,
    awarded_points
)
SELECT
    'R_TXN_0002',
    'SUB_TXN_0001',
    test_case_id,
    'Passed',
    '13',
    '1024',
    points
FROM test_cases
WHERE problem_id = 'P0001'
ORDER BY CAST(case_no AS INTEGER)
LIMIT 1 OFFSET 1;

COMMIT;

SELECT 'SCENARIO 1 - COMMITTED SUBMISSION' AS step,
       submission_id,
       student_id,
       problem_id,
       language,
       status,
       score
FROM submissions_txn
WHERE submission_id = 'SUB_TXN_0001';

SELECT 'SCENARIO 1 - COMMITTED TEST RESULTS' AS step,
       result_id,
       submission_id,
       test_case_id,
       result_status,
       awarded_points
FROM test_results_txn
WHERE submission_id = 'SUB_TXN_0001';

-- ============================================================
-- TRANSACTION SCENARIO 2: Roll back invalid enrollment
-- Business idea:
-- An enrollment is attempted for student S0001 into non-existing course C999.
-- The validation query detects that the course parent is missing, so the transaction
-- is rolled back.
-- Expected final state after ROLLBACK:
-- E_TXN_BAD1 does not exist in enrollments_txn.
-- ============================================================

BEGIN TRANSACTION;

INSERT INTO enrollments_txn (
    enrollment_id,
    student_id,
    course_id,
    enrolled_on,
    enrollment_status,
    final_grade
)
VALUES (
    'E_TXN_BAD1',
    'S0001',
    'C999',
    '2026-05-27',
    'active',
    ''
);

SELECT 'SCENARIO 2 - INVALID COURSE DETECTED BEFORE ROLLBACK' AS step,
       e.enrollment_id,
       e.student_id,
       e.course_id,
       CASE WHEN c.course_id IS NULL THEN 'missing course parent' ELSE 'valid course' END AS course_check
FROM enrollments_txn e
LEFT JOIN courses c ON c.course_id = e.course_id
WHERE e.enrollment_id = 'E_TXN_BAD1';

ROLLBACK;

SELECT 'SCENARIO 2 - AFTER ROLLBACK SHOULD BE ZERO' AS step,
       COUNT(*) AS enrollment_count
FROM enrollments_txn
WHERE enrollment_id = 'E_TXN_BAD1';

-- ============================================================
-- TRANSACTION SCENARIO 3: Commit score correction after validation
-- Business idea:
-- SUB000103 has score 999, but its problem P0040 has max_score 75.
-- The correction is committed after validating against the problem table.
-- Expected final state after COMMIT:
-- SUB000103 score becomes 75 in submissions_txn.
-- ============================================================

BEGIN TRANSACTION;

SELECT 'SCENARIO 3 - BEFORE SCORE CORRECTION' AS step,
       s.submission_id,
       s.problem_id,
       s.score,
       p.max_score
FROM submissions_txn s
JOIN problems p ON p.problem_id = s.problem_id
WHERE s.submission_id = 'SUB000103';

UPDATE submissions_txn
SET score = (
    SELECT max_score
    FROM problems
    WHERE problems.problem_id = submissions_txn.problem_id
)
WHERE submission_id = 'SUB000103'
  AND CAST(score AS INTEGER) > (
      SELECT CAST(max_score AS INTEGER)
      FROM problems
      WHERE problems.problem_id = submissions_txn.problem_id
  );

COMMIT;

SELECT 'SCENARIO 3 - AFTER COMMITTED SCORE CORRECTION' AS step,
       s.submission_id,
       s.problem_id,
       s.score,
       p.max_score
FROM submissions_txn s
JOIN problems p ON p.problem_id = s.problem_id
WHERE s.submission_id = 'SUB000103';

-- ============================================================
-- TRANSACTION SCENARIO 4: SAVEPOINT partial rollback during regrade processing
-- Business idea:
-- A regrade request RG0001 is approved and the related submission score is increased.
-- During the same transaction, a risky delete of test-result evidence is attempted.
-- The risky delete is rolled back using SAVEPOINT, while the safe regrade updates remain.
-- Expected final state after COMMIT:
-- RG0001 is approved, SUB001225 score becomes 30, and test_results_txn rows for
-- SUB001225 are still present because the delete was rolled back to the savepoint.
-- ============================================================

BEGIN TRANSACTION;

SELECT 'SCENARIO 4 - BEFORE REGRADE' AS step,
       r.request_id,
       r.submission_id,
       r.request_status,
       r.resolved_at,
       s.score AS submission_score,
       (SELECT COUNT(*) FROM test_results_txn tr WHERE tr.submission_id = r.submission_id) AS test_result_rows
FROM regrade_requests_txn r
JOIN submissions_txn s ON s.submission_id = r.submission_id
WHERE r.request_id = 'RG0001';

UPDATE regrade_requests_txn
SET request_status = 'approved',
    resolved_at = '2026-05-27 12:00:00'
WHERE request_id = 'RG0001'
  AND request_status = 'open';

UPDATE submissions_txn
SET score = '30'
WHERE submission_id = (
    SELECT submission_id
    FROM regrade_requests_txn
    WHERE request_id = 'RG0001'
)
  AND CAST(score AS INTEGER) < 30;

SAVEPOINT before_risky_delete;

DELETE FROM test_results_txn
WHERE submission_id = (
    SELECT submission_id
    FROM regrade_requests_txn
    WHERE request_id = 'RG0001'
);

SELECT 'SCENARIO 4 - AFTER RISKY DELETE BEFORE SAVEPOINT ROLLBACK' AS step,
       COUNT(*) AS test_result_rows
FROM test_results_txn
WHERE submission_id = 'SUB001225';

ROLLBACK TO before_risky_delete;
RELEASE before_risky_delete;

COMMIT;

SELECT 'SCENARIO 4 - AFTER COMMIT WITH DELETE UNDONE' AS step,
       r.request_id,
       r.submission_id,
       r.request_status,
       r.resolved_at,
       s.score AS submission_score,
       (SELECT COUNT(*) FROM test_results_txn tr WHERE tr.submission_id = r.submission_id) AS test_result_rows
FROM regrade_requests_txn r
JOIN submissions_txn s ON s.submission_id = r.submission_id
WHERE r.request_id = 'RG0001';
