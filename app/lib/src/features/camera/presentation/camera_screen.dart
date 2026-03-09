import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import '../../../core/services/api_client.dart';
import '../../item_detail/presentation/item_detail_screen.dart';
import 'dart:math' as math;

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isUploading = false;
  final List<_CapturedShot> _shots = [];
  final List<File> _videos = [];

  bool _initError = false;
  bool _showGuide = true;
  bool _detailMode = false;
  bool _videoMode = false;
  bool _aiMode = false;
  bool _isLowLight = false;
  bool _isProcessingFrame = false;
  String _aiMessage = '';

  bool _recording = false;
  int _recordSeconds = 0;
  static const int _maxVideoSeconds = 10;
  Timer? _timer;
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  // Animation controller for AI scanning effect
  late AnimationController _scanController;

  static const List<String> _recommendedShots = [
    '正面',
    '背面',
    '左侧',
    '右侧',
    '顶部',
    '细节1',
    '细节2',
  ];
  static const List<String> _detailShots = ['细节1', '细节2', '细节3'];
  List<String> get _recShots => _detailMode ? _detailShots : _recommendedShots;

  Future<Duration> _getVideoDuration(File file) async {
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    final d = controller.value.duration;
    await controller.dispose();
    return d;
  }

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _initError = true);
        return;
      }
      final camera = _cameras!.first;
      _controller = CameraController(camera, ResolutionPreset.medium);
      await _controller!.initialize();
      try {
        final minZoom = await _controller!.getMinZoomLevel();
        final maxZoom = await _controller!.getMaxZoomLevel();
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _zoom = _minZoom;
        await _controller!.setZoomLevel(_zoom);
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
    if (_aiMode &&
        _controller != null &&
        _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    _scanController.dispose();
    _controller?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _processCameraImage(CameraImage image) {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    // Run heavy computation in a microtask or isolate ideally,
    // but for simple luminance sampling, async here is okay.
    Future.microtask(() {
      try {
        if (!mounted || !_aiMode) {
          _isProcessingFrame = false;
          return;
        }

        // Simple luminance check on Y plane (plane 0)
        // We don't need to check every pixel. Sampling is enough.
        final plane = image.planes[0];
        final bytes = plane.bytes;
        final stride = plane.bytesPerRow; // width equivalent in bytes mostly
        // Sample center area
        int totalY = 0;
        int count = 0;

        // Check every 20th pixel in every 20th row to save CPU
        final height = image.height;
        final width = image.width;

        for (int y = 0; y < height; y += 20) {
          for (int x = 0; x < width; x += 20) {
            final index = y * stride + x;
            if (index < bytes.length) {
              totalY += bytes[index];
              count++;
            }
          }
        }

        if (count > 0) {
          final avgY = totalY / count;
          final isLow = avgY < 50; // Threshold for "Low Light"
          if (isLow != _isLowLight) {
            setState(() => _isLowLight = isLow);
          }
        }
      } catch (e) {
        debugPrint('Error processing image: $e');
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> _toggleAI() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Disable AI if switching OFF
    if (_aiMode) {
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
      setState(() {
        _aiMode = false;
        _isLowLight = false;
        _aiMessage = '';
      });
      return;
    }

    // Enable AI
    // Note: ImageStream might conflict with Video Recording on some devices.
    // We will disable AI automatically if recording starts.
    try {
      await _controller!.startImageStream(_processCameraImage);
      setState(() {
        _aiMode = true;
        _aiMessage = 'AI 助手已激活';
      });
      // Clear message after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _aiMode) setState(() => _aiMessage = '');
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法启动 AI 模式: $e')));
      }
    }
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_videoMode) {
      // Stop AI stream if running, as it might conflict with video recording
      if (_aiMode && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
        setState(() {
          _aiMode = false;
          _isLowLight = false;
        });
      }

      if (_recording) {
        final xfile = await _controller!.stopVideoRecording();
        _timer?.cancel();
        _recording = false;
        final tmpDir = await getTemporaryDirectory();
        final saved = await File(xfile.path).copy(
          p.join(tmpDir.path, '${DateTime.now().millisecondsSinceEpoch}.mp4'),
        );
        _videos.add(saved);
        if (mounted) setState(() {});
      } else {
        _recordSeconds = 0;
        _recording = true;
        await _controller!.startVideoRecording();
        _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
          _recordSeconds += 1;
          if (_recordSeconds >= _maxVideoSeconds) {
            final xfile = await _controller!.stopVideoRecording();
            _timer?.cancel();
            _recording = false;
            final tmpDir = await getTemporaryDirectory();
            final saved = await File(xfile.path).copy(
              p.join(
                tmpDir.path,
                '${DateTime.now().millisecondsSinceEpoch}.mp4',
              ),
            );
            _videos.add(saved);
            if (mounted) setState(() {});
          } else {
            if (mounted) setState(() {});
          }
        });
        if (mounted) setState(() {});
      }
      return;
    }
    final tmpDir = await getTemporaryDirectory();
    final filePath = p.join(
      tmpDir.path,
      '${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final xfile = await _controller!.takePicture();
    final saved = await File(xfile.path).copy(filePath);
    final label = _shots.length < _recShots.length
        ? _recShots[_shots.length]
        : '补拍${_shots.length - _recommendedShots.length + 1}';
    _shots.add(_CapturedShot(file: saved, label: label));
    if (mounted) setState(() {});
  }

  void _removeShot(int index) {
    if (index < 0 || index >= _shots.length) return;
    setState(() => _shots.removeAt(index));
  }

  Future<void> _uploadAllAndCreate() async {
    if (_shots.isEmpty && _videos.isEmpty) return;
    setState(() => _isUploading = true);
    try {
      final api = ApiClient();
      final urls = <String>[];
      for (final s in _shots) {
        final upload = await api.uploadImage(s.file);
        final url = upload['url'] as String?;
        if (url != null) urls.add(url);
      }
      var item = await api.createItem(imagePaths: urls);
      item = await api.describeItem(item.id);
      if (_videos.isNotEmpty) {
        final upload = await api.uploadVideo(_videos.first);
        final url = upload['url'] as String?;
        if (url != null) {
          item = await api.updateItem(item.id, videoPath: url);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('上传失败: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
      _shots.clear();
      _videos.clear();
    }
  }

  Future<void> _showVideoPreview(File file) async {
    final ctrl = VideoPlayerController.file(file);
    await ctrl.initialize();
    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          content: AspectRatio(
            aspectRatio: ctrl.value.aspectRatio == 0
                ? 16 / 9
                : ctrl.value.aspectRatio,
            child: VideoPlayer(ctrl),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ctrl.pause();
                Navigator.pop(dialogContext);
              },
              child: const Text('关闭'),
            ),
            TextButton(
              onPressed: () => ctrl.seekTo(Duration.zero),
              child: const Text('重播'),
            ),
            TextButton(
              onPressed: () {
                if (ctrl.value.isPlaying) {
                  ctrl.pause();
                } else {
                  ctrl.play();
                }
                (dialogContext as Element).markNeedsBuild();
              },
              child: Text(ctrl.value.isPlaying ? '暂停' : '播放'),
            ),
          ],
        );
      },
    );
    await ctrl.dispose();
  }

  Widget _guideOverlay(BuildContext context) {
    final total = _recShots.length;
    final done = _shots.length.clamp(0, total);
    final progress = total > 0 ? done / total : 0.0;
    final next = done < total ? _recShots[done] : null;
    final missing = done < total ? _recShots.sublist(done) : const <String>[];

    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _showGuide
                ? Container(
                    key: const ValueKey('guide_open'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _detailMode ? '细节模式' : '多角度拍摄引导',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _toggleAI,
                              icon: Icon(
                                Icons.auto_awesome,
                                color: _aiMode ? Colors.amber : Colors.white,
                              ),
                              tooltip: 'AI 辅助',
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _videoMode = !_videoMode),
                              icon: Icon(
                                _videoMode
                                    ? Icons.videocam
                                    : Icons.photo_camera,
                                color: Colors.white,
                              ),
                              tooltip: _videoMode ? '视频模式' : '照片模式',
                            ),
                            Switch(
                              value: _detailMode,
                              onChanged: (v) => setState(() => _detailMode = v),
                              activeThumbImage: null,
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _showGuide = false),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          next != null
                              ? (_detailMode ? '建议靠近拍摄：$next' : '下一张建议：$next')
                              : (_detailMode
                                    ? '已完成细节拍摄，可继续补拍其他细节'
                                    : '已完成推荐角度，可继续补拍细节'),
                          style: const TextStyle(color: Colors.white),
                        ),
                        if (missing.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '缺角：${missing.join('、')}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: List.generate(_recShots.length, (i) {
                            final completed = _shots.length > i;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: completed
                                    ? Colors.white.withValues(alpha: 0.20)
                                    : Colors.black.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: completed
                                      ? Colors.white.withValues(alpha: 0.6)
                                      : Colors.white.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Text(
                                _recShots[i],
                                style: TextStyle(
                                  color: Colors.white.withValues(
                                    alpha: completed ? 1 : 0.7,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  )
                : Align(
                    key: const ValueKey('guide_closed'),
                    alignment: Alignment.topRight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: IconButton(
                        onPressed: () => setState(() => _showGuide = true),
                        icon: const Icon(
                          Icons.help_outline,
                          color: Colors.white,
                        ),
                        tooltip: '拍摄引导',
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnailStrip(BuildContext context) {
    final hasShots = _shots.isNotEmpty || _videos.isNotEmpty;
    if (!hasShots) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 92),
          child: SizedBox(
            height: 84,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: _shots.length + _videos.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index < _shots.length) {
                  final s = _shots[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          s.file,
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            s.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(99),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(99),
                            onTap: () => _removeShot(index),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                final v = _videos[index - _shots.length];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: GestureDetector(
                        onTap: () => _showVideoPreview(v),
                        child: Stack(
                          children: [
                            Image.file(
                              v,
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                            const Positioned(
                              right: 6,
                              bottom: 6,
                              child: Icon(Icons.videocam, color: Colors.white),
                            ),
                            Positioned(
                              left: 6,
                              bottom: 6,
                              child: FutureBuilder<Duration>(
                                future: _getVideoDuration(v),
                                builder: (context, snapshot) {
                                  final dur = snapshot.data;
                                  final mm = ((dur?.inSeconds ?? 0) ~/ 60)
                                      .toString()
                                      .padLeft(2, '0');
                                  final ss = ((dur?.inSeconds ?? 0) % 60)
                                      .toString()
                                      .padLeft(2, '0');
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.55,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$mm:$ss',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(99),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(99),
                          onTap: () {
                            setState(() => _videos.remove(v));
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initError) {
      return Scaffold(
        appBar: AppBar(title: const Text('拍摄')),
        body: const Center(child: Text('无法初始化相机或无可用相机')),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('拍摄')),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          if (_aiMode)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _scanController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _AIScannerPainter(
                        isLowLight: _isLowLight,
                        animationValue: _scanController.value,
                      ),
                    );
                  },
                ),
              ),
            ),
          if (_isLowLight)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wb_sunny_outlined,
                        color: Colors.amber,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '光线较暗，建议开启补光灯',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_aiMessage.isNotEmpty)
            Positioned(
              top: 150,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _aiMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          if (_detailMode)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ReticlePainter()),
              ),
            ),
          if (_videoMode && _recording)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'REC ${_recordSeconds}s',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          _guideOverlay(context),
          _thumbnailStrip(context),
          if (_isUploading)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
          if (_detailMode)
            Positioned(
              left: 16,
              right: 16,
              bottom: 176,
              child: Slider(
                min: _minZoom,
                max: _maxZoom,
                value: _zoom.clamp(_minZoom, _maxZoom),
                onChanged: (v) async {
                  setState(() => _zoom = v);
                  try {
                    await _controller!.setZoomLevel(v);
                  } catch (_) {}
                },
              ),
            ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            onPressed: _isUploading ? null : _capture,
            child: Icon(
              _videoMode
                  ? (_recording ? Icons.stop : Icons.videocam)
                  : Icons.camera,
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            onPressed: _isUploading || (_shots.isEmpty && _videos.isEmpty)
                ? null
                : _uploadAllAndCreate,
            icon: const Icon(Icons.check),
            label: Text('完成(${_shots.length + _videos.length})'),
          ),
        ],
      ),
    );
  }
}

class _CapturedShot {
  final File file;
  final String label;

  const _CapturedShot({required this.file, required this.label});
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final r = (size.shortestSide * 0.18).clamp(52.0, 110.0);
    final rect = Rect.fromCenter(center: center, width: r * 2, height: r * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      paint,
    );

    final tick = r * 0.35;
    canvas.drawLine(
      Offset(center.dx - tick, center.dy),
      Offset(center.dx + tick, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - tick),
      Offset(center.dx, center.dy + tick),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AIScannerPainter extends CustomPainter {
  final bool isLowLight;
  final double animationValue;

  _AIScannerPainter({required this.isLowLight, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final center = Offset(size.width / 2, size.height / 2);
    // Dynamic size based on animation
    final baseSize = size.shortestSide * 0.7;
    final breathe = 10.0 * math.sin(animationValue * math.pi * 2);
    final rectSize = baseSize + breathe;

    final rect = Rect.fromCenter(
      center: center,
      width: rectSize,
      height: rectSize * 1.2, // Slightly vertical for objects
    );

    // Color changes based on status
    if (isLowLight) {
      paint.color = Colors.amber.withValues(alpha: 0.6);
    } else {
      paint.color = Colors.blueAccent.withValues(alpha: 0.6);
    }

    // Draw corners
    final cornerLen = 30.0;

    // Top Left
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(cornerLen, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, cornerLen), paint);

    // Top Right
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(-cornerLen, 0),
      paint,
    );
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, cornerLen), paint);

    // Bottom Left
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(cornerLen, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(0, -cornerLen),
      paint,
    );

    // Bottom Right
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(-cornerLen, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(0, -cornerLen),
      paint,
    );

    // Draw scanning line
    if (!isLowLight) {
      final scanY = rect.top + (rect.height * animationValue);
      final scanPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.blueAccent.withValues(alpha: 0),
            Colors.blueAccent.withValues(alpha: 0.5),
            Colors.blueAccent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(rect.left, scanY, rect.width, 4));

      canvas.drawRect(
        Rect.fromLTWH(rect.left, scanY, rect.width, 2),
        scanPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AIScannerPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isLowLight != isLowLight;
  }
}
