-- CodeJudge Part 4 — Safe DELETE Operations
-- DBMS: SQLite-compatible SQL
-- Safety rule: Deletes are performed only on staging copies.
-- Bad rows are copied into rejected/audit tables before deletion.

PRAGMA foreign_keys = OFF;

DROP TABLE IF EXISTS submissions_delete_stage;
DROP TABLE IF EXISTS enrollments_delete_stage;
DROP TABLE IF EXISTS rejected_submissions_stage;
DROP TABLE IF EXISTS rejected_enrollments_stage;

CREATE TABLE submissions_delete_stage AS SELECT * FROM submissions;
CREATE TABLE enrollments_delete_stage AS SELECT * FROM enrollments;

CREATE TABLE rejected_submissions_stage AS
SELECT *, '' AS issue_reason
FROM submissions
WHERE 1 = 0;

CREATE TABLE rejected_enrollments_stage AS
SELECT *, '' AS issue_reason
FROM enrollments
WHERE 1 = 0;

-- ============================================================
-- DELETE 1: Remove unsupported programming-language submission from staging
-- Actual issue: SUB000140 uses language = 'PseudoCode'.
-- Decision: Preserve it in rejected_submissions_stage, then delete it from
-- submissions_delete_stage because the judge cannot execute PseudoCode.
-- Safety explanation:
-- The DELETE uses a specific submission_id and checks the exact invalid language.
-- It cannot delete other submissions.
-- ============================================================

SELECT 'BEFORE DELETE 1 - ROW TO REVIEW' AS step,
       submission_id,
       student_id,
       problem_id,
       language,
       status,
       score
FROM submissions_delete_stage
WHERE submission_id = 'SUB000140'
  AND language = 'PseudoCode';

INSERT INTO rejected_submissions_stage
SELECT *, 'Unsupported programming language: PseudoCode' AS issue_reason
FROM submissions_delete_stage
WHERE submission_id = 'SUB000140'
  AND language = 'PseudoCode';

DELETE FROM submissions_delete_stage
WHERE submission_id = 'SUB000140'
  AND language = 'PseudoCode';

SELECT 'AFTER DELETE 1 - SHOULD BE ZERO' AS step,
       COUNT(*) AS remaining_rows
FROM submissions_delete_stage
WHERE submission_id = 'SUB000140';

SELECT 'AFTER DELETE 1 - PRESERVED REJECTED ROW' AS step,
       submission_id,
       student_id,
       problem_id,
       language,
       issue_reason
FROM rejected_submissions_stage
WHERE submission_id = 'SUB000140';

-- ============================================================
-- DELETE 2: Remove orphan enrollment records from staging
-- Actual issues:
-- E00718 references missing student S9999.
-- E00719 references missing course C999.
-- Decision: Preserve these rows in rejected_enrollments_stage, then delete them
-- from enrollments_delete_stage because they cannot satisfy foreign-key rules.
-- Safety explanation:
-- The DELETE uses known enrollment IDs and also checks that the parent student
-- or parent course is missing. This prevents deleting valid enrollments.
-- ============================================================

SELECT 'BEFORE DELETE 2 - ORPHAN ENROLLMENTS' AS step,
       e.enrollment_id,
       e.student_id,
       e.course_id,
       e.enrollment_status,
       CASE WHEN s.student_id IS NULL THEN 'missing student' ELSE 'student exists' END AS student_check,
       CASE WHEN c.course_id IS NULL THEN 'missing course' ELSE 'course exists' END AS course_check
FROM enrollments_delete_stage e
LEFT JOIN students s ON s.student_id = e.student_id
LEFT JOIN courses c ON c.course_id = e.course_id
WHERE e.enrollment_id IN ('E00718', 'E00719');

INSERT INTO rejected_enrollments_stage
SELECT e.*,
       CASE
           WHEN s.student_id IS NULL AND c.course_id IS NULL THEN 'Missing student and course parent'
           WHEN s.student_id IS NULL THEN 'Missing student parent'
           WHEN c.course_id IS NULL THEN 'Missing course parent'
           ELSE 'No issue found'
       END AS issue_reason
FROM enrollments_delete_stage e
LEFT JOIN students s ON s.student_id = e.student_id
LEFT JOIN courses c ON c.course_id = e.course_id
WHERE e.enrollment_id IN ('E00718', 'E00719')
  AND (s.student_id IS NULL OR c.course_id IS NULL);

DELETE FROM enrollments_delete_stage
WHERE enrollment_id IN ('E00718', 'E00719')
  AND (
      student_id NOT IN (SELECT student_id FROM students)
      OR course_id NOT IN (SELECT course_id FROM courses)
  );

SELECT 'AFTER DELETE 2 - SHOULD BE ZERO' AS step,
       COUNT(*) AS remaining_orphan_rows
FROM enrollments_delete_stage
WHERE enrollment_id IN ('E00718', 'E00719');

SELECT 'AFTER DELETE 2 - PRESERVED REJECTED ROWS' AS step,
       enrollment_id,
       student_id,
       course_id,
       issue_reason
FROM rejected_enrollments_stage
WHERE enrollment_id IN ('E00718', 'E00719');

-- ============================================================
-- Note on duplicate submission SUB000701:
-- This row is intentionally NOT deleted here. The duplicate submission_id belongs
-- to different students, so deleting one row could remove real activity. The safer
-- repair is to assign a staging-only replacement ID after manual verification.
-- ============================================================

SELECT 'NOT DELETED - DUPLICATE NEEDS MANUAL/STAGING ID REPAIR' AS step,
       submission_id,
       student_id,
       problem_id,
       status,
       score
FROM submissions
WHERE submission_id = 'SUB000701';
