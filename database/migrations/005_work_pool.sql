-- Preserve all existing snapshots and session references.
ALTER TABLE la_task_days ADD COLUMN waiting BOOLEAN NOT NULL DEFAULT FALSE;
