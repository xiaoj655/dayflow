import 'dart:math';

String newId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

DateTime chinaNow([DateTime? now]) =>
    (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
String dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String sqlTime(DateTime date) =>
    date.toUtc().toIso8601String().replaceFirst('T', ' ').replaceFirst('Z', '');

class DailyTask {
  const DailyTask({
    required this.id,
    required this.templateId,
    required this.date,
    required this.title,
    required this.content,
    this.tutorial,
    this.taskValue,
    this.minimumGoal,
    this.completionStandard,
    this.startAction,
    this.estimatedMinutes,
    this.completedAt,
    this.carriedFromDate,
    this.sortOrder = 0,
    this.recurrence = 'once',
    this.weekdays = const [],
    this.scheduleDate,
  });
  final String id, templateId, date, title, content, recurrence;
  final String? tutorial, completedAt, scheduleDate, carriedFromDate;
  final String? taskValue, minimumGoal, completionStandard, startAction;
  final int? estimatedMinutes;
  final List<int> weekdays;
  final int sortOrder;
  bool get completed => completedAt != null;
  DailyTask withCompletion(String? value) => DailyTask(
    id: id,
    templateId: templateId,
    date: date,
    title: title,
    content: content,
    tutorial: tutorial,
    taskValue: taskValue,
    minimumGoal: minimumGoal,
    completionStandard: completionStandard,
    startAction: startAction,
    estimatedMinutes: estimatedMinutes,
    completedAt: value,
    carriedFromDate: carriedFromDate,
    sortOrder: sortOrder,
    recurrence: recurrence,
    weekdays: weekdays,
    scheduleDate: scheduleDate,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'template_id': templateId,
    'task_date': date,
    'title': title,
    'content': content,
    'tutorial': tutorial,
    'task_value': taskValue,
    'minimum_goal': minimumGoal,
    'completion_standard': completionStandard,
    'start_action': startAction,
    'estimated_minutes': estimatedMinutes,
    'completed_at': completedAt,
    'carried_from_date': carriedFromDate,
    'sort_order': sortOrder,
    'recurrence': recurrence,
    'weekdays': weekdays.join(','),
    'schedule_start_date': scheduleDate,
  };
  factory DailyTask.fromJson(Map<String, dynamic> data) => DailyTask(
    id: data['id'] as String,
    templateId: data['template_id'] as String,
    date: data['task_date'].toString().substring(0, 10),
    title: data['title'] as String,
    content: data['content'] as String,
    tutorial: data['tutorial'] as String?,
    taskValue: data['task_value'] as String?,
    minimumGoal: data['minimum_goal'] as String?,
    completionStandard: data['completion_standard'] as String?,
    startAction: data['start_action'] as String?,
    estimatedMinutes: int.tryParse('${data['estimated_minutes'] ?? ''}'),
    completedAt: data['completed_at'] as String?,
    carriedFromDate: data['carried_from_date']?.toString().substring(0, 10),
    sortOrder: int.parse('${data['sort_order'] ?? 0}'),
    recurrence: data['recurrence'] as String? ?? 'once',
    weekdays: (data['weekdays']?.toString() ?? '')
        .split(',')
        .where((day) => day.isNotEmpty)
        .map(int.parse)
        .toList(),
    scheduleDate: data['schedule_start_date']?.toString().substring(0, 10),
  );
}

class TaskDraft {
  const TaskDraft({
    this.id,
    required this.title,
    required this.content,
    required this.date,
    this.tutorial,
    this.taskValue,
    this.minimumGoal,
    this.completionStandard,
    this.startAction,
    this.estimatedMinutes,
    this.recurrence = 'once',
    this.weekdays = const [],
    this.sortOrder = 0,
  });
  final String title, content, date, recurrence;
  final String? id;
  final String? tutorial;
  final String? taskValue, minimumGoal, completionStandard, startAction;
  final int? estimatedMinutes;
  final List<int> weekdays;
  final int sortOrder;
  void validate() {
    if (estimatedMinutes != null &&
        (estimatedMinutes! < 1 || estimatedMinutes! > 1440)) {
      throw const FormatException('预估时长须为 1–1440 分钟');
    }
    if (DateTime.tryParse(date) == null) throw const FormatException('日期无效');
    if (title.trim().isEmpty ||
        title.trim().length > 200 ||
        content.trim().isEmpty) {
      throw const FormatException('请填写标题和任务内容');
    }
    if (!['once', 'daily', 'weekly'].contains(recurrence) ||
        (recurrence == 'weekly' && weekdays.isEmpty) ||
        weekdays.any((day) => day < 1 || day > 7)) {
      throw const FormatException('请选择重复日期');
    }
  }
}
