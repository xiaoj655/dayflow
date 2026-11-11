-- Dayflow v5. All DATETIME values are UTC; task_date is Asia/Shanghai.
CREATE TABLE IF NOT EXISTS la_task_templates (
  id CHAR(36) PRIMARY KEY,
  space ENUM('life','work') NOT NULL DEFAULT 'life',
  title VARCHAR(200) NOT NULL,
  content TEXT NOT NULL,
  tutorial LONGTEXT NULL,
  task_value TEXT NULL,
  minimum_goal TEXT NULL,
  completion_standard TEXT NULL,
  start_action TEXT NULL,
  estimated_minutes SMALLINT UNSIGNED NULL,
  recurrence ENUM('once','daily','weekly') NOT NULL DEFAULT 'once',
  start_date DATE NOT NULL,
  weekdays VARCHAR(13) NOT NULL DEFAULT '',
  sort_order INT NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  INDEX task_schedule (active, start_date)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS la_task_days (
  id VARCHAR(47) PRIMARY KEY,
  template_id CHAR(36) NOT NULL,
  task_date DATE NOT NULL,
  carried_from_date DATE NULL,
  space ENUM('life','work') NOT NULL DEFAULT 'life',
  title VARCHAR(200) NOT NULL,
  content TEXT NOT NULL,
  tutorial LONGTEXT NULL,
  task_value TEXT NULL,
  minimum_goal TEXT NULL,
  completion_standard TEXT NULL,
  start_action TEXT NULL,
  estimated_minutes SMALLINT UNSIGNED NULL,
  sort_order INT NOT NULL DEFAULT 0,
  waiting BOOLEAN NOT NULL DEFAULT FALSE,
  completed_at DATETIME(3) NULL,
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  UNIQUE KEY task_occurrence (template_id, task_date),
  INDEX day_order (task_date, sort_order),
  FOREIGN KEY (template_id) REFERENCES la_task_templates(id)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS la_focus_sessions (
  id CHAR(36) PRIMARY KEY,
  task_day_id VARCHAR(47) NULL,
  space ENUM('life','work') NOT NULL DEFAULT 'life',
  task_title VARCHAR(200) NOT NULL,
  kind ENUM('focus','rest') NOT NULL,
  planned_seconds INT UNSIGNED NOT NULL,
  actual_seconds INT UNSIGNED NOT NULL,
  status ENUM('completed','interrupted') NOT NULL,
  started_at DATETIME(3) NOT NULL,
  ended_at DATETIME(3) NOT NULL,
  INDEX focus_history (started_at),
  INDEX task_focus (task_day_id),
  FOREIGN KEY (task_day_id) REFERENCES la_task_days(id)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
