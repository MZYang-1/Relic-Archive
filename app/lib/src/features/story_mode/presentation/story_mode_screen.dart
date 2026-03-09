import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../core/services/api_client.dart';
import '../../../models/item.dart';
import '../../../core/constants/api_constants.dart';

class StoryModeScreen extends StatefulWidget {
  final Item item;
  const StoryModeScreen({super.key, required this.item});

  @override
  State<StoryModeScreen> createState() => _StoryModeScreenState();
}

class _StoryModeScreenState extends State<StoryModeScreen> {
  late Item _item = widget.item;
  late PageController _pageController;
  int _currentPage = 0;
  final AudioPlayer _player = AudioPlayer();
  String? _playingUrl;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  late List<ItemEvent> _audioEvents;
  int _currentAudioIndex = -1;
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;
  String? _style;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _audioEvents = widget.item.events.where((e) => e.audioUrl != null).toList();
    _player.onDurationChanged.listen((d) {
      setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      setState(() => _position = p);
    });
    _tts.setLanguage("zh-CN");
    _tts.setSpeechRate(0.45);
  }

  @override
  void dispose() {
    _player.dispose();
    _pageController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _generateStory() async {
    try {
      final api = ApiClient();
      final updated = await api.describeItem(_item.id, style: _style);
      if (!mounted) return;
      setState(() {
        _item = updated;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('故事已生成')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    }
  }

  Future<void> _toggleSpeak() async {
    if (_speaking) {
      await _tts.stop();
      setState(() => _speaking = false);
    } else {
      final text = _item.description ?? '暂无故事描述';
      await _tts.speak(text);
      setState(() => _speaking = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = apiBaseUrl();
    final images = _item.imagePaths.map((p) => '$baseUrl$p').toList();
    final mood = (_item.aiMetadata ?? const {})['mood'] as String? ?? '宁静';

    // Determine background color based on mood (simplified)
    Color bgColor = Colors.black;
    if (mood == '怀旧') bgColor = const Color(0xFF3E2723); // Dark Brown
    if (mood == '温暖') bgColor = const Color(0xFFE65100); // Dark Orange
    if (mood == '忧郁') bgColor = const Color(0xFF1A237E); // Dark Blue

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          if (images.isNotEmpty)
            PageView.builder(
              controller: _pageController,
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) {
                return Image.network(
                  images[index],
                  fit: BoxFit.cover,
                  height: double.infinity,
                  width: double.infinity,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    );
                  },
                );
              },
            )
          else
            const Center(
              child: Text('无影像记录', style: TextStyle(color: Colors.white)),
            ),

          // Gradient overlay for text readability
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
          ),

          // Content
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_item.title != null)
                  Text(
                    _item.title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Serif', // Use a serif font for "story" feel
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _style,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('随机风格')),
                          DropdownMenuItem(
                            value: '客观档案式',
                            child: Text('客观档案式'),
                          ),
                          DropdownMenuItem(
                            value: '温柔叙述式',
                            child: Text('温柔叙述式'),
                          ),
                          DropdownMenuItem(
                            value: '博物馆标签式',
                            child: Text('博物馆标签式'),
                          ),
                          DropdownMenuItem(
                            value: '私密日记式',
                            child: Text('私密日记式'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _style = v),
                        dropdownColor: Colors.black87,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: '故事风格',
                          labelStyle: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _generateStory,
                      child: const Text('生成故事'),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: _toggleSpeak,
                      icon: Icon(
                        _speaking ? Icons.stop_circle : Icons.volume_up,
                        color: Colors.white,
                      ),
                      tooltip: '朗读',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_item.description != null)
                  Text(
                    _item.description!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                const SizedBox(height: 24),
                if (images.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(images.length, (index) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? Colors.white
                              : Colors.white24,
                        ),
                      );
                    }),
                  ),
                const SizedBox(height: 16),
                if (_audioEvents.isNotEmpty) ...[
                  SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (int i = 0; i < _audioEvents.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                final e = _audioEvents[i];
                                final base = apiBaseUrl();
                                final url = e.audioUrl!.startsWith('/')
                                    ? '$base${e.audioUrl}'
                                    : e.audioUrl!;
                                if (_playingUrl == e.audioUrl) {
                                  await _player.pause();
                                  setState(() {
                                    _playingUrl = null;
                                    _currentAudioIndex = -1;
                                  });
                                } else {
                                  await _player.stop();
                                  await _player.play(UrlSource(url));
                                  setState(() {
                                    _playingUrl = e.audioUrl;
                                    _currentAudioIndex = i;
                                  });
                                }
                              },
                              icon: Icon(
                                _playingUrl == _audioEvents[i].audioUrl
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              label: Text(_audioEvents[i].title),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_currentAudioIndex >= 0) ...[
                    Row(
                      children: [
                        IconButton(
                          onPressed: _currentAudioIndex > 0
                              ? () async {
                                  final e =
                                      _audioEvents[_currentAudioIndex - 1];
                                  final base = apiBaseUrl();
                                  final url = e.audioUrl!.startsWith('/')
                                      ? '$base${e.audioUrl}'
                                      : e.audioUrl!;
                                  await _player.stop();
                                  await _player.play(UrlSource(url));
                                  setState(() {
                                    _playingUrl = e.audioUrl;
                                    _currentAudioIndex -= 1;
                                  });
                                }
                              : null,
                          icon: const Icon(
                            Icons.skip_previous,
                            color: Colors.white,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _position.inMilliseconds.toDouble().clamp(
                              0,
                              _duration.inMilliseconds.toDouble(),
                            ),
                            max: _duration.inMilliseconds.toDouble() > 0
                                ? _duration.inMilliseconds.toDouble()
                                : 1,
                            onChanged: (v) async {
                              final pos = Duration(milliseconds: v.toInt());
                              await _player.seek(pos);
                            },
                          ),
                        ),
                        IconButton(
                          onPressed:
                              _currentAudioIndex < _audioEvents.length - 1
                              ? () async {
                                  final e =
                                      _audioEvents[_currentAudioIndex + 1];
                                  final base = apiBaseUrl();
                                  final url = e.audioUrl!.startsWith('/')
                                      ? '$base${e.audioUrl}'
                                      : e.audioUrl!;
                                  await _player.stop();
                                  await _player.play(UrlSource(url));
                                  setState(() {
                                    _playingUrl = e.audioUrl;
                                    _currentAudioIndex += 1;
                                  });
                                }
                              : null,
                          icon: const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),

          // Close button
          Positioned(
            top: 48,
            right: 24,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
            ),
          ),
        ],
      ),
    );
  }
}
