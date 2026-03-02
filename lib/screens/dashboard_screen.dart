import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../models/task_model.dart';
import '../widgets/task_card.dart';
import 'add_task_screen.dart';
import '../services/github_service.dart';
import '../services/notification_service.dart'; // ⚡ 核心：引入通知通信站

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<TaskModel> _tasks = [];
  TaskModel? _tempTask;
  int? _tempIndex;

  String _avatarUrl = 'https://github.com/github.png';
  bool _showAllTasks = false;
  bool _isSyncing = false;
  String _bgPath =
      'https://images.unsplash.com/photo-1550684848-fac1c5b4e853?q=80&w=2070&auto=format&fit=crop';
  bool _isLocalBg = false;

  @override
  void initState() {
    super.initState();
    _loadFromBlackBox();
  }

  Future<void> _loadFromBlackBox() async {
    final prefs = await SharedPreferences.getInstance();

    final savedBgUrl = prefs.getString('custom_bg_url');
    final isLocal = prefs.getBool('is_local_bg') ?? false;
    if (savedBgUrl != null && savedBgUrl.isNotEmpty) {
      setState(() {
        _bgPath = savedBgUrl;
        _isLocalBg = isLocal;
      });
    }

    final repoUrl = prefs.getString('github_repo_url');
    if (repoUrl != null && repoUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(repoUrl.replaceAll('.git', ''));
        final pathSegments = uri.pathSegments;
        if (pathSegments.length >= 2) {
          final owner = pathSegments[pathSegments.length - 2];
          setState(() => _avatarUrl = 'https://github.com/$owner.png');
        }
      } catch (e) {}
    }

    final String? tasksJson = prefs.getString('mech_tasks_data');
    if (tasksJson != null) {
      final List<dynamic> decoded = jsonDecode(tasksJson);
      setState(() {
        _tasks.clear();
        _tasks.addAll(decoded.map((e) => TaskModel.fromJson(e)).toList());
      });
    }
  }

  Future<void> _saveToBlackBox() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_tasks.map((e) => e.toJson()).toList());
    await prefs.setString('mech_tasks_data', encoded);
  }

  Future<bool> _showGithubConfigDialog() async {
    final prefs = await SharedPreferences.getInstance();
    String tempUrl = prefs.getString('github_repo_url') ?? '';
    String tempToken = prefs.getString('github_token') ?? '';
    bool isConfigured = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_sync, color: Colors.blue),
            SizedBox(width: 8),
            Text(
              "配置云端同步",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "请输入您的 GitHub 凭证。为了数据安全，请务必使用私有仓库，并确保 Token 仅授予 repo 权限。",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: tempUrl),
              decoration: const InputDecoration(
                labelText: "GitHub 仓库地址",
                hintText: "例如: https://github.com/usr/usr_schedule",
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => tempUrl = val,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: TextEditingController(text: tempToken),
              decoration: const InputDecoration(
                labelText: "Personal Access Token",
                hintText: "ghp_xxxxxxxxxxxx",
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              onChanged: (val) => tempToken = val,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (tempUrl.isNotEmpty && tempToken.isNotEmpty) {
                await prefs.setString('github_repo_url', tempUrl.trim());
                await prefs.setString('github_token', tempToken.trim());

                try {
                  final uri = Uri.parse(tempUrl.trim().replaceAll('.git', ''));
                  final pathSegments = uri.pathSegments;
                  if (pathSegments.length >= 2) {
                    final owner = pathSegments[pathSegments.length - 2];
                    setState(
                      () => _avatarUrl = 'https://github.com/$owner.png',
                    );
                  }
                } catch (e) {}

                isConfigured = true;
                if (mounted) Navigator.pop(context);
              } else {
                _showSnackBar("⚠️ 请填写完整信息", Colors.red);
              }
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
    return isConfigured;
  }

  Future<void> _triggerCloudSync() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('github_token');
    final repoUrl = prefs.getString('github_repo_url');

    if (token == null || token.isEmpty || repoUrl == null || repoUrl.isEmpty) {
      final configured = await _showGithubConfigDialog();
      if (!configured) return;
    }

    setState(() => _isSyncing = true);

    try {
      final cloudTasks = await GithubService.fetchTasksFromCloud();

      if (cloudTasks == null) {
        _showSnackBar("⚠️ 凭证无效或网络错误，请重新配置", Colors.red);
        await _showGithubConfigDialog();
        setState(() => _isSyncing = false);
        return;
      }

      final bool isCloudEmpty = cloudTasks.isEmpty;
      final bool isLocalEmpty = _tasks.isEmpty;

      bool isIdentical = false;
      if (!isLocalEmpty &&
          !isCloudEmpty &&
          _tasks.length == cloudTasks.length) {
        final localSorted = List<TaskModel>.from(_tasks)
          ..sort((a, b) => a.id.compareTo(b.id));
        final cloudSorted = List<TaskModel>.from(cloudTasks)
          ..sort((a, b) => a.id.compareTo(b.id));

        final localJson = jsonEncode(
          localSorted.map((e) => e.toJson()).toList(),
        );
        final cloudJson = jsonEncode(
          cloudSorted.map((e) => e.toJson()).toList(),
        );

        if (localJson == cloudJson) {
          isIdentical = true;
        }
      }

      if (isCloudEmpty && isLocalEmpty) {
        _showSnackBar("☁️ 云端与本地均无计划，已保持同步", Colors.blueGrey);
      } else if (isIdentical) {
        _showSnackBar("✅ 数据已是最新，无需同步", Colors.green);
      } else if (!isLocalEmpty && isCloudEmpty) {
        final success = await GithubService.syncToCloud(_tasks);
        _showSnackBar(
          success ? "☁️ 已将本地计划上传至云端" : "⚠️ 上传失败，请检查网络",
          success ? Colors.green : Colors.red,
        );
      } else if (isLocalEmpty && !isCloudEmpty) {
        setState(() {
          _tasks.clear();
          _tasks.addAll(cloudTasks);
        });
        await _saveToBlackBox();

        // ⚡ 云端拉取后，重新计算并挂载所有本地通知
        for (var task in _tasks) {
          NotificationService.scheduleTaskNotification(task);
        }

        _showSnackBar("☁️ 已从云端拉取 ${cloudTasks.length} 个计划", Colors.green);
      } else {
        setState(() => _isSyncing = false);
        _showConflictDialog(cloudTasks);
        return;
      }
    } catch (e) {
      _showSnackBar("⚠️ 同步发生异常", Colors.red);
    }

    setState(() => _isSyncing = false);
  }

  void _showSnackBar(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showConflictDialog(List<TaskModel> cloudTasks) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue, size: 28),
            SizedBox(width: 8),
            Text("数据同步冲突", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "本地现有 ${_tasks.length} 个计划，云端有 ${cloudTasks.length} 个计划。\n\n请选择要保留的数据版本（覆盖后不可恢复）：",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isSyncing = true);

              // ⚡ 覆盖前先清除所有旧通知
              for (var t in _tasks) {
                NotificationService.cancelTaskNotification(t.id);
              }

              setState(() {
                _tasks.clear();
                _tasks.addAll(cloudTasks);
              });
              await _saveToBlackBox();

              // ⚡ 重新挂载新通知
              for (var t in _tasks) {
                NotificationService.scheduleTaskNotification(t);
              }

              setState(() => _isSyncing = false);
              _showSnackBar("☁️ 已下载云端数据 (本地被覆盖)", Colors.blue);
            },
            child: const Text("⬇️ 保留云端数据"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isSyncing = true);
              final success = await GithubService.syncToCloud(_tasks);
              setState(() => _isSyncing = false);
              _showSnackBar(
                success ? "☁️ 已强制上传 (云端被覆盖)" : "⚠️ 上传失败",
                success ? Colors.green : Colors.red,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text(
              "⬆️ 保留本地数据",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLocalImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_bg_url', image.path);
      await prefs.setBool('is_local_bg', true);

      setState(() {
        _bgPath = image.path;
        _isLocalBg = true;
      });
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _changeBackground() async {
    String tempUrl = '';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "更换壁纸",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: _pickLocalImage,
              icon: const Icon(Icons.photo_library),
              label: const Text("从本地相册选择"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "或者使用网络图片:",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: "输入图片 URL",
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => tempUrl = val,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('custom_bg_url');
              await prefs.remove('is_local_bg');
              setState(() {
                _bgPath =
                    'https://images.unsplash.com/photo-1550684848-fac1c5b4e853?q=80&w=2070&auto=format&fit=crop';
                _isLocalBg = false;
              });
              if (mounted) Navigator.pop(context);
            },
            child: const Text("恢复默认", style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              if (tempUrl.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('custom_bg_url', tempUrl);
                await prefs.setBool('is_local_bg', false);
                setState(() {
                  _bgPath = tempUrl;
                  _isLocalBg = false;
                });
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text("应用网络图"),
          ),
        ],
      ),
    );
  }

  List<TaskModel> get _todayTasks {
    final now = DateTime.now();
    return _tasks.where((task) {
      if (task.loopType == 'daily') return true;
      if (task.loopType == 'weekly') return task.loopDays.contains(now.weekday);
      if (task.loopType == 'specific') {
        return task.specificDates.any(
          (d) => d.year == now.year && d.month == now.month && d.day == now.day,
        );
      }
      return false;
    }).toList();
  }

  void _undoAction() {
    if (_tempTask != null && _tempIndex != null) {
      setState(() {
        _tasks.insert(_tempIndex!, _tempTask!);
      });
      _saveToBlackBox();
      NotificationService.scheduleTaskNotification(_tempTask!); // ⚡ 恢复时重新注册通知

      setState(() {
        _tempTask = null;
        _tempIndex = null;
      });
    }
  }

  void _deleteTask(TaskModel task) {
    NotificationService.cancelTaskNotification(task.id); // ⚡ 删除任务时取消闹钟
    setState(() {
      _tempIndex = _tasks.indexOf(task);
      _tempTask = task;
      _tasks.remove(task);
    });
    _saveToBlackBox();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("计划已删除"),
        action: SnackBarAction(label: "撤销", onPressed: _undoAction),
      ),
    );
  }

  Future<void> _editTask(TaskModel task) async {
    final int realIndex = _tasks.indexOf(task);
    final updatedTask = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddTaskScreen(initialTask: task)),
    );
    if (updatedTask != null) {
      setState(() => _tasks[realIndex] = updatedTask);
      _saveToBlackBox();
      NotificationService.scheduleTaskNotification(updatedTask); // ⚡ 更新任务时重设闹钟
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayTasks = _showAllTasks ? _tasks : _todayTasks;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: Colors.black87,
          image: DecorationImage(
            image: _isLocalBg
                ? FileImage(File(_bgPath)) as ImageProvider
                : NetworkImage(_bgPath),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const Divider(height: 1, thickness: 1, color: Colors.white24),
              Expanded(
                child: displayTasks.isEmpty
                    ? Center(
                        child: Text(
                          _showAllTasks
                              ? "暂无任何计划\n点击右上角新建"
                              : "今日暂无日程\n点击右上角新建计划",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                      )
                    : _buildTaskList(displayTasks),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⚡ 极简版 Header：已彻底移除臃肿的时间显示
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 只有左侧的头像
          GestureDetector(
            onTap: () async {
              await _showGithubConfigDialog();
            },
            child: Tooltip(
              message: "点击修改 GitHub 配置",
              child: CircleAvatar(
                radius: 20,
                backgroundImage: NetworkImage(_avatarUrl),
                backgroundColor: Colors.white,
              ),
            ),
          ),

          // 右侧的按键列队
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _showAllTasks ? Icons.today : Icons.list_alt,
                  color: _showAllTasks ? Colors.cyanAccent : Colors.white,
                ),
                onPressed: () => setState(() => _showAllTasks = !_showAllTasks),
                tooltip: _showAllTasks ? "返回今日日程" : "查看全部计划 (往期/将来)",
              ),
              // 在“撤销”按钮的上方或下方，加入这个测试按钮
              IconButton(
                icon: const Icon(
                  Icons.notifications_active,
                  color: Colors.amberAccent,
                ),
                onPressed: () async {
                  await NotificationService.showInstantNotification();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("已触发测试通知，请看手机顶部！")),
                  );
                },
                tooltip: "测试通信链路",
              ),
              IconButton(
                icon: const Icon(Icons.undo_rounded, color: Colors.white),
                onPressed: _tempTask != null ? _undoAction : null,
                tooltip: "撤销删除",
              ),
              _isSyncing
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.cyanAccent,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.cloud_sync, color: Colors.white),
                      onPressed: _triggerCloudSync,
                      tooltip: "同步至 GitHub",
                    ),
              IconButton(
                icon: const Icon(Icons.wallpaper, color: Colors.white),
                onPressed: _changeBackground,
                tooltip: "更换壁纸",
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_circle,
                  color: Colors.cyanAccent,
                  size: 28,
                ),
                onPressed: () async {
                  if (_tasks.length >= 4096) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("提示：数据量已达系统上限")),
                    );
                    return;
                  }
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddTaskScreen(),
                    ),
                  );
                  if (result != null) {
                    setState(() => _tasks.add(result));
                    _saveToBlackBox();

                    // ⚡ 核心修复：创建任务后正式向系统注册通知闹钟！
                    NotificationService.scheduleTaskNotification(result);

                    final now = DateTime.now();
                    bool isToday =
                        result.loopType == 'daily' ||
                        (result.loopType == 'weekly' &&
                            result.loopDays.contains(now.weekday)) ||
                        (result.loopType == 'specific' &&
                            result.specificDates.any(
                              (d) =>
                                  d.year == now.year &&
                                  d.month == now.month &&
                                  d.day == now.day,
                            ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isToday ? "✅ 已添加至今日日程" : "🗄️ 计划已保存 (非今日日程，已隐藏)",
                        ),
                        backgroundColor: isToday
                            ? Colors.green
                            : Colors.blueGrey,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(List<TaskModel> displayTasks) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: displayTasks.length,
      itemBuilder: (context, index) {
        final task = displayTasks[index];
        return TaskCard(
          task: task,
          onToggle: () {
            setState(() => task.isCompleted = !task.isCompleted);
            _saveToBlackBox();
            // ⚡ 打钩完成后，取消闹钟防止干扰
            if (task.isCompleted) {
              NotificationService.cancelTaskNotification(task.id);
            } else {
              NotificationService.scheduleTaskNotification(task);
            }
          },
          onDelete: () => _deleteTask(task),
          onEdit: () => _editTask(task),
        );
      },
    );
  }
}
