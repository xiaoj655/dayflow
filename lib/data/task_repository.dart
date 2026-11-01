import '../models/task.dart';

abstract class TaskRepository {
  Future<List<DailyTask>> fetchDay(String date);
  Future<void> addToToday(DailyTask task, String today);
  Future<void> setCompleted(String id, String? completedAt, String changedAt);
  Future<void> saveTask(TaskDraft draft, {DailyTask? existing});
  Future<void> archiveTask(DailyTask task);
  Future<void> saveSession(Map<String, dynamic> session);
  Future<List<Map<String, dynamic>>> history();
}
