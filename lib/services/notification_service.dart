import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/task_model.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // ⚡ 支持“瞬间通知”的平台 (包含了 Linux)
  static bool get _isInstantSupported {
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux;
  }

  // ⚡ 支持“底层定时闹钟”的平台 (剔除了 Linux 和 Windows)
  static bool get _isSchedulingSupported {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  static Future<void> init() async {
    // 如果是不支持的平台（如 Windows），直接静默返回，防止机甲崩溃
    if (!_isInstantSupported) {
      print("⚠️ 当前平台暂不支持原生通知。");
      return;
    }
    tz.initializeTimeZones();

    try {
      final dynamic tzResult = await FlutterTimezone.getLocalTimezone();
      String timeZoneName = tzResult is String ? tzResult : tzResult.identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const LinuxInitializationSettings linuxInit = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      linux: linuxInit,
    );

    await _notificationsPlugin.initialize(settings: initSettings);

    if (Platform.isAndroid) {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImplementation?.requestNotificationsPermission();
      await androidImplementation?.requestExactAlarmsPermission();
    }
  }

  static Future<void> showInstantNotification() async {
    if (!_isInstantSupported) {
      print("⚠️ 当前平台暂不支持原生通知。");
      return;
    }
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'taskmech_channel',
          'TaskMech Reminders',
          importance: Importance.max,
          priority: Priority.high,
        );
    await _notificationsPlugin.show(
      id: 999,
      title: '⚡ 链路测试',
      body: '如果你看到了这条消息，说明底层通知模块完全正常！',
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> cancelTaskNotification(String taskId) async {
    // ⚡ 核心规避：如果是 Linux，直接拦截，防止触发 UnimplementedError
    if (!_isSchedulingSupported) {
      print("⚠️ 当前平台 (${Platform.operatingSystem}) 暂不支持底层定时闹钟机制。");
      return;
    }
    await _notificationsPlugin.cancel(id: taskId.hashCode);
  }

  static Future<void> scheduleTaskNotification(TaskModel task) async {
    // ⚡ 核心规避：如果是 Linux，直接拦截，防止触发 UnimplementedError
    if (!_isSchedulingSupported) {
      print("⚠️ 当前平台 (${Platform.operatingSystem}) 暂不支持底层定时闹钟机制。");
      return;
    }
    final int notificationId = task.id.hashCode;
    await _notificationsPlugin.cancel(id: notificationId);

    if (!task.hasReminder || task.isCompleted) return;

    try {
      final parts = task.startTime.split(':');
      final int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);

      final now = tz.TZDateTime.now(tz.local);
      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      scheduledDate = scheduledDate.subtract(
        Duration(minutes: task.reminderOffset),
      );

      if (scheduledDate.isBefore(now)) {
        if (task.loopType == 'daily') {
          scheduledDate = scheduledDate.add(const Duration(days: 1));
        } else if (task.loopType == 'weekly') {
          do {
            scheduledDate = scheduledDate.add(const Duration(days: 1));
          } while (!task.loopDays.contains(scheduledDate.weekday));
        } else if (task.loopType == 'specific') {
          return;
        }
      }

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'taskmech_channel',
            'TaskMech Reminders',
            importance: Importance.max,
            priority: Priority.high,
            ticker: 'ticker',
          );

      await _notificationsPlugin.zonedSchedule(
        id: notificationId,
        title: '⏳ 日程提醒: ${task.title}',
        body:
            '将于 ${task.reminderOffset > 0 ? "提前 ${task.reminderOffset} 分钟" : "现在"} 开始。',
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: task.loopType == 'daily'
            ? DateTimeComponents.time
            : (task.loopType == 'weekly'
                  ? DateTimeComponents.dayOfWeekAndTime
                  : null),
      );
    } catch (e) {
      print("❌ 通知模块异常: $e");
    }
  }
}
