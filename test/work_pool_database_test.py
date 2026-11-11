"""Integration checks using uniquely named isolated tables, never user rows.
Run with a Python environment containing PyMySQL: python test/work_pool_database_test.py
"""
import importlib.util
from pathlib import Path
import uuid

spec = importlib.util.spec_from_file_location('dayflow_tasks', Path(__file__).resolve().parents[1] / 'skills/dayflow/scripts/tasks.py')
tasks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tasks)


def main():
    connection = tasks.connect()
    suffix = uuid.uuid4().hex
    names = {table: f'test_{suffix}_{table}' for table in ('la_task_templates', 'la_task_days')}
    created = []
    class IsolatedCursor:
        def __init__(self, raw): self.raw = raw
        def execute(self, query, args=None):
            for source, target in names.items(): query = query.replace(source, target)
            return self.raw.execute(query, args)
        def __getattr__(self, name): return getattr(self.raw, name)
    try:
        with connection.cursor() as cursor:
            for source, target in names.items():
                cursor.execute(f'CREATE TABLE {target} LIKE {source}')
                created.append(target)
            cursor = IsolatedCursor(cursor)
            old = (tasks.date.fromisoformat(tasks.today()) - tasks.timedelta(days=20)).isoformat()
            identity = tasks.put_task(cursor, {'title': 'pool-test', 'content': 'original', 'space': 'work', 'date': old})['template_id']
            first = tasks.work_tasks(cursor)
            assert len(first) == 1
            row_id = first[0]['id']
            cursor.execute('UPDATE la_task_days SET waiting=TRUE WHERE id=%s', (row_id,))
            again = tasks.list_tasks(cursor, tasks.today())
            assert len(again) == 1 and again[0]['id'] == row_id and again[0]['waiting']
            tasks.put_task(cursor, {'content': 'edited'}, identity)
            assert tasks.work_tasks(cursor)[0]['content'] == 'edited'
            cursor.execute('UPDATE la_task_days SET completed_at=UTC_TIMESTAMP(3) WHERE id=%s', (row_id,))
            assert len(tasks.work_tasks(cursor)) == 1
            tasks.put_task(cursor, {'content': 'must not replace completed snapshot'}, identity)
            assert tasks.work_tasks(cursor)[0]['content'] == 'edited'
            cursor.execute('UPDATE la_task_days SET completed_at=UTC_TIMESTAMP(3)-INTERVAL 14 DAY WHERE id=%s', (row_id,))
            assert tasks.work_tasks(cursor) == []
            assert tasks.work_tasks(cursor, completed=True)[0]['id'] == row_id
            cursor.execute('UPDATE la_task_days SET completed_at=NULL WHERE id=%s', (row_id,))
            assert tasks.work_tasks(cursor)[0]['waiting']
            cursor.execute('UPDATE la_task_templates SET active=FALSE WHERE id=%s', (identity,))
            assert tasks.work_tasks(cursor) == []
            cursor.execute('SELECT COUNT(*) AS n FROM la_task_days')
            assert cursor.fetchone()['n'] == 1
        print('Work pool database checks passed (isolated random tables only).')
    finally:
        connection.rollback()
        with connection.cursor() as cursor:
            for table in reversed(created): cursor.execute(f'DROP TABLE {table}')
        connection.close()


if __name__ == '__main__':
    main()
