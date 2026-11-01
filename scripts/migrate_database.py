#!/usr/bin/env python3
"""Apply the additive task-detail migration using the project's pinned TLS config."""
import importlib.util
from pathlib import Path

source = Path(__file__).resolve().parents[1] / 'skills/dayflow/scripts/tasks.py'
spec = importlib.util.spec_from_file_location('life_tasks', source)
skill = importlib.util.module_from_spec(spec)
spec.loader.exec_module(skill)

if __name__ == '__main__':
    connection = skill.connect()
    try:
        with connection.cursor() as cursor:
            added = skill.migrate_task_details(cursor)
        connection.commit()
        print(f'Migration complete: {len(added)} columns added.')
    finally:
        connection.close()
