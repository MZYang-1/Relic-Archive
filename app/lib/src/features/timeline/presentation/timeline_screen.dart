import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../core/constants/api_constants.dart';
import '../../../models/item.dart';
import '../../item_detail/presentation/item_detail_screen.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/api_client.dart';
import '../../../core/theme/event_type_theme.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  bool _loading = true;
  String? _error;
  List<Item> _items = const [];
  String? _selectedItemId;
  final AudioPlayer _player = AudioPlayer();
  String? _playingUrl;
  String? _mood;
  final _moods = const ['怀旧', '温暖', '忧郁', '宁静', '神秘'];
  String? _type;
  // final _types = const ['购买', '修理', '赠与', '使用', '清洁', '移动', '拍照', '录音', '其他'];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = apiBaseUrl();
      final params = <String, String>{'sort': 'created_desc'};
      if (_mood != null && _mood!.isNotEmpty) params['mood'] = _mood!;
      final uri = Uri.parse('$base/items/').replace(queryParameters: params);
      final resp = await http.get(uri);

      if (!mounted) return;

      if (resp.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = '请求失败: ${resp.statusCode}';
        });
        return;
      }
      final data = jsonDecode(resp.body) as List<dynamic>;
      setState(() {
        _items = data
            .map((e) => Item.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '连接失败: $e';
      });
    }
  }

  String _groupKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  List<({DateTime at, Item item, ItemEvent? event})> _entries() {
    final out = <({DateTime at, Item item, ItemEvent? event})>[];
    for (final item in _items) {
      if (item.events.isNotEmpty) {
        for (final e in item.events) {
          if (_type == null || _type!.isEmpty || e.type == _type) {
            out.add((at: e.at, item: item, event: e));
          }
        }
      } else if (item.createdAt != null) {
        out.add((at: item.createdAt!, item: item, event: null));
      }
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('时间轴')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetch, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final entries = _entries();
    final groups =
        <String, List<({DateTime at, Item item, ItemEvent? event})>>{};
    for (final entry in entries) {
      final key = _groupKey(entry.at);
      groups
          .putIfAbsent(
            key,
            () => <({DateTime at, Item item, ItemEvent? event})>[],
          )
          .add(entry);
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final base = apiBaseUrl();

    return Scaffold(
      appBar: AppBar(title: const Text('时间轴')),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: keys.fold<int>(
            0,
            (sum, k) => sum + 1 + (groups[k]?.length ?? 0),
          ),
          itemBuilder: (context, index) {
            var cursor = 0;
            for (final key in keys) {
              if (index == cursor) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    key,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              cursor += 1;
              var items = groups[key]!;
              if (_selectedItemId != null) {
                items = items
                    .where((e) => e.item.id == _selectedItemId)
                    .toList();
                if (items.isEmpty) {
                  cursor += (groups[key]?.length ?? 0);
                  continue;
                }
              }
              if (index < cursor + items.length) {
                final entry = items[index - cursor];
                final item = entry.item;
                final img = item.imagePaths.isNotEmpty
                    ? '$base${item.imagePaths.first}'
                    : null;
                final mood = (item.aiMetadata ?? const {})['mood'] as String?;
                final eventTitle = entry.event?.title ?? '创建档案';
                final dateText =
                    '${entry.at.year}-${entry.at.month.toString().padLeft(2, '0')}-${entry.at.day.toString().padLeft(2, '0')}';
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: img != null
                        ? Image.network(
                            img,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: const Center(child: Text('无图')),
                          ),
                  ),
                  title: Text(item.title ?? '未命名物品'),
                  subtitle: Text(
                    entry.event?.type != null
                        ? '$dateText · $eventTitle · ${entry.event!.type}${mood != null ? ' · $mood' : ''}'
                        : (mood != null
                              ? '$dateText · $eventTitle · $mood'
                              : '$dateText · $eventTitle'),
                  ),
                  trailing: entry.event != null
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (entry.event!.type != null)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: EventTypeTheme.getColor(
                                    entry.event!.type!,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: EventTypeTheme.getColor(
                                      entry.event!.type!,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  entry.event!.type!,
                                  style: TextStyle(
                                    color: EventTypeTheme.getColor(
                                      entry.event!.type!,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            if (entry.event!.audioUrl != null)
                              IconButton(
                                icon: Icon(
                                  _playingUrl == entry.event!.audioUrl
                                      ? Icons.pause_circle
                                      : Icons.play_circle,
                                ),
                                onPressed: () async {
                                  final url = entry.event!.audioUrl!;
                                  final abs = url.startsWith('/')
                                      ? '$base$url'
                                      : url;
                                  if (_playingUrl == url) {
                                    await _player.pause();
                                    if (context.mounted) {
                                      setState(() => _playingUrl = null);
                                    }
                                  } else {
                                    await _player.stop();
                                    await _player.play(UrlSource(abs));
                                    if (context.mounted) {
                                      setState(() => _playingUrl = url);
                                    }
                                  }
                                },
                              ),
                            PopupMenuButton<String>(
                              onSelected: (val) async {
                                final idx = item.events.indexOf(entry.event!);
                                if (idx < 0) return;
                                if (val == 'delete') {
                                  setState(() => _loading = true);
                                  try {
                                    final api = ApiClient(baseUrl: base);
                                    await api.deleteItemEvent(
                                      itemId: item.id,
                                      index: idx,
                                    );
                                    if (context.mounted) await _fetch();
                                  } finally {
                                    if (context.mounted) {
                                      setState(() => _loading = false);
                                    }
                                  }
                                } else if (val == 'edit') {
                                  final titleController = TextEditingController(
                                    text: entry.event!.title,
                                  );
                                  final noteController = TextEditingController(
                                    text: entry.event!.note ?? '',
                                  );
                                  final audioController = TextEditingController(
                                    text: entry.event!.audioUrl ?? '',
                                  );
                                  DateTime selected = entry.event!.at;
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => StatefulBuilder(
                                      builder: (context, setLocal) => AlertDialog(
                                        title: const Text('编辑事件'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextField(
                                              controller: titleController,
                                              decoration: const InputDecoration(
                                                labelText: '事件标题',
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            TextField(
                                              controller: noteController,
                                              decoration: const InputDecoration(
                                                labelText: '备注(可选)',
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            TextField(
                                              controller: audioController,
                                              decoration: const InputDecoration(
                                                labelText: '音频URL(可选)',
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Text(
                                                  '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}',
                                                ),
                                                const Spacer(),
                                                TextButton(
                                                  onPressed: () async {
                                                    final picked =
                                                        await showDatePicker(
                                                          context: context,
                                                          firstDate: DateTime(
                                                            1970,
                                                          ),
                                                          lastDate:
                                                              DateTime.now().add(
                                                                const Duration(
                                                                  days: 3650,
                                                                ),
                                                              ),
                                                          initialDate: selected,
                                                        );
                                                    if (picked != null) {
                                                      setLocal(
                                                        () => selected = picked,
                                                      );
                                                    }
                                                  },
                                                  child: const Text('选日期'),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('保存'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (ok == true) {
                                    setState(() => _loading = true);
                                    try {
                                      final api = ApiClient(baseUrl: base);
                                      await api.updateItemEvent(
                                        itemId: item.id,
                                        index: idx,
                                        at: selected,
                                        title: titleController.text.trim(),
                                        note: noteController.text.trim(),
                                        audioUrl:
                                            audioController.text.trim().isEmpty
                                            ? null
                                            : audioController.text.trim(),
                                      );
                                      if (context.mounted) await _fetch();
                                    } finally {
                                      if (context.mounted) {
                                        setState(() => _loading = false);
                                      }
                                    }
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('编辑')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除'),
                                ),
                              ],
                            ),
                          ],
                        )
                      : null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ItemDetailScreen(item: item),
                      ),
                    );
                  },
                );
              }
              cursor += items.length;
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            const Text('仅看物品'),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedItemId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部')),
                  for (final it in _items)
                    DropdownMenuItem(
                      value: it.id,
                      child: Text(it.title ?? it.id),
                    ),
                ],
                onChanged: (v) => setState(() => _selectedItemId = v),
              ),
            ),
            const SizedBox(width: 12),
            const Text('情绪'),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _mood,
              items: [
                const DropdownMenuItem(value: null, child: Text('全部')),
                for (final m in _moods)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) {
                setState(() => _mood = v);
                _fetch();
              },
            ),
            const SizedBox(width: 12),
            const Text('类型'),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _type,
              items: [
                const DropdownMenuItem(value: null, child: Text('全部')),
                for (final t in EventTypeTheme.types)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) {
                setState(() => _type = v);
                _fetch();
              },
            ),
          ],
        ),
      ),
    );
  }
}
