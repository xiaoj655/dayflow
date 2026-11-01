#!/usr/bin/env python3
"""Dayflow task operations shared by Hermes and the companion app."""
import argparse
from datetime import date, datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import ssl
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
CHINA = timezone(timedelta(hours=8))
DETAIL_FIELDS = ('task_value', 'minimum_goal', 'completion_standard', 'start_action', 'estimated_minutes')


def migrate_task_details(cursor):
    """Only add missing v2/v3 columns; never rewrite existing rows or snapshots."""
    added = []
    for table in ('la_task_templates', 'la_task_days'):
        cursor.execute('SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=%s', (table,))
        existing = {row['COLUMN_NAME'] for row in cursor.fetchall()}
        if not existing:
            raise ValueError(f'Missing table {table}; initialize the schema first')
        for field in DETAIL_FIELDS:
            if field not in existing:
                definition = 'SMALLINT UNSIGNED NULL' if field == 'estimated_minutes' else 'TEXT NULL'
                cursor.execute(f'ALTER TABLE {table} ADD COLUMN {field} {definition}')
                added.append(f'{table}.{field}')
    if 'carried_from_date' not in existing:
        cursor.execute('ALTER TABLE la_task_days ADD COLUMN carried_from_date DATE NULL')
        added.append('la_task_days.carried_from_date')
    return added


def today():
    return datetime.now(CHINA).date().isoformat()


def connect():
    import pymysql
    config = json.loads((ROOT / 'connection.json').read_text())
    context = ssl.create_default_context(cafile=str(ROOT / 'mysql-server.pem'))
    context.check_hostname = False  # Identity is the pinned leaf certificate below.
    # MySQL auto-generated certificates may omit AKI; keep chain/date checking
    # and the exact leaf pin while using OpenSSL's compatibility verifier.
    context.verify_flags &= ~ssl.VERIFY_X509_STRICT
    context.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN
    connection = pymysql.connect(host=config['host'], port=config['port'], user=config['user'],
        password=config['password'], database=config['database'], charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor, ssl=context, connect_timeout=8,
        read_timeout=8, write_timeout=8, autocommit=False)
    if hashlib.sha256(connection._sock.getpeercert(binary_form=True)).hexdigest() != config['certificateSha256']:
        connection.close()
        raise RuntimeError('Database certificate does not match the configured pin')
    with connection.cursor() as cursor:
        cursor.execute("SET time_zone = '+00:00'")
    return connection


def materialize(cursor, day):
    weekday = date.fromisoformat(day).isoweekday()
    cursor.execute('''INSERT IGNORE INTO la_task_days
        (id, template_id, task_date, title, content, tutorial,
         task_value, minimum_goal, completion_standard, start_action, estimated_minutes, sort_order)
        SELECT CONCAT(id, ':', %s), id, %s, title, content, tutorial,
        task_value, minimum_goal, completion_standard, start_action, estimated_minutes, sort_order
        FROM la_task_templates WHERE active = TRUE AND start_date <= %s
        AND ((recurrence = 'once' AND start_date = %s) OR recurrence = 'daily'
          OR (recurrence = 'weekly' AND FIND_IN_SET(%s, weekdays) > 0))''',
        (day, day, day, day, weekday))


def list_tasks(cursor, day):
    materialize(cursor, day)
    cursor.execute('''SELECT d.*, t.recurrence, t.weekdays FROM la_task_days d
        JOIN la_task_templates t ON d.template_id = t.id WHERE d.task_date = %s
        AND (%s < %s OR d.completed_at IS NOT NULL OR d.carried_from_date IS NOT NULL OR (t.active = TRUE AND t.start_date <= %s
          AND ((t.recurrence = 'once' AND t.start_date = %s) OR t.recurrence = 'daily'
            OR (t.recurrence = 'weekly' AND FIND_IN_SET(%s, t.weekdays) > 0))))
        ORDER BY d.completed_at IS NOT NULL, d.sort_order, d.id''',
        (day, day, today(), day, day, date.fromisoformat(day).isoweekday()))
    return cursor.fetchall()


def put_task(cursor, payload, task_id=None):
    if task_id:
        cursor.execute('SELECT * FROM la_task_templates WHERE id = %s', (task_id,))
        existing = cursor.fetchone()
        if not existing:
            raise ValueError('No template with this ID')
        base = dict(existing)
        base['date'] = str(base['start_date'])
        base['weekdays'] = [int(x) for x in base['weekdays'].split(',') if x]
        base.update(payload)
        payload = base
    title = payload.get('title', '').strip()
    content = payload.get('content', '').strip()
    if not title or len(title) > 200 or not content:
        raise ValueError('A title (1–200 characters) and task content are required')
    day = payload.get('date', today())
    date.fromisoformat(day)
    repeat = payload.get('recurrence', 'once')
    weekdays = sorted(set(payload.get('weekdays', [])))
    if repeat not in ('once', 'daily', 'weekly') or any(type(x) is not int or x not in range(1, 8) for x in weekdays):
        raise ValueError('Invalid recurrence or weekdays')
    if repeat == 'weekly' and not weekdays:
        raise ValueError('Weekly tasks need weekdays (Monday=1 ... Sunday=7)')
    tutorial = (payload.get('tutorial') or '').strip() or None
    details = [(payload.get(field) or '').strip() or None for field in DETAIL_FIELDS[:-1]]
    estimate = payload.get('estimated_minutes')
    if estimate is not None and (type(estimate) is not int or not 1 <= estimate <= 1440):
        raise ValueError('estimated_minutes must be an integer between 1 and 1440, or null')
    details.append(estimate)
    task_id = task_id or str(uuid.uuid4())
    order = int(payload.get('sort_order', 0))
    cursor.execute('''INSERT INTO la_task_templates
        (id, title, content, tutorial, task_value, minimum_goal, completion_standard,
         start_action, estimated_minutes, recurrence, start_date, weekdays, sort_order)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON DUPLICATE KEY UPDATE
        title=VALUES(title), content=VALUES(content), tutorial=VALUES(tutorial),
        task_value=VALUES(task_value), minimum_goal=VALUES(minimum_goal),
        completion_standard=VALUES(completion_standard), start_action=VALUES(start_action),
        estimated_minutes=VALUES(estimated_minutes), recurrence=VALUES(recurrence),
        start_date=VALUES(start_date), weekdays=VALUES(weekdays),
        sort_order=VALUES(sort_order)''',
        (task_id, title, content, tutorial, *details, repeat, day, ','.join(map(str, weekdays)), order))
    cursor.execute('''UPDATE la_task_days SET title=%s, content=%s, tutorial=%s, sort_order=%s,
        task_value=%s, minimum_goal=%s, completion_standard=%s, start_action=%s, estimated_minutes=%s
        WHERE template_id=%s AND task_date >= %s AND completed_at IS NULL''',
        (title, content, tutorial, order, *details, task_id, today()))
    return {'template_id': task_id, 'title': title, 'date': day, 'recurrence': repeat}


def carry_to_today(cursor, task_id):
    day = today()
    cursor.execute('SELECT * FROM la_task_days WHERE id=%s FOR UPDATE', (task_id,))
    source = cursor.fetchone()
    if not source or source['completed_at'] is not None or str(source['task_date']) == day:
        raise ValueError('Only unfinished tasks from another date can be added to today')
    cursor.execute('''INSERT INTO la_task_days
        (id, template_id, task_date, carried_from_date, title, content, tutorial,
         task_value, minimum_goal, completion_standard, start_action, estimated_minutes, sort_order)
        SELECT CONCAT(template_id, ':', %s), template_id, %s, task_date,
          title, content, tutorial, task_value, minimum_goal, completion_standard,
          start_action, estimated_minutes, sort_order
        FROM la_task_days AS source_task WHERE id=%s
        ON DUPLICATE KEY UPDATE carried_from_date=IF(la_task_days.completed_at IS NULL,
          COALESCE(la_task_days.carried_from_date, VALUES(carried_from_date)), la_task_days.carried_from_date)''', (day, day, task_id))
    return {'id': f"{source['template_id']}:{day}", 'date': day, 'carried_from_date': str(source['task_date'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('init')
    listing = commands.add_parser('list'); listing.add_argument('--date', default=today())
    put = commands.add_parser('put'); put.add_argument('--input', type=Path, required=True); put.add_argument('--id')
    complete = commands.add_parser('complete'); complete.add_argument('--id', required=True); complete.add_argument('--undo', action='store_true')
    carry = commands.add_parser('carry'); carry.add_argument('--id', required=True)
    archive = commands.add_parser('archive'); archive.add_argument('--id', required=True)
    history = commands.add_parser('history'); history.add_argument('--limit', type=int, default=30)
    args = parser.parse_args()
    connection = connect()
    try:
        with connection.cursor() as cursor:
            if args.command == 'init':
                schema = '\n'.join(line for line in (ROOT / 'references/schema.sql').read_text().splitlines() if not line.lstrip().startswith('--'))
                for statement in schema.split(';'):
                    if statement.strip(): cursor.execute(statement)
                added = migrate_task_details(cursor)
                output = {'schema': 'ready', 'added_columns': added}
            elif args.command == 'list': output = list_tasks(cursor, args.date)
            elif args.command == 'put': output = put_task(cursor, json.loads(args.input.read_text()), args.id)
            elif args.command == 'carry': output = carry_to_today(cursor, args.id)
            elif args.command == 'complete':
                cursor.execute('UPDATE la_task_days SET completed_at=%s WHERE id=%s',
                    (None if args.undo else datetime.now(timezone.utc).replace(tzinfo=None), args.id))
                if not cursor.rowcount:
                    cursor.execute('SELECT id FROM la_task_days WHERE id=%s', (args.id,))
                    if not cursor.fetchone(): raise ValueError('No daily task with this ID; list its date first')
                output = {'id': args.id, 'completed': not args.undo}
            elif args.command == 'archive':
                cursor.execute('UPDATE la_task_templates SET active=FALSE WHERE id=%s', (args.id,))
                if not cursor.rowcount:
                    cursor.execute('SELECT id FROM la_task_templates WHERE id=%s', (args.id,))
                    if not cursor.fetchone(): raise ValueError('No template with this ID')
                output = {'template_id': args.id, 'active': False}
            else:
                cursor.execute('SELECT * FROM la_focus_sessions ORDER BY started_at DESC LIMIT %s',
                    (max(1, min(args.limit, 200)),))
                output = cursor.fetchall()
        connection.commit()
        print(json.dumps(output, ensure_ascii=False, default=str, indent=2))
    except Exception:
        connection.rollback()
        raise
    finally: connection.close()


if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(f'Operation failed: {error}', file=sys.stderr)
        sys.exit(1)
