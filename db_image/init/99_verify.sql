\set ON_ERROR_STOP on

DO $verify$
DECLARE
  expected record;
  actual_rows bigint;
BEGIN
  FOR expected IN
    SELECT *
    FROM (VALUES
      ('public.closest_dealerships', 44533::bigint),
      ('public.countries', 0::bigint),
      ('public.customer_sales', 50000::bigint),
      ('public.customer_survey', 32::bigint),
      ('public.customers', 50000::bigint),
      ('public.dealerships', 20::bigint),
      ('public.emails', 418158::bigint),
      ('public.products', 12::bigint),
      ('public.public_transportation_by_zip', 15412::bigint),
      ('public.sales', 37711::bigint),
      ('public.salespeople', 300::bigint),
      ('public.top_cities_data', 20::bigint),
      ('public.customer_search', 50000::bigint),
      ('public.customer_survey_search', 32::bigint)
    ) AS checks(relation_name, expected_rows)
  LOOP
    IF to_regclass(expected.relation_name) IS NULL THEN
      RAISE EXCEPTION 'Required relation % is missing', expected.relation_name;
    END IF;

    EXECUTE format('SELECT count(*) FROM %s', expected.relation_name)
      INTO actual_rows;

    IF actual_rows <> expected.expected_rows THEN
      RAISE EXCEPTION
        'Relation % has % rows; expected %',
        expected.relation_name,
        actual_rows,
        expected.expected_rows;
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM pg_extension
    WHERE extname IN ('cube', 'earthdistance')
  ) <> 2 THEN
    RAISE EXCEPTION 'Required cube and earthdistance extensions are not installed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'stat315_student'
      AND NOT rolsuper
      AND NOT rolcreatedb
      AND NOT rolcreaterole
  ) THEN
    RAISE EXCEPTION 'stat315_student does not have the expected restricted role';
  END IF;

  IF has_schema_privilege('stat315_student', 'public', 'CREATE') THEN
    RAISE EXCEPTION 'stat315_student must not be able to create in public';
  END IF;

  IF NOT has_schema_privilege('stat315_student', 'student_work', 'CREATE') THEN
    RAISE EXCEPTION 'stat315_student must be able to create in student_work';
  END IF;

  IF pg_get_userbyid((
    SELECT nspowner FROM pg_namespace WHERE nspname = 'student_work'
  )) <> 'stat315_admin' THEN
    RAISE EXCEPTION 'stat315_admin must retain ownership of student_work';
  END IF;

  PERFORM earth_distance(ll_to_earth(30.6187, -96.3365), ll_to_earth(29.7604, -95.3698));
  PERFORM count(*) FROM public.customer_search
    WHERE search_vector @@ plainto_tsquery('english', 'customer');

  RAISE NOTICE 'STAT 315 database verification passed';
END
$verify$;

-- The bootstrap password is needed only by initdb. Local maintenance continues
-- to work through the Unix socket; password-based TCP superuser login is then
-- impossible from the notebook or pgAdmin containers.
ALTER ROLE stat315_admin PASSWORD NULL;

-- This marker is deliberately last. The Compose health check cannot report a
-- usable database unless every restore, permission, and integrity check above
-- completed successfully.
INSERT INTO course_meta.environment_release (dataset_version)
VALUES ('2026-fall-pg18-seed1');
