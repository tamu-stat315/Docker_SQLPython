\set ON_ERROR_STOP on

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;

GRANT CONNECT ON DATABASE sqlda TO stat315_student;
GRANT USAGE ON SCHEMA public TO stat315_student;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO stat315_student;

CREATE SCHEMA student_work AUTHORIZATION stat315_admin;
REVOKE ALL ON SCHEMA student_work FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA student_work TO stat315_student;
ALTER ROLE stat315_student IN DATABASE sqlda
  SET search_path TO public, student_work;

CREATE SCHEMA course_meta AUTHORIZATION stat315_admin;
CREATE TABLE course_meta.environment_release (
  dataset_version text PRIMARY KEY,
  installed_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON SCHEMA course_meta FROM PUBLIC;
GRANT USAGE ON SCHEMA course_meta TO stat315_student;
GRANT SELECT ON course_meta.environment_release TO stat315_student;

ALTER DEFAULT PRIVILEGES FOR ROLE stat315_admin IN SCHEMA public
  GRANT SELECT ON TABLES TO stat315_student;

ANALYZE;
