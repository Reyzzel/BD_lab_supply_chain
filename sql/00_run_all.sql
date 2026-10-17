\set ON_ERROR_STOP on
\encoding UTF8

\echo '== 01 schema'
\ir 01_schema.sql
\echo '== 02 indexes'
\ir 02_indexes.sql
\echo '== 03 functions'
\ir 03_functions.sql
\echo '== 04 triggers'
\ir 04_triggers.sql
\echo '== 05 views'
\ir 05_views.sql
\echo '== 06 procedures'
\ir 06_procedures.sql
\echo '== 07 grants'
\ir 07_grants.sql
\echo '== 08 seed'
\ir 08_seed.sql
\echo '== 09 tests'
\ir 09_tests.sql
