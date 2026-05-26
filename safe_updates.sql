-- CodeJudge Part 4 — Safe UPDATE Operations
-- DBMS: SQLite-compatible SQL
-- Safety rule: This file does not update original imported tables directly.
-- It creates staging copies and applies updates only on those copies.

PRAGMA foreign_keys = OFF;

DROP TABLE IF EXISTS students_stage;
DROP TABLE IF EXISTS submissions_stage;
DROP TABLE IF EXISTS regrade_requests_stage;
DROP TABLE IF EXISTS operation_requests_stage;

CREATE TABLE students_stage AS SELECT * FROM students;
CREATE TABLE submissions_stage AS SELECT * FROM submissions;
CREATE TABLE regrade_requests_stage AS SELECT * FROM regrade_requests;
CREATE TABLE operation_requests_stage AS SELECT * FROM operation_requests;

-- ============================================================
-- UPDATE 1: Correct typo in student enrollment status
-- Actual issue: S0089 has enrollment_status = 'actve'
-- Safe WHERE explanation:
-- The WHERE clause uses the exact primary identifier student_id = 'S0089'
-- and also checks the old bad value 'actve'. This prevents accidental
-- modification if the row was already corrected.
-- ============================================================

SELECT 'BEFORE UPDATE 1' AS step, student_id, full_name, enrollment_status
FROM students_stage
WHERE student_id = 'S0089';

UPDATE students_stage
SET enrollment_status = 'active'
WHERE student_id = 'S0089'
  AND enrollment_status = 'actve';

SELECT 'AFTER UPDATE 1' AS step, student_id, full_name, enrollment_status
FROM students_stage
WHERE student_id = 'S0089';

-- ============================================================
-- UPDATE 2: Correct negative score to zero
-- Actual issue: SUB000056 has score = -10
-- Safe WHERE explanation:
-- The WHERE clause targets one known submission_id and requires the score
-- to be negative. It will not change any other submission or any already-fixed row.
-- ============================================================

SELECT 'BEFORE UPDATE 2' AS step, submission_id, student_id, problem_id, score
FROM submissions_stage
WHERE submission_id = 'SUB000056';

UPDATE submissions_stage
SET score = '0'
WHERE submission_id = 'SUB000056'
  AND CAST(score AS INTEGER) < 0;

SELECT 'AFTER UPDATE 2' AS step, submission_id, student_id, problem_id, score
FROM submissions_stage
WHERE submission_id = 'SUB000056';

-- ============================================================
-- UPDATE 3: Normalize invalid submission status synonym
-- Actual issue: SUB000208 has status = 'OK'
-- Decision: In judge outputs, OK means successful/accepted.
-- Safe WHERE explanation:
-- The exact submission_id and exact old status are both checked.
-- ============================================================

SELECT 'BEFORE UPDATE 3' AS step, submission_id, language, status, score
FROM submissions_stage
WHERE submission_id = 'SUB000208';

UPDATE submissions_stage
SET status = 'Accepted'
WHERE submission_id = 'SUB000208'
  AND status = 'OK';

SELECT 'AFTER UPDATE 3' AS step, submission_id, language, status, score
FROM submissions_stage
WHERE submission_id = 'SUB000208';

-- ============================================================
-- UPDATE 4: Cap score that is greater than problem maximum
-- Actual issue: SUB000103 has score = 999 for problem P0040, max_score = 75
-- Safe WHERE explanation:
-- The update targets one known submission and only changes it when its score
-- is greater than the matching problem's max_score.
-- ============================================================

SELECT 'BEFORE UPDATE 4' AS step,
       s.submission_id,
       s.problem_id,
       s.score,
       p.max_score
FROM submissions_stage s
JOIN problems p ON p.problem_id = s.problem_id
WHERE s.submission_id = 'SUB000103';

UPDATE submissions_stage
SET score = (
    SELECT max_score
    FROM problems
    WHERE problems.problem_id = submissions_stage.problem_id
)
WHERE submission_id = 'SUB000103'
  AND CAST(score AS INTEGER) > (
      SELECT CAST(max_score AS INTEGER)
      FROM problems
      WHERE problems.problem_id = submissions_stage.problem_id
  );

SELECT 'AFTER UPDATE 4' AS step,
       s.submission_id,
       s.problem_id,
       s.score,
       p.max_score
FROM submissions_stage s
JOIN problems p ON p.problem_id = s.problem_id
WHERE s.submission_id = 'SUB000103';

-- ============================================================
-- UPDATE 5: Reopen impossible regrade resolution timestamp
-- Actual issue: RG0019 has resolved_at before requested_at.
-- Decision: Do not guess the real resolution date. Reopen the request and clear resolved_at.
-- Safe WHERE explanation:
-- The WHERE clause targets request_id = 'RG0019' and confirms that the stored
-- resolved_at value is earlier than requested_at.
-- ============================================================

SELECT 'BEFORE UPDATE 5' AS step,
       request_id,
       submission_id,
       student_id,
       request_status,
       requested_at,
       resolved_at
FROM regrade_requests_stage
WHERE request_id = 'RG0019';

UPDATE regrade_requests_stage
SET request_status = 'open',
    resolved_at = ''
WHERE request_id = 'RG0019'
  AND resolved_at <> ''
  AND resolved_at < requested_at;

SELECT 'AFTER UPDATE 5' AS step,
       request_id,
       submission_id,
       student_id,
       request_status,
       requested_at,
       resolved_at
FROM regrade_requests_stage
WHERE request_id = 'RG0019';

-- ============================================================
-- UPDATE 6: Reject destructive operation request workflow status
-- Actual issue: OP0003 has operation_type = 'DROP' and approval_status = 'approved'.
-- Decision: Mark it rejected in staging because DROP is destructive and should not
-- be approved through the normal operation workflow.
-- Safe WHERE explanation:
-- The update targets one operation_id and checks operation_type = 'DROP'.
-- ============================================================

SELECT 'BEFORE UPDATE 6' AS step,
       operation_id,
       requested_by,
       operation_type,
       target_table,
       target_record_id,
       approval_status,
       executed_at
FROM operation_requests_stage
WHERE operation_id = 'OP0003';

UPDATE operation_requests_stage
SET approval_status = 'rejected',
    executed_at = ''
WHERE operation_id = 'OP0003'
  AND operation_type = 'DROP';

SELECT 'AFTER UPDATE 6' AS step,
       operation_id,
       requested_by,
       operation_type,
       target_table,
       target_record_id,
       approval_status,
       executed_at
FROM operation_requests_stage
WHERE operation_id = 'OP0003';
