"""Offline validation for Hermes step plans and per-step mutations."""
import importlib.util
import json
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'skills/dayflow/scripts/tasks.py'
spec = importlib.util.spec_from_file_location('dayflow_step_tasks', path)
tasks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tasks)


class StepCursor:
    def __init__(self, row):
        self.row = row
        self.updates = []
        self.locked = False

    def execute(self, query, args=None):
        if query.startswith('SELECT '):
            self.locked = query.endswith('FOR UPDATE')
        else:
            self.updates.append((query, args))

    def fetchone(self):
        return self.row


class MigrationCursor:
    def __init__(self):
        self.tables = {
            'la_task_templates': {'id', *tasks.DETAIL_FIELDS, 'space'},
            'la_task_days': {'id', *tasks.DETAIL_FIELDS, 'space', 'waiting', 'carried_from_date'},
            'la_focus_sessions': {'id', 'space'},
        }
        self.table = None

    def execute(self, query, args=None):
        if query.startswith('SELECT COLUMN_NAME'):
            self.table = args[0] if args else 'la_task_days'
        else:
            parts = query.split()
            self.tables[parts[2]].add(parts[5])

    def fetchall(self):
        return [{'COLUMN_NAME': column} for column in self.tables[self.table]]


class TaskStepsTest(unittest.TestCase):
    def test_plain_text_plan_reorders_keep_ids_and_new_steps_get_new_ids(self):
        previous = json.dumps([{'id': 'first', 'title': '复现问题'}, {'id': 'second', 'title': '修改代码'}])
        result = tasks.normalize_steps(['修改代码', '复现问题', '验证修复'], previous)
        self.assertEqual([step['id'] for step in result[:2]], ['second', 'first'])
        self.assertNotIn(result[2]['id'], ['first', 'second'])
        self.assertEqual(len(result[2]['id']), 36)

    def test_explicit_id_can_rename_without_losing_identity(self):
        result = tasks.normalize_steps([{'id': 'second', 'title': '修复边界情况', 'completed': True}])
        self.assertEqual(result, [{'id': 'second', 'title': '修复边界情况'}])
        self.assertEqual(tasks.normalize_steps([]), [])

    def test_duplicate_titles_still_get_distinct_stable_ids(self):
        previous = [{'id': 'a', 'title': '检查'}, {'id': 'b', 'title': '检查'}]
        self.assertEqual([step['id'] for step in tasks.normalize_steps(['检查', '检查'], previous)], ['a', 'b'])

    def test_invalid_plans_are_rejected_before_sql(self):
        invalid = [None, '不是列表', [''], [' '], [True], [1], ['x' * 501], ['步骤'] * 21,
                   [{'id': 'duplicate', 'title': '一'}, {'id': 'duplicate', 'title': '二'}],
                   [{'id': 'bad.id', 'title': '一'}], [{'id': '', 'title': '一'}],
                   [{'id': 12, 'title': '一'}], [{'id': 'x' * 65, 'title': '一'}]]
        for plan in invalid:
            with self.subTest(plan=plan), self.assertRaises(ValueError):
                tasks.normalize_steps(plan)

    def test_list_renders_progress_without_inventing_task_completion(self):
        row = {'steps': '[{"id":"a","title":"复现"},{"id":"b","title":"修复"}]',
               'step_progress': '{"a":true,"b":false,"removed":true}', 'completed_at': None}
        result = tasks.task_with_steps(row)
        self.assertEqual([step['completed'] for step in result['steps']], [True, False])
        self.assertIsNone(result['completed_at'])
        self.assertIsInstance(row['steps'], str)
        self.assertEqual(tasks.task_with_steps({'steps': None, 'step_progress': None})['steps'], [])

    def test_step_mutation_locks_and_merges_other_step_progress(self):
        cursor = StepCursor({'steps': '[{"id":"a","title":"复现"},{"id":"b","title":"修复"}]',
                             'step_progress': '{"a":true}'})
        output = tasks.set_step_completed(cursor, 'task:2026-11-15', 'b')
        self.assertTrue(cursor.locked)
        self.assertTrue(output['completed'])
        self.assertEqual(len(cursor.updates), 1)
        query, args = cursor.updates[0]
        self.assertNotIn('completed_at', query)
        self.assertEqual(json.loads(args[0]), {'a': True, 'b': True})
        self.assertEqual(args[1], 'task:2026-11-15')

    def test_undo_preserves_other_steps_and_missing_id_never_updates(self):
        cursor = StepCursor({'steps': '[{"id":"a","title":"复现"},{"id":"b","title":"修复"}]',
                             'step_progress': '{"a":true,"b":true}'})
        tasks.set_step_completed(cursor, 'task', 'a', False)
        self.assertEqual(json.loads(cursor.updates[0][1][0]), {'a': False, 'b': True})
        for row, step_id in [(None, 'a'), (cursor.row, 'removed')]:
            invalid = StepCursor(row)
            with self.assertRaises(ValueError):
                tasks.set_step_completed(invalid, 'task', step_id)
            self.assertEqual(invalid.updates, [])

    def test_migration_only_adds_optional_columns_and_is_idempotent(self):
        cursor = MigrationCursor()
        self.assertEqual(set(tasks.migrate_task_details(cursor)), {
            'la_task_templates.steps', 'la_task_days.steps', 'la_task_days.step_progress'})
        self.assertEqual(tasks.migrate_task_details(cursor), [])


if __name__ == '__main__':
    unittest.main()
