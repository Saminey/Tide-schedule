import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/task_model.dart';

class TaskCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const TaskCard({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  String _getScheduleText() {
    if (task.loopType == 'daily') return "每天";
    if (task.loopType == 'weekly') {
      if (task.loopDays.isEmpty) return "未指定";
      final days = task.loopDays
          .map((d) => ['一', '二', '三', '四', '五', '六', '日'][d - 1])
          .join('、');
      return "周$days";
    }
    if (task.loopType == 'specific') {
      if (task.specificDates.isEmpty) return "未指定日期";
      // 如果日期太多，缩略显示
      if (task.specificDates.length > 2) {
        return "${task.specificDates[0].month}/${task.specificDates[0].day} 等${task.specificDates.length}天";
      }
      final dates = task.specificDates
          .map((d) => "${d.month}/${d.day}")
          .join(', ');
      return dates;
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Material(
            color: Colors.white.withValues(alpha: 0.15),
            child: InkWell(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: onToggle,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Row(
                              children: [
                                Icon(
                                  task.isCompleted
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: task.isCompleted
                                      ? Colors.greenAccent
                                      : Colors.white70,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  task.isCompleted ? "已完成" : "待执行",
                                  style: TextStyle(
                                    color: task.isCompleted
                                        ? Colors.greenAccent
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      task.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "🕒 ${_getScheduleText()} | ${task.startTime} - ${task.endTime}",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    if (task.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        task.description,
                        style: const TextStyle(color: Colors.white60),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
