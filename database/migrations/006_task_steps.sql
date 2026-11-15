-- Step definitions are optional and independent of daily completion progress.
-- New occurrences copy only definitions; existing history remains unchanged.
ALTER TABLE la_task_templates ADD COLUMN steps LONGTEXT NULL;
ALTER TABLE la_task_days ADD COLUMN steps LONGTEXT NULL;
ALTER TABLE la_task_days ADD COLUMN step_progress LONGTEXT NULL;
