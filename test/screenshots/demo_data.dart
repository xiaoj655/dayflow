import 'package:life_assistant/models/task.dart';

import '../fakes.dart';

/// Screenshot-only examples; never read or write a user's tasks.
FakeRepository screenshotRepository(String date) {
  final repository = ScreenshotRepository();
  repository.days[date] = [
    DailyTask(
      id: 'desk:$date',
      templateId: 'desk',
      date: date,
      title: '整理书桌',
      content: '收好桌面杂物，擦拭桌面，留下今天需要的用品。',
      tutorial: '先把物品分类，再放回固定位置。',
      taskValue: '保持整洁舒适的环境',
      minimumGoal: '整理桌面的一角',
      completionStandard: '桌面整洁，常用物品归位',
      startAction: '先收好桌上的杂物',
      estimatedMinutes: 15,
    ),
    DailyTask(
      id: 'read:$date',
      templateId: 'read',
      date: date,
      title: '阅读',
      content: '阅读一节，写下一条收获。',
      sortOrder: 1,
    ),
    DailyTask(
      id: 'walk:$date',
      templateId: 'walk',
      date: date,
      title: '散步',
      content: '出门走走，活动身体。',
      sortOrder: 2,
      completedAt: '$date 01:00:00',
    ),
    DailyTask(
      id: 'report:$date',
      templateId: 'report',
      date: date,
      title: '整理项目进度',
      content: '整理本周进展和下一步计划。',
      startAction: '打开项目笔记',
      space: 'work',
      sortOrder: 3,
    ),
    DailyTask(
      id: 'feedback:$date',
      templateId: 'feedback',
      date: date,
      title: '确认设计反馈',
      content: '等待同事确认修改意见。',
      space: 'work',
      waiting: true,
      sortOrder: 4,
    ),
    DailyTask(
      id: 'notes:$date',
      templateId: 'notes',
      date: date,
      title: '整理会议纪要',
      content: '记录会议结论与待办。',
      space: 'work',
      completedAt: '$date 01:30:00',
      sortOrder: 5,
    ),
  ];
  for (final entry in [
    ('demo-read', '阅读', 'life', 'focus', '00:00:00', '00:25:00', 1500),
    ('demo-rest', '休息', 'life', 'rest', '00:25:00', '00:30:00', 300),
    ('demo-work', '整理项目进度', 'work', 'focus', '01:00:00', '01:45:00', 2700),
  ]) {
    repository.sessions[entry.$1] = {
      'id': entry.$1,
      'task_id': null,
      'task_title': entry.$2,
      'space': entry.$3,
      'kind': entry.$4,
      'status': 'completed',
      'started_at': '$date ${entry.$5}',
      'ended_at': '$date ${entry.$6}',
      'planned_seconds': entry.$7,
      'actual_seconds': entry.$7,
    };
  }
  return repository;
}

class ScreenshotRepository extends FakeRepository {
  @override
  Future<void> saveSession(Map<String, dynamic> session) async {
    sessions[session['id'] as String] = {
      'id': session['id'],
      'task_title': session['taskTitle'],
      'space': session['space'],
      'kind': session['kind'],
      'status': session['status'],
      'actual_seconds': session['actualSeconds'],
      'planned_seconds': session['plannedSeconds'],
      'started_at': sqlTime(
        DateTime.fromMillisecondsSinceEpoch(session['startedAt'] as int),
      ),
      'ended_at': sqlTime(
        DateTime.fromMillisecondsSinceEpoch(session['endedAt'] as int),
      ),
    };
  }

  @override
  Future<List<DailyTask>> fetchDay(String date) async =>
      List.of(days[date] ?? []);
}
