// 位置：lib/main.dart

import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const TaskMechApp());
}

class TaskMechApp extends StatelessWidget {
  const TaskMechApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskMech',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const DashboardScreen(),
    );
  }
}
