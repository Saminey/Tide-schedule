class TaskModel {
  String id;
  String title;
  String description;
  String startTime;
  String endTime;
  String loopType;
  List<int> loopDays;
  List<DateTime> specificDates;
  bool isCompleted;

  // ⚡ 新增：通知设置
  bool hasReminder;
  int reminderOffset; // 提前提醒的分钟数 (上限 1440)

  TaskModel({
    required this.id,
    required this.title,
    this.description = '',
    required this.startTime,
    required this.endTime,
    required this.loopType,
    this.loopDays = const [],
    this.specificDates = const [],
    this.isCompleted = false,
    this.hasReminder = false,
    this.reminderOffset = 0,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['id'],
      title: json['title'],
      description: json['description'] ?? '',
      startTime: json['startTime'],
      endTime: json['endTime'],
      loopType: json['loopType'],
      loopDays: List<int>.from(json['loopDays'] ?? []),
      specificDates:
          (json['specificDates'] as List<dynamic>?)
              ?.map((e) => DateTime.parse(e))
              .toList() ??
          [],
      isCompleted: json['isCompleted'] ?? false,
      // ⚡ 兼容旧数据：如果 JSON 里没有这两个字段，默认不提醒
      hasReminder: json['hasReminder'] ?? false,
      reminderOffset: json['reminderOffset'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'startTime': startTime,
      'endTime': endTime,
      'loopType': loopType,
      'loopDays': loopDays,
      'specificDates': specificDates.map((e) => e.toIso8601String()).toList(),
      'isCompleted': isCompleted,
      'hasReminder': hasReminder,
      'reminderOffset': reminderOffset,
    };
  }
}
