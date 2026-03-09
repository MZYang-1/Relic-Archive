import 'dart:io';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SafeModelViewer extends StatefulWidget {
  final String src;
  final String alt;
  final bool autoRotate;
  final bool cameraControls;
  final bool ar;
  final Color backgroundColor;

  const SafeModelViewer({
    super.key,
    required this.src,
    required this.alt,
    this.autoRotate = true,
    this.cameraControls = true,
    this.ar = true,
    this.backgroundColor = Colors.transparent,
  });

  @override
  State<SafeModelViewer> createState() => _SafeModelViewerState();
}

class _SafeModelViewerState extends State<SafeModelViewer> {
  late final WebViewController _controller;
  bool _isMacOS = false;

  @override
  void initState() {
    super.initState();
    try {
      if (Platform.isMacOS) {
        _isMacOS = true;
        _controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadHtmlString(_buildHtml(widget.src));
      }
    } catch (e) {
      _isMacOS = false;
    }
  }

  String _buildHtml(String src) {
    final c = widget.backgroundColor;
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);
    final a = c.a;
    final bgColorCss = 'rgba($r, $g, $b, ${a.toStringAsFixed(3)})';

    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<script type="module" src="https://ajax.googleapis.com/ajax/libs/model-viewer/3.4.0/model-viewer.min.js"></script>
<style>
body, html { margin: 0; padding: 0; width: 100%; height: 100%; background-color: $bgColorCss; overflow: hidden; }
model-viewer { width: 100%; height: 100%; --poster-color: transparent; }
</style>
</head>
<body>
<model-viewer 
  src="$src" 
  alt="${widget.alt}"
  ${widget.autoRotate ? 'auto-rotate' : ''} 
  ${widget.cameraControls ? 'camera-controls' : ''} 
  ${widget.ar ? 'ar' : ''}
  shadow-intensity="1"
>
</model-viewer>
</body>
</html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    if (_isMacOS) {
      return WebViewWidget(controller: _controller);
    }

    return ModelViewer(
      src: widget.src,
      alt: widget.alt,
      autoRotate: widget.autoRotate,
      cameraControls: widget.cameraControls,
      ar: widget.ar,
      backgroundColor: widget.backgroundColor,
    );
  }
}
