import 'dart:convert';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/api_constants.dart';
import '../../../models/item.dart';
import '../../item_detail/presentation/item_detail_screen.dart';
import '../../subscription/presentation/subscription_screen.dart';
import '../../collections/presentation/collections_screen.dart';
import '../../timeline/presentation/timeline_screen.dart';
import 'package:http/http.dart' as http;

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<Item> _items = const [];
  bool _loading = true;
  String? _error;
  String? _mood;
  String _tag = '';
  String _q = '';
  final _moods = const ['怀旧', '温暖', '忧郁', '宁静', '神秘'];

  @override
  void initState() {
    super.initState();
    _authenticateAndLoad();
  }

  Future<void> _authenticateAndLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final requireUnlock = prefs.getBool('require_gallery_unlock') ?? true;
      if (requireUnlock) {
        try {
          final auth = LocalAuthentication();
          final canCheck = await auth.canCheckBiometrics;
          final isSupported = await auth.isDeviceSupported();
          if (canCheck && isSupported) {
            final ok = await auth.authenticate(
              localizedReason: '请进行生物识别以解锁“我的收藏馆”',
            );
            if (!ok) {
              if (!mounted) return;
              setState(() {
                _loading = false;
                _error = '解锁失败，请重试';
              });
              return;
            }
          }
        } catch (_) {
          // Fallback: allow access
        }
      }
    } catch (_) {}
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = apiBaseUrl();
      final params = <String, String>{};
      if (_mood != null && _mood!.isNotEmpty) params['mood'] = _mood!;
      if (_tag.isNotEmpty) params['tag'] = _tag;
      if (_q.isNotEmpty) params['q'] = _q;
      final uri = Uri.parse(
        '$base/items/',
      ).replace(queryParameters: params.isEmpty ? null : params);
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List<dynamic>;
        setState(() {
          _items = data
              .map((e) => Item.fromJson(e as Map<String, dynamic>))
              .toList();
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = '请求失败: ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '连接失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的收藏馆')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchItems, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏馆'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              );
            },
            icon: const Icon(Icons.workspace_premium),
            tooltip: '会员订阅',
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CollectionsScreen()),
              );
            },
            icon: const Icon(Icons.folder_special),
            tooltip: '收藏馆',
          ),
          IconButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const TimelineScreen()));
            },
            icon: const Icon(Icons.timeline),
            tooltip: '时间轴',
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _mood,
              items: [
                const DropdownMenuItem(value: null, child: Text('全部情绪')),
                for (final m in _moods)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) {
                setState(() => _mood = v);
                _fetchItems();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: TextField(
              decoration: const InputDecoration(
                hintText: '关键词',
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: (v) {
                setState(() => _q = v.trim());
                _fetchItems();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextField(
              decoration: const InputDecoration(
                hintText: '标签',
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: (v) {
                setState(() => _tag = v.trim());
                _fetchItems();
              },
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchItems,
        child: GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            final base = apiBaseUrl();
            final img = item.imagePaths.isNotEmpty
                ? '$base${item.imagePaths.first}'
                : null;
            return InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ItemDetailScreen(item: item),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    if (img != null)
                      Positioned.fill(
                        child: Image.network(img, fit: BoxFit.cover),
                      )
                    else
                      Positioned.fill(
                        child: Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Center(child: Text('无图')),
                        ),
                      ),
                    if ((item.aiMetadata ?? const {})['mood'] != null)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            (item.aiMetadata ?? const {})['mood'] as String,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
