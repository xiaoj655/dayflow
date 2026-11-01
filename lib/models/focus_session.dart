class FocusSession {
  const FocusSession({
    required this.id,
    required this.taskId,
    required this.taskTitle,
    this.startAction,
    required this.kind,
    required this.status,
    required this.plannedSeconds,
    required this.remainingMillis,
    required this.startedAt,
  });
  final String id, taskId, taskTitle, kind, status;
  final String? startAction;
  final int plannedSeconds, remainingMillis, startedAt;
  bool get running => status == 'running';
  bool get paused => status == 'paused';
  bool get finished => status == 'finished';
  bool get active => running || paused;
  int get remainingSeconds => (remainingMillis / 1000).ceil();
  factory FocusSession.fromJson(Map<String, dynamic> json) => FocusSession(
    id: json['id'] as String,
    taskId: json['taskId'] as String,
    taskTitle: json['taskTitle'] as String,
    startAction: json['startAction'] as String?,
    kind: json['kind'] as String,
    status: json['status'] as String,
    plannedSeconds: (json['plannedSeconds'] as num).toInt(),
    remainingMillis: (json['remainingMillis'] as num).toInt(),
    startedAt: (json['startedAt'] as num).toInt(),
  );
}
