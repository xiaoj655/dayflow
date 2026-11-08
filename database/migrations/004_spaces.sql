-- Existing data remains in life; no historical rows are removed.
ALTER TABLE la_task_templates ADD COLUMN space ENUM('life','work') NOT NULL DEFAULT 'life';
ALTER TABLE la_task_days ADD COLUMN space ENUM('life','work') NOT NULL DEFAULT 'life';
ALTER TABLE la_focus_sessions ADD COLUMN space ENUM('life','work') NOT NULL DEFAULT 'life';
