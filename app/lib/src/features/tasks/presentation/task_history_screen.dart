import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/api_client.dart';

class TaskHistoryScreen extends StatefulWidget {
  final String? itemId;
  const TaskHistoryScreen({super.key, this.itemId});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tasks = const [];
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _fetch();
    _poller = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiClient();
      final tasks = await api.listTasks(itemId: widget.itemId);
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('任务历史')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _fetch, child: const Text('重试')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _fetch(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _tasks.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final t = _tasks[index];
                      final id = t['id'] as String?;
                      final status = t['status'] as String?;
                      final progress = t['progress'] as String?;
                      final msg = t['message'] as String?;
                      final modelPath = t['model_path'] as String?;
                      final createdAt = t['created_at']?.toString();
                      final updatedAt = t['updated_at']?.toString();
                      return ListTile(
                        title: Text('任务 $id'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('状态：${status ?? '-'}  进度：${progress ?? '-'}'),
                            if (msg != null && msg.isNotEmpty) Text('信息：$msg'),
                            if (modelPath != null) Text('模型：$modelPath'),
                            if (createdAt != null) Text('创建：$createdAt'),
                            if (updatedAt != null) Text('更新：$updatedAt'),
                          ],
                        ),
                        leading: Icon(
                          status == 'completed'
                              ? Icons.check_circle
                              : status == 'failed'
                                  ? Icons.error
                                  : Icons.timelapse,
                          color: status == 'completed'
                              ? Colors.green
                              : status == 'failed'
                                  ? Colors.red
                                  : Colors.orange,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
