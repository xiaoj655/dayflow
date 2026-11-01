"""Run with .venv/bin/python -m unittest discover -s test -p skill_integration_test.py.
All task mutations remain in a transaction rolled back by tearDown.
"""
import importlib.util
import os
from datetime import date, timedelta
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'skills/dayflow/scripts/tasks.py'
spec = importlib.util.spec_from_file_location('life_tasks', path)
skill = importlib.util.module_from_spec(spec)
spec.loader.exec_module(skill)


@unittest.skipUnless(os.environ.get('RUN_DATABASE_TEST') == 'true',
                     'Set RUN_DATABASE_TEST=true and configure a dedicated test database')
class SkillDatabaseTest(unittest.TestCase):
    def setUp(self):
        self.connection = skill.connect()
        self.cursor = self.connection.cursor()
        self.day = skill.today()

    def tearDown(self):
        self.connection.rollback()
        self.connection.close()

    def test_weekly_tasks_unicode_and_independent_daily_status(self):
        day = date.fromisoformat(self.day)
        task = skill.put_task(self.cursor, {'title': "观察 ' 街道", 'content': '第一行\n第二行',
            'tutorial': None, 'date': self.day, 'recurrence': 'weekly', 'weekdays': [day.isoweekday()]})
        template_id = task['template_id']
        row = next(row for row in skill.list_tasks(self.cursor, self.day) if row['template_id'] == template_id)
        self.assertEqual(row['content'], '第一行\n第二行')
        self.assertIsNone(row['tutorial'])
        tomorrow = (day + timedelta(days=1)).isoformat()
        self.assertFalse(any(row['template_id'] == template_id for row in skill.list_tasks(self.cursor, tomorrow)))
        self.cursor.execute('UPDATE la_task_days SET completed_at=UTC_TIMESTAMP(3) WHERE id=%s', (row['id'],))
        next_week = (day + timedelta(days=7)).isoformat()
        future = next(row for row in skill.list_tasks(self.cursor, next_week) if row['template_id'] == template_id)
        self.assertIsNone(future['completed_at'])
        self.assertEqual(len([row for row in skill.list_tasks(self.cursor, next_week) if row['template_id'] == template_id]), 1)

    def test_partial_update_preserves_past_and_completed_snapshots(self):
        yesterday = (date.fromisoformat(self.day) - timedelta(days=1)).isoformat()
        task = skill.put_task(self.cursor, {'title': '原始标题', 'content': '原始内容', 'date': yesterday, 'recurrence': 'daily'})
        template_id = task['template_id']
        old = next(row for row in skill.list_tasks(self.cursor, yesterday) if row['template_id'] == template_id)
        current = next(row for row in skill.list_tasks(self.cursor, self.day) if row['template_id'] == template_id)
        self.cursor.execute('UPDATE la_task_days SET completed_at=UTC_TIMESTAMP(3) WHERE id=%s', (current['id'],))
        skill.put_task(self.cursor, {'tutorial': '新教程'}, template_id)
        self.cursor.execute('SELECT title,content,tutorial FROM la_task_templates WHERE id=%s', (template_id,))
        self.assertEqual(self.cursor.fetchone(), {'title': '原始标题', 'content': '原始内容', 'tutorial': '新教程'})
        for day in [yesterday, self.day]:
            row = next(row for row in skill.list_tasks(self.cursor, day) if row['template_id'] == template_id)
            self.assertIsNone(row['tutorial'])
        self.cursor.execute('UPDATE la_task_templates SET active=FALSE WHERE id=%s', (template_id,))
        self.assertTrue(any(row['id'] == old['id'] for row in skill.list_tasks(self.cursor, yesterday)))


    def test_task_details_partial_update_and_history(self):
        today = date.fromisoformat(self.day)
        yesterday = (today - timedelta(days=1)).isoformat()
        tomorrow = (today + timedelta(days=1)).isoformat()
        task = skill.put_task(self.cursor, {'title': '阅读', 'content': '读书并记录',
            'date': yesterday, 'recurrence': 'daily', 'task_value': '拓宽知识',
            'minimum_goal': '读一节', 'completion_standard': '写一句收获',
            'start_action': '先翻开书', 'estimated_minutes': 17})
        template_id = task['template_id']
        old = next(row for row in skill.list_tasks(self.cursor, yesterday) if row['template_id'] == template_id)
        current = next(row for row in skill.list_tasks(self.cursor, self.day) if row['template_id'] == template_id)
        skill.list_tasks(self.cursor, tomorrow)
        self.cursor.execute('UPDATE la_task_days SET completed_at=UTC_TIMESTAMP(3) WHERE id=%s', (current['id'],))
        skill.put_task(self.cursor, {'start_action': '先读两页', 'minimum_goal': None}, template_id)
        self.cursor.execute('SELECT * FROM la_task_templates WHERE id=%s', (template_id,))
        template = self.cursor.fetchone()
        self.assertEqual(template['task_value'], '拓宽知识')
        self.assertEqual(template['estimated_minutes'], 17)
        self.assertIsNone(template['minimum_goal'])
        for day in [yesterday, self.day]:
            row = next(row for row in skill.list_tasks(self.cursor, day) if row['template_id'] == template_id)
            self.assertEqual(row['start_action'], '先翻开书')
            self.assertEqual(row['minimum_goal'], '读一节')
        future = next(row for row in skill.list_tasks(self.cursor, tomorrow) if row['template_id'] == template_id)
        self.assertEqual(future['start_action'], '先读两页')
        self.assertEqual(future['completion_standard'], '写一句收获')
        self.assertIsNone(future['minimum_goal'])

    def test_invalid_estimates_do_not_create_tasks(self):
        for estimate in [0, -1, 1441, True, '20', 2.5]:
            with self.assertRaises(ValueError):
                skill.put_task(self.cursor, {'title': '无效任务', 'content': '不会写入',
                    'estimated_minutes': estimate})


    def test_carry_single_task_preserves_source_and_completed_destination(self):
        yesterday = (date.fromisoformat(self.day) - timedelta(days=1)).isoformat()
        task = skill.put_task(self.cursor, {'title': '理发', 'content': '修剪头发',
            'date': yesterday, 'task_value': '整洁', 'start_action': '先联系理发店', 'estimated_minutes': 30})
        template_id = task['template_id']
        source = next(row for row in skill.list_tasks(self.cursor, yesterday) if row['template_id'] == template_id)
        skill.carry_to_today(self.cursor, source['id'])
        skill.carry_to_today(self.cursor, source['id'])
        matches = [row for row in skill.list_tasks(self.cursor, self.day) if row['template_id'] == template_id]
        self.assertEqual(len(matches), 1)
        target = matches[0]
        self.assertEqual(str(target['carried_from_date']), yesterday)
        self.assertEqual(target['start_action'], '先联系理发店')
        self.assertEqual(target['estimated_minutes'], 30)
        self.cursor.execute('UPDATE la_task_days SET completed_at=UTC_TIMESTAMP(3) WHERE id=%s', (target['id'],))
        skill.carry_to_today(self.cursor, source['id'])
        target = next(row for row in skill.list_tasks(self.cursor, self.day) if row['template_id'] == template_id)
        self.assertIsNotNone(target['completed_at'])
        original = next(row for row in skill.list_tasks(self.cursor, yesterday) if row['template_id'] == template_id)
        self.assertIsNone(original['completed_at'])
        self.assertIsNone(original['carried_from_date'])
        with self.assertRaises(ValueError):
            skill.carry_to_today(self.cursor, target['id'])
