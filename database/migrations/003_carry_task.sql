-- Applied idempotently by scripts/migrate_database.py.
ALTER TABLE la_task_days ADD COLUMN carried_from_date DATE NULL;
