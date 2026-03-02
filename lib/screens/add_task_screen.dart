import 'package:flutter/material.dart';
import '../models/task_model.dart'; // 修复了包名引用，使用相对路径更安全

class AddTaskScreen extends StatefulWidget {
  final TaskModel? initialTask;
  const AddTaskScreen({super.key, this.initialTask});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  // 通知引擎状态变量
  bool _hasReminder = false;
  final _offsetController = TextEditingController(text: '15');

  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);

  String _loopType = 'daily';
  List<int> _selectedDays = [];
  List<DateTime> _specificDates = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialTask != null) {
      final t = widget.initialTask!;
      _titleController.text = t.title;
      _descController.text = t.description;
      _startTime = _parseTime(t.startTime);
      _endTime = _parseTime(t.endTime);
      _loopType = t.loopType;
      _selectedDays = List.from(t.loopDays);
      _specificDates = List.from(t.specificDates);
      // 恢复旧任务的提醒设置
      _hasReminder = t.hasReminder;
      _offsetController.text = t.reminderOffset.toString();
    }
  }

  TimeOfDay _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return const TimeOfDay(hour: 9, minute: 0);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _offsetController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() => isStart ? _startTime = picked : _endTime = picked);
    }
  }

  Future<void> _pickSpecificDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );

    if (picked != null) {
      bool exists = _specificDates.any(
        (d) =>
            d.year == picked.year &&
            d.month == picked.month &&
            d.day == picked.day,
      );
      if (!exists) {
        setState(() {
          _specificDates.add(picked);
          _specificDates.sort((a, b) => a.compareTo(b));
        });
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("该日期已在计划中！")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.red),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.initialTask == null ? "新建计划" : "编辑计划",
          style: const TextStyle(color: Colors.black),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green, size: 30),
            onPressed: () {
              // 1. 标题校验
              if (_titleController.text.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("提示：标题不能为空！")));
                return;
              }

              // 2. ⚡ 提前时间校验 (已移出错误的作用域)
              final offset = int.tryParse(_offsetController.text) ?? 0;
              if (_hasReminder && (offset < 0 || offset > 1440)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("提示：提前时间必须在 0 到 1440 分钟之间")),
                );
                return;
              }

              // 3. 组装数据兵器 (已移除重复参数)
              final task = TaskModel(
                id:
                    widget.initialTask?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                title: _titleController.text,
                description: _descController.text,
                // ⚡ 核心修复：强制转换为纯净的 HH:mm 24小时制，杜绝一切 AM/PM 导致的解析崩溃
                startTime:
                    '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                endTime:
                    '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
                loopType: _loopType,
                loopDays: _loopType == 'weekly' ? _selectedDays : [],
                specificDates: _loopType == 'specific' ? _specificDates : [],
                hasReminder: _hasReminder,
                reminderOffset: offset,
              );
              Navigator.pop(context, task);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        // ⚡ 核心修复：确保所有组件都在 children 的中括号里面
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: "标题",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _descController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "描述 (选填)",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 25),

          const Text("时间段:", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              _timeBox(true),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text("至"),
              ),
              _timeBox(false),
            ],
          ),

          const SizedBox(height: 25),
          const Divider(),
          const SizedBox(height: 10),

          const Text('循环模式:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _buildLoopSelector(),

          const SizedBox(height: 15),
          if (_loopType == 'weekly') _buildWeeklySelector(),
          if (_loopType == 'specific') _buildSpecificDateSelector(),

          // ⚡ 通知组件已归队至正确位置
          const SizedBox(height: 15),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              "开启准点/提前提醒",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text("系统将在设定时间推送本地通知"),
            value: _hasReminder,
            activeThumbColor: Colors.blue,
            onChanged: (val) => setState(() => _hasReminder = val),
          ),
          if (_hasReminder)
            Row(
              children: [
                const Text("提前 "),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _offsetController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Text(" 分钟提醒 (最大1440)"),
              ],
            ),
        ],
      ),
    );
  }

  Widget _timeBox(bool isStart) {
    return Expanded(
      child: InkWell(
        onTap: () => _pickTime(isStart),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              isStart ? _startTime.format(context) : _endTime.format(context),
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoopSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        ChoiceChip(
          label: const Text("每天"),
          selected: _loopType == 'daily',
          onSelected: (_) => setState(() => _loopType = 'daily'),
        ),
        ChoiceChip(
          label: const Text("每周"),
          selected: _loopType == 'weekly',
          onSelected: (_) => setState(() => _loopType = 'weekly'),
        ),
        ChoiceChip(
          label: const Text("特定日期"),
          selected: _loopType == 'specific',
          onSelected: (_) => setState(() => _loopType = 'specific'),
        ),
      ],
    );
  }

  Widget _buildWeeklySelector() {
    final weekDays = ['一', '二', '三', '四', '五', '六', '日'];
    return Wrap(
      spacing: 8,
      children: List.generate(7, (index) {
        final day = index + 1;
        return FilterChip(
          label: Text("周${weekDays[index]}"),
          selected: _selectedDays.contains(day),
          onSelected: (selected) {
            setState(() {
              selected ? _selectedDays.add(day) : _selectedDays.remove(day);
              if (_selectedDays.length == 7) {
                _loopType = 'daily';
                _selectedDays.clear();
              }
            });
          },
        );
      }),
    );
  }

  Widget _buildSpecificDateSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "已选特定日期 (上限 10 天):",
                style: TextStyle(color: Colors.blueGrey),
              ),
              Text(
                "${_specificDates.length} / 10",
                style: TextStyle(
                  color: _specificDates.length >= 10 ? Colors.red : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._specificDates.map(
                (date) => Chip(
                  label: Text("${date.year}/${date.month}/${date.day}"),
                  deleteIcon: const Icon(Icons.cancel, size: 18),
                  onDeleted: () => setState(() => _specificDates.remove(date)),
                  backgroundColor: Colors.blue.shade50,
                ),
              ),
              if (_specificDates.length < 10)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18, color: Colors.blue),
                  label: const Text(
                    "添加日期",
                    style: TextStyle(color: Colors.blue),
                  ),
                  backgroundColor: Colors.white,
                  shape: const StadiumBorder(
                    side: BorderSide(color: Colors.blue),
                  ),
                  onPressed: _pickSpecificDate,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
