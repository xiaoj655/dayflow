-- Additive v2 migration; run through scripts/migrate_database.py for idempotence.
ALTER TABLE la_task_templates
  ADD COLUMN task_value TEXT NULL,
  ADD COLUMN minimum_goal TEXT NULL,
  ADD COLUMN completion_standard TEXT NULL,
  ADD COLUMN start_action TEXT NULL,
  ADD COLUMN estimated_minutes SMALLINT UNSIGNED NULL;
ALTER TABLE la_task_days
  ADD COLUMN task_value TEXT NULL,
  ADD COLUMN minimum_goal TEXT NULL,
  ADD COLUMN completion_standard TEXT NULL,
  ADD COLUMN start_action TEXT NULL,
  ADD COLUMN estimated_minutes SMALLINT UNSIGNED NULL;
