import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _requireUnlock = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getBool('require_gallery_unlock') ?? true;
    if (!mounted) return;
    setState(() {
      _requireUnlock = val;
      _loading = false;
    });
  }

  Future<void> _save(bool v) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('require_gallery_unlock', v);
    if (!mounted) return;
    setState(() => _requireUnlock = v);
    messenger?.showSnackBar(const SnackBar(content: Text('设置已保存')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('进入“我的收藏馆”前要求生物识别解锁'),
                  value: _requireUnlock,
                  onChanged: _save,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    '退出登录',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('退出登录'),
                        content: const Text('确定要退出当前账号吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('退出'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('access_token');
                      if (!mounted) return;
                      navigator.pushNamedAndRemoveUntil(
                        '/login',
                        (route) => false,
                      );
                    }
                  },
                ),
              ],
            ),
    );
  }
}
