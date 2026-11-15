"""Step persistence checks in random isolated tables; never reads or edits user tasks.
Run: skills/dayflow/.venv/bin/python test/task_steps_database_test.py
Requires the configured TLS connection plus CREATE/ALTER/DROP on its database.
"""
import importlib.util
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Barrier
import uuid

spec = importlib.util.spec_from_file_location('dayflow_step_tasks', Path(__file__).resolve().parents[1] / 'skills/dayflow/scripts/tasks.py')
tasks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tasks)


def main():
    connection = tasks.connect()
    suffix = uuid.uuid4().hex
    names = {name: f'test_{suffix}_{name}' for name in ('la_task_templates', 'la_task_days', 'la_focus_sessions')}
    created = []

    class IsolatedCursor:
        def __init__(self, raw):
            self.raw = raw

        def execute(self, query, args=None):
            for source, target in names.items():
                query = query.replace(source, target)
            if args:
                args = tuple(names.get(arg, arg) if isinstance(arg, str) else arg for arg in args)
            return self.raw.execute(query, args)

        def __getattr__(self, name):
            return getattr(self.raw, name)

    def by_template(cursor, day, identity):
        return next(row for row in tasks.list_tasks(cursor, day) if row['template_id'] == identity)

    try:
        with connection.cursor() as raw:
            for source, target in names.items():
                raw.execute(f'CREATE TABLE {target} LIKE {source}')
                created.append(target)
            cursor = IsolatedCursor(raw)
            tasks.migrate_task_details(cursor)
            assert tasks.migrate_task_details(cursor) == []
            day = tasks.date.fromisoformat(tasks.today())
            yesterday = (day - tasks.timedelta(days=1)).isoformat()
            tomorrow = (day + tasks.timedelta(days=1)).isoformat()

            # New daily snapshots start clean, while source history stays intact.
            identity = tasks.put_task(cursor, {'title': 'steps-test', 'content': 'daily', 'date': yesterday,
                'recurrence': 'daily', 'steps': ['复现问题', '修改代码', '验证修复']})['template_id']
            old = by_template(cursor, yesterday, identity)
            old_ids = [step['id'] for step in old['steps']]
            tasks.set_step_completed(cursor, old['id'], old_ids[0])
            current = by_template(cursor, tasks.today(), identity)
            future = by_template(cursor, tomorrow, identity)
            assert not any(step['completed'] for step in current['steps'])
            assert not any(step['completed'] for step in future['steps'])
            tasks.set_step_completed(cursor, current['id'], old_ids[0])
            tasks.set_step_completed(cursor, current['id'], old_ids[1])
            tasks.set_step_completed(cursor, current['id'], old_ids[0], False)
            current = by_template(cursor, tasks.today(), identity)
            assert [step['completed'] for step in current['steps']] == [False, True, False]
            assert current['completed_at'] is None

            # Partial edits keep snapshot plans; reorders reuse IDs and progress.
            tasks.put_task(cursor, {'content': 'edited without changing steps'}, identity)
            assert by_template(cursor, tasks.today(), identity)['steps'] == current['steps']
            tasks.put_task(cursor, {'steps': ['修改代码', '复现问题', '验证修复', '补充说明']}, identity)
            changed = by_template(cursor, tasks.today(), identity)
            assert [step['id'] for step in changed['steps'][:3]] == [old_ids[1], old_ids[0], old_ids[2]]
            assert changed['steps'][0]['completed']
            assert [step['id'] for step in by_template(cursor, yesterday, identity)['steps']] == old_ids
            cursor.execute('UPDATE la_task_days SET completed_at=UTC_TIMESTAMP(3) WHERE id=%s', (changed['id'],))
            tasks.put_task(cursor, {'steps': []}, identity)
            assert by_template(cursor, tasks.today(), identity)['steps'] == changed['steps']
            assert by_template(cursor, tomorrow, identity)['steps'] == []

            # Carry copies progress only for a new destination, never overwrites it.
            carry_id = tasks.put_task(cursor, {'title': 'carry-steps-test', 'content': 'once', 'date': yesterday,
                'steps': [{'id': 'one', 'title': '第一步'}, {'id': 'two', 'title': '第二步'}]})['template_id']
            source = by_template(cursor, yesterday, carry_id)
            tasks.set_step_completed(cursor, source['id'], 'one')
            tasks.carry_to_today(cursor, source['id'])
            target = by_template(cursor, tasks.today(), carry_id)
            assert target['steps'][0]['completed']
            tasks.set_step_completed(cursor, target['id'], 'two')
            tasks.carry_to_today(cursor, source['id'])
            assert all(step['completed'] for step in by_template(cursor, tasks.today(), carry_id)['steps'])
            assert not by_template(cursor, yesterday, carry_id)['steps'][1]['completed']

            # Work progress follows its one persistent record across dates and edits.
            work_id = tasks.put_task(cursor, {'title': 'work-steps-test', 'content': 'persistent', 'space': 'work',
                'date': yesterday, 'steps': [{'id': 'draft', 'title': '草稿'}, {'id': 'review', 'title': '检查'}]})['template_id']
            work = by_template(cursor, yesterday, work_id)
            tasks.set_step_completed(cursor, work['id'], 'draft')
            assert by_template(cursor, tomorrow, work_id)['id'] == work['id']
            tasks.put_task(cursor, {'steps': [{'id': 'draft', 'title': '草稿'}, {'id': 'review', 'title': '完整检查'}]}, work_id)
            work = by_template(cursor, tasks.today(), work_id)
            assert work['steps'][0]['completed']
            assert work['steps'][1]['title'] == '完整检查'
            try:
                tasks.set_step_completed(cursor, work['id'], 'missing')
                raise AssertionError('A missing step was accepted')
            except ValueError:
                pass

            # Different clients update different steps concurrently. Row locks
            # must merge both results rather than uploading whole stale plans.
            tasks.set_step_completed(cursor, work['id'], 'draft', False)
            connection.commit()  # Only random isolated rows become visible.
            ready = Barrier(2)

            def finish_step(step_id):
                peer = tasks.connect()
                try:
                    with peer.cursor() as raw_peer:
                        ready.wait(timeout=10)
                        tasks.set_step_completed(IsolatedCursor(raw_peer), work['id'], step_id)
                    peer.commit()
                finally:
                    peer.close()

            with ThreadPoolExecutor(max_workers=2) as pool:
                list(pool.map(finish_step, ['draft', 'review']))
            concurrent = by_template(cursor, tasks.today(), work_id)
            assert all(step['completed'] for step in concurrent['steps'])
            assert concurrent['completed_at'] is None
            tasks.put_task(cursor, {'steps': [{'id': 'review', 'title': '重排后的检查'},
                                             {'id': 'draft', 'title': '草稿'}]}, work_id)
            revised = by_template(cursor, tasks.today(), work_id)
            assert all(step['completed'] for step in revised['steps'])
            assert revised['steps'][0]['id'] == 'review'
            cursor.execute('SELECT COUNT(*) AS n FROM la_focus_sessions')
            assert cursor.fetchone()['n'] == 0
            print('Task step database checks passed (random isolated tables only).')
    finally:
        connection.rollback()
        with connection.cursor() as cursor:
            for table in reversed(created):
                cursor.execute(f'DROP TABLE {table}')
        connection.close()


if __name__ == '__main__':
    main()
