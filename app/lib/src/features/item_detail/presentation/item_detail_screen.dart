import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/widgets/safe_model_viewer.dart';
import '../../../core/widgets/pseudo_3d_viewer.dart';
import '../../../models/item.dart';
import '../../../core/services/api_client.dart';
import '../../../core/theme/event_type_theme.dart';
import '../../story_mode/presentation/story_mode_screen.dart';
import '../../tasks/presentation/task_history_screen.dart';

class ItemDetailScreen extends StatefulWidget {
  final Item item;
  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late Item item = widget.item;
  bool loading = false;
  final moods = const ['怀旧', '温暖', '忧郁', '宁静', '神秘'];
  List<String> editTags = const [];
  String? selectedMood;
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  final AudioPlayer _player = AudioPlayer();
  String? _playingUrl;
  String? _taskId;
  String? _taskProgress;
  String? _taskStatus;
  late final PageController _imagePager;
  double _imagePage = 0.0;
  final GlobalKey _shareKey = GlobalKey();
  VideoPlayerController? _videoController;
  Future<void>? _videoInit;
  bool _is3DMode = false;

  @override
  void initState() {
    super.initState();
    editTags = List<String>.from(item.tags);
    selectedMood = item.aiMetadata?['mood'] as String?;
    _imagePager = PageController();
    _imagePager.addListener(() {
      final p = _imagePager.hasClients ? (_imagePager.page ?? 0.0) : 0.0;
      if (p != _imagePage && mounted) {
        setState(() => _imagePage = p);
      }
    });
  }

  @override
  void dispose() {
    _imagePager.dispose();
    _player.dispose();
    _recorder.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _openModelFullScreen() {
    final path = item.modelPath;
    if (path == null) return;
    final src = path.startsWith('/') ? '${apiBaseUrl()}$path' : path;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _ModelViewerFullScreen(src: src, title: item.title ?? '3D 模型'),
      ),
    );
  }

  Future<void> _generate() async {
    setState(() => loading = true);
    try {
      final api = ApiClient();
      final updated = await api.describeItem(item.id);
      if (mounted) setState(() => item = updated);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _addToCollection() async {
    setState(() => loading = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final api = ApiClient();
      final cols = await api.listCollections();
      if (!mounted) return;
      String? selectedId;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('加入收藏馆'),
            content: SizedBox(
              width: 320,
              child: cols.isEmpty
                  ? const Text('暂无收藏馆，请先在“我的收藏馆”创建')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: cols.length,
                      itemBuilder: (context, index) {
                        final c = cols[index];
                        final id = c['id'] as String;
                        final name = c['name'] as String? ?? '未命名';
                        final count =
                            (c['items'] as List<dynamic>? ?? const []).length;
                        final selected = selectedId == id;
                        return ListTile(
                          title: Text(name),
                          subtitle: Text('共 $count 件'),
                          trailing: selected
                              ? const Icon(Icons.check_circle)
                              : null,
                          onTap: () => setLocal(() => selectedId = id),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确定'),
              ),
            ],
          ),
        ),
      );
      if (ok == true && selectedId != null) {
        await api.addItemToCollection(
          collectionId: selectedId!,
          itemId: item.id,
        );
        messenger?.showSnackBar(const SnackBar(content: Text('已加入收藏馆')));
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('加入失败: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<ItemEvent> _sortedEvents() {
    final events = List<ItemEvent>.from(item.events);
    events.sort((a, b) => b.at.compareTo(a.at));
    return events;
  }

  Future<void> _checkTask() async {
    if (_taskId == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final api = ApiClient();
      final task = await api.getTaskStatus(_taskId!);
      if (!mounted) return;

      setState(() {
        _taskStatus = task['status'] as String?;
        _taskProgress = task['progress'] as String?;
      });

      if (_taskStatus == 'completed') {
        _taskId = null;
        messenger?.showSnackBar(const SnackBar(content: Text('模型生成成功！')));
        final refreshed = await api.getItem(item.id);
        if (!mounted) return;
        setState(() => item = refreshed);
      } else if (_taskStatus == 'failed') {
        _taskId = null;
        messenger?.showSnackBar(
          SnackBar(content: Text('生成失败: ${task['message']}')),
        );
      } else {
        Future.delayed(const Duration(seconds: 2), _checkTask);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _taskId = null;
        _taskStatus = 'failed';
      });
      messenger?.showSnackBar(SnackBar(content: Text('任务查询失败: $e')));
    }
  }

  Future<void> _shareImage() async {
    try {
      final boundary =
          _shareKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/share_${item.id}.png').create();
      await file.writeAsBytes(pngBytes);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: '来自旧物志的分享: ${item.title}'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分享失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = apiBaseUrl();
    final images = item.imagePaths.map((p) => '$baseUrl$p').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title ?? '物品档案'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '分享',
            onPressed: _shareImage,
          ),
          IconButton(
            icon: const Icon(Icons.auto_stories),
            tooltip: '故事模式',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StoryModeScreen(item: item)),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              if (v == 'hide') {
                if (!editTags.contains('hidden')) {
                  setState(() {
                    editTags = List.of(editTags)..add('hidden');
                    loading = true;
                  });
                  try {
                    final api = ApiClient();
                    final updated = await api.updateItem(
                      item.id,
                      tags: editTags,
                    );
                    if (mounted) setState(() => item = updated);
                    if (mounted) {
                      messenger?.showSnackBar(
                        const SnackBar(content: Text('已隐藏/归档，物品将模糊显示')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => loading = false);
                  }
                } else {
                  // Unhide
                  setState(() {
                    editTags = List.of(editTags)..remove('hidden');
                    loading = true;
                  });
                  try {
                    final api = ApiClient();
                    final updated = await api.updateItem(
                      item.id,
                      tags: editTags,
                    );
                    if (mounted) setState(() => item = updated);
                    if (mounted) {
                      messenger?.showSnackBar(
                        const SnackBar(content: Text('已取消隐藏')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => loading = false);
                  }
                }
              }
            },
            itemBuilder: (context) {
              final isHidden = editTags.contains('hidden');
              return [
                PopupMenuItem(
                  value: 'hide',
                  child: Text(isHidden ? '取消隐藏' : '隐藏/归档 (心理安全)'),
                ),
              ];
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (images.isNotEmpty)
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _is3DMode
                          ? Pseudo3DViewer(imageUrls: images)
                          : PageView.builder(
                              controller: _imagePager,
                              itemCount: images.length,
                              itemBuilder: (context, index) {
                                final delta = index - _imagePage;
                                final shift = (delta * 18).clamp(-24.0, 24.0);
                                return Transform.translate(
                                  offset: Offset(shift, 0),
                                  child: RepaintBoundary(
                                    key: index == (_imagePage.round())
                                        ? _shareKey
                                        : null,
                                    child: Image.network(
                                      images[index],
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    if (!_is3DMode && images.length > 1)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 10,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(images.length, (i) {
                            final active = (_imagePage.round() == i);
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: active ? 18 : 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(
                                  alpha: active ? 0.55 : 0.25,
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            );
                          }),
                        ),
                      ),
                    if (images.length > 1)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton.filledTonal(
                          onPressed: () {
                            setState(() {
                              _is3DMode = !_is3DMode;
                            });
                          },
                          icon: Icon(
                            _is3DMode ? Icons.view_carousel : Icons.thirteen_mp,
                          ),
                          tooltip: _is3DMode ? '切换至普通视图' : '切换至伪3D视图',
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            Container(
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: const Center(child: Text('暂无图片')),
            ),
          const SizedBox(height: 16),
          Text('ID: ${item.id}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (item.category != null) Text('分类：${item.category}'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in editTags)
                Chip(
                  label: Text(t),
                  onDeleted: () {
                    setState(() {
                      editTags = List.of(editTags)..remove(t);
                    });
                  },
                ),
              ActionChip(
                label: const Text('添加标签'),
                onPressed: () async {
                  final controller = TextEditingController();
                  await showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('添加标签'),
                      content: TextField(controller: controller),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () {
                            final v = controller.text.trim();
                            if (v.isNotEmpty) {
                              setState(() {
                                editTags = List.of(editTags)..add(v);
                              });
                            }
                            Navigator.pop(context);
                          },
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: selectedMood != null && moods.contains(selectedMood)
                ? selectedMood
                : null,
            items: [
              for (final m in moods) DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => selectedMood = v),
            decoration: const InputDecoration(labelText: '情绪'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: loading
                ? null
                : () async {
                    setState(() => loading = true);
                    try {
                      final api = ApiClient();
                      final updated = await api.updateItem(
                        item.id,
                        tags: editTags,
                        mood: selectedMood,
                      );
                      setState(() => item = updated);
                    } finally {
                      setState(() => loading = false);
                    }
                  },
            icon: const Icon(Icons.save),
            label: const Text('保存标签与情绪'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: loading ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('生成AI描述'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: loading ? null : _addToCollection,
            icon: const Icon(Icons.folder_special),
            label: const Text('加入收藏馆'),
          ),
          if (item.videoPath != null) ...[
            const SizedBox(height: 12),
            FutureBuilder<void>(
              future: () {
                if (_videoController == null) {
                  final base = ApiClient().baseUrl;
                  final url = item.videoPath!.startsWith('/')
                      ? '$base${item.videoPath}'
                      : item.videoPath!;
                  _videoController = VideoPlayerController.networkUrl(
                    Uri.parse(url),
                  );
                  _videoInit = _videoController!.initialize();
                }
                return _videoInit!;
              }(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                return Column(
                  children: [
                    AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio == 0
                          ? 16 / 9
                          : _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            final c = _videoController!;
                            if (c.value.isPlaying) {
                              c.pause();
                            } else {
                              c.play();
                            }
                            setState(() {});
                          },
                          icon: Icon(
                            _videoController!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                        Text(
                          '${_videoController!.value.position.inSeconds}s / ${_videoController!.value.duration.inSeconds}s',
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () =>
                              _videoController!.seekTo(Duration.zero),
                          icon: const Icon(Icons.replay),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: loading
                ? null
                : () async {
                    setState(() => loading = true);
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    try {
                      final boundary =
                          _shareKey.currentContext?.findRenderObject()
                              as RenderRepaintBoundary?;
                      if (boundary == null) {
                        messenger?.showSnackBar(
                          const SnackBar(content: Text('请先选择一张图片')),
                        );
                      } else {
                        final image = await boundary.toImage(pixelRatio: 2.0);
                        final byteData = await image.toByteData(
                          format: ui.ImageByteFormat.png,
                        );
                        if (byteData != null) {
                          final bytes = byteData.buffer.asUint8List();
                          final tmp = await getTemporaryDirectory();
                          final filePath = '${tmp.path}/share_${item.id}.png';
                          final f = File(filePath);
                          await f.writeAsBytes(bytes);
                          await SharePlus.instance.share(
                            ShareParams(
                              files: [XFile(filePath)],
                              text: item.title ?? '旧物志',
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      messenger?.showSnackBar(
                        SnackBar(content: Text('生成分享卡片失败: $e')),
                      );
                    } finally {
                      if (mounted) setState(() => loading = false);
                    }
                  },
            icon: const Icon(Icons.share),
            label: const Text('生成分享卡片'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: loading
                ? null
                : () async {
                    setState(() => loading = true);
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    try {
                      final api = ApiClient();
                      final updated = await api.classifyItem(item.id);
                      setState(() {
                        item = updated;
                        editTags = List<String>.from(item.tags);
                      });
                      messenger?.showSnackBar(
                        const SnackBar(content: Text('已应用智能分类与标签')),
                      );
                    } finally {
                      setState(() => loading = false);
                    }
                  },
            icon: const Icon(Icons.category),
            label: const Text('智能分类'),
          ),
          if (item.description != null) ...[
            const SizedBox(height: 12),
            Text(
              item.description!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          if (_taskId != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '3D 重建中...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _taskProgress != null
                        ? double.tryParse(_taskProgress!.replaceAll('%', ''))! /
                              100
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(_taskProgress ?? 'Waiting...'),
                  if (_taskStatus != null)
                    Text(
                      _taskStatus!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TaskHistoryScreen(itemId: item.id),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('查看任务历史'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Text('3D 档案', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (item.modelPath == null) ...[
                if (item.imagePaths.isNotEmpty)
                  TextButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            setState(() => loading = true);
                            try {
                              final api = ApiClient();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('正在基于已有影像生成模型...'),
                                ),
                              );
                              final updated = await api.reconstructFromExisting(
                                item.id,
                              );
                              if (!context.mounted) return;
                              setState(() => item = updated);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('模型生成成功！')),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('生成失败: $e')),
                              );
                            } finally {
                              if (mounted) setState(() => loading = false);
                            }
                          },
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('用已有影像建模'),
                  ),
                TextButton.icon(
                  onPressed: loading
                      ? null
                      : () async {
                          final result = await FilePicker.platform.pickFiles(
                            allowMultiple: true,
                            type: FileType.image,
                          );
                          if (!context.mounted) return;
                          if (result != null && result.files.isNotEmpty) {
                            setState(() => loading = true);
                            try {
                              final api = ApiClient();
                              final files = result.files
                                  .map((f) => File(f.path!))
                                  .toList();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('正在上传图片并创建任务...')),
                              );
                              final task = await api.reconstructModel(
                                item.id,
                                files,
                              );
                              if (!context.mounted) return;
                              setState(() {
                                _taskId = task['id'] as String;
                                _taskStatus = 'pending';
                                _taskProgress = '0%';
                              });
                              _checkTask();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('提交失败: $e')),
                              );
                            } finally {
                              if (mounted) setState(() => loading = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('照片建模'),
                ),
                TextButton.icon(
                  onPressed: loading
                      ? null
                      : () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.any,
                          );
                          if (result != null &&
                              result.files.single.path != null) {
                            setState(() => loading = true);
                            try {
                              final api = ApiClient();
                              final file = File(result.files.single.path!);
                              final res = await api.uploadModel(file);
                              final path = res['path'] as String;
                              final updated = await api.updateItem(
                                item.id,
                                modelPath: path,
                              );
                              if (!context.mounted) return;
                              setState(() => item = updated);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('上传失败: $e')),
                              );
                            } finally {
                              if (mounted) setState(() => loading = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('上传模型'),
                ),
              ],
            ],
          ),
          if (item.modelPath != null)
            GestureDetector(
              onTap: _openModelFullScreen,
              child: Container(
                height: 300,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black12,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SafeModelViewer(
                          backgroundColor: Platform.isMacOS
                              ? Colors.white
                              : Colors.transparent,
                          src: item.modelPath!.startsWith('/')
                              ? '${apiBaseUrl()}${item.modelPath}'
                              : item.modelPath!,
                          alt: "A 3D model of ${item.title}",
                          ar: true,
                          autoRotate: true,
                          cameraControls: true,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(24),
                          child: IconButton(
                            onPressed: _openModelFullScreen,
                            icon: const Icon(
                              Icons.open_in_full,
                              color: Colors.white,
                              size: 20,
                            ),
                            tooltip: '全屏查看',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('时间轴', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: loading
                    ? null
                    : () async {
                        final titleController = TextEditingController();
                        final noteController = TextEditingController();
                        DateTime selected = DateTime.now();
                        String? eventType;

                        final audioController = TextEditingController();
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => StatefulBuilder(
                            builder: (context, setLocal) => AlertDialog(
                              title: const Text('添加事件'),
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
                                      hintText: '例如 /uploads/xxx.m4a',
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
                                          final picked = await showDatePicker(
                                            context: context,
                                            firstDate: DateTime(1970),
                                            lastDate: DateTime.now().add(
                                              const Duration(days: 3650),
                                            ),
                                            initialDate: selected,
                                          );
                                          if (picked != null) {
                                            setLocal(() => selected = picked);
                                          }
                                        },
                                        child: const Text('选日期'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          final hasPerm = await _recorder
                                              .hasPermission();
                                          if (!hasPerm) return;
                                          final tmp =
                                              await getTemporaryDirectory();
                                          final filePath =
                                              '${tmp.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
                                          await _recorder.start(
                                            const RecordConfig(
                                              encoder: AudioEncoder.aacLc,
                                              bitRate: 128000,
                                              sampleRate: 44100,
                                            ),
                                            path: filePath,
                                          );
                                          setLocal(() => _isRecording = true);
                                        },
                                        icon: const Icon(Icons.mic),
                                        label: const Text('开始录音'),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton.icon(
                                        onPressed: !_isRecording
                                            ? null
                                            : () async {
                                                final path = await _recorder
                                                    .stop();
                                                setLocal(
                                                  () => _isRecording = false,
                                                );
                                                if (path != null) {
                                                  final api = ApiClient();
                                                  final upload = await api
                                                      .uploadAudio(File(path));
                                                  final url =
                                                      upload['url'] as String?;
                                                  if (url != null) {
                                                    audioController.text = url;
                                                  }
                                                }
                                              },
                                        icon: const Icon(Icons.stop),
                                        label: const Text('结束并上传'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    initialValue: eventType,
                                    items: [
                                      const DropdownMenuItem(
                                        value: null,
                                        child: Text('事件类型(可选)'),
                                      ),
                                      for (final t in EventTypeTheme.types)
                                        DropdownMenuItem(
                                          value: t,
                                          child: Text(t),
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setLocal(() => eventType = v),
                                    decoration: const InputDecoration(
                                      labelText: '类型',
                                    ),
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
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('保存'),
                                ),
                              ],
                            ),
                          ),
                        );

                        if (ok != true) return;
                        final title = titleController.text.trim();
                        final note = noteController.text.trim();
                        final audioUrlText = audioController.text.trim();
                        final audioUrl = audioUrlText.isEmpty
                            ? null
                            : audioUrlText;
                        if (title.isEmpty) return;

                        setState(() => loading = true);
                        try {
                          final api = ApiClient();
                          final updated = await api.appendItemEvent(
                            itemId: item.id,
                            at: selected,
                            title: title,
                            note: note.isEmpty ? null : note,
                            audioUrl: audioUrl,
                            type: eventType,
                          );
                          setState(() => item = updated);
                        } finally {
                          setState(() => loading = false);
                        }
                      },
                icon: const Icon(Icons.add),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in _sortedEvents())
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Icon(EventTypeTheme.getIcon(e.type), size: 16),
                  const SizedBox(width: 6),
                  Text(e.title),
                  if (e.type != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(context).colorScheme.secondaryContainer,
                      ),
                      child: Text(
                        e.type!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  if (e.audioUrl != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.audiotrack, size: 16),
                  ],
                ],
              ),
              subtitle: e.note != null
                  ? Text(
                      '${e.at.year}-${e.at.month.toString().padLeft(2, '0')}-${e.at.day.toString().padLeft(2, '0')}  ${e.note}',
                    )
                  : Text(
                      '${e.at.year}-${e.at.month.toString().padLeft(2, '0')}-${e.at.day.toString().padLeft(2, '0')}',
                    ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (e.audioUrl != null)
                    IconButton(
                      icon: Icon(
                        _playingUrl == e.audioUrl
                            ? Icons.pause_circle
                            : Icons.play_circle,
                      ),
                      onPressed: () async {
                        final base = apiBaseUrl();
                        final url = e.audioUrl!.startsWith('/')
                            ? '$base${e.audioUrl}'
                            : e.audioUrl!;
                        if (_playingUrl == e.audioUrl) {
                          await _player.pause();
                          setState(() => _playingUrl = null);
                        } else {
                          await _player.stop();
                          await _player.play(UrlSource(url));
                          setState(() => _playingUrl = e.audioUrl);
                        }
                      },
                    ),
                  PopupMenuButton<String>(
                    onSelected: (val) async {
                      if (val == 'delete') {
                        final idx = item.events.indexOf(e);
                        if (idx >= 0) {
                          setState(() => loading = true);
                          try {
                            final api = ApiClient();
                            final updated = await api.deleteItemEvent(
                              itemId: item.id,
                              index: idx,
                            );
                            setState(() => item = updated);
                          } finally {
                            setState(() => loading = false);
                          }
                        }
                      } else if (val == 'edit') {
                        final titleController = TextEditingController(
                          text: e.title,
                        );
                        final noteController = TextEditingController(
                          text: e.note ?? '',
                        );
                        final audioController = TextEditingController(
                          text: e.audioUrl ?? '',
                        );
                        DateTime selected = e.at;
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
                                          final picked = await showDatePicker(
                                            context: context,
                                            firstDate: DateTime(1970),
                                            lastDate: DateTime.now().add(
                                              const Duration(days: 3650),
                                            ),
                                            initialDate: selected,
                                          );
                                          if (picked != null) {
                                            setLocal(() => selected = picked);
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
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('保存'),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (ok == true) {
                          final idx = item.events.indexOf(e);
                          if (idx >= 0) {
                            setState(() => loading = true);
                            try {
                              final api = ApiClient();
                              final updated = await api.updateItemEvent(
                                itemId: item.id,
                                index: idx,
                                at: selected,
                                title: titleController.text.trim(),
                                note: noteController.text.trim(),
                                audioUrl: audioController.text.trim().isEmpty
                                    ? null
                                    : audioController.text.trim(),
                              );
                              setState(() => item = updated);
                            } finally {
                              setState(() => loading = false);
                            }
                          }
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelViewerFullScreen extends StatelessWidget {
  final String src;
  final String title;

  const _ModelViewerFullScreen({required this.src, required this.title});

  @override
  Widget build(BuildContext context) {
    final bg = Platform.isMacOS ? Colors.white : Colors.black;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Platform.isMacOS ? Colors.black : Colors.white,
        title: Text(title),
      ),
      body: SafeArea(
        child: SafeModelViewer(
          backgroundColor: bg,
          src: src,
          alt: title,
          ar: true,
          autoRotate: true,
          cameraControls: true,
        ),
      ),
    );
  }
}
