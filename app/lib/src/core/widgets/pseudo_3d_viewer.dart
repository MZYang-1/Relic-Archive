import 'package:flutter/material.dart';

class Pseudo3DViewer extends StatefulWidget {
  final List<String> imageUrls;
  final double aspectRatio;

  const Pseudo3DViewer({
    super.key,
    required this.imageUrls,
    this.aspectRatio = 1.0,
  });

  @override
  State<Pseudo3DViewer> createState() => _Pseudo3DViewerState();
}

class _Pseudo3DViewerState extends State<Pseudo3DViewer> {
  int _currentIndex = 0;
  double _dragStartPosition = 0.0;
  int _startIndex = 0;

  @override
  void initState() {
    super.initState();
    // Default to the first image (usually '正面')
    _currentIndex = 0;
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStartPosition = details.localPosition.dx;
    _startIndex = _currentIndex;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (widget.imageUrls.isEmpty) return;

    // Sensitivity: how many pixels drag to switch one frame
    const sensitivity = 10.0;
    final delta = details.localPosition.dx - _dragStartPosition;
    final framesMoved = (delta / sensitivity).round();

    // Reverse logic: dragging left (negative delta) should rotate object right (next image)
    // or dragging left rotates view left?
    // Usually: Drag Left -> Move to Next Image in sequence (simulating spinning object counter-clockwise)

    int newIndex = _startIndex - framesMoved;

    // Wrap around logic
    final length = widget.imageUrls.length;
    newIndex = newIndex % length;
    if (newIndex < 0) newIndex += length;

    if (newIndex != _currentIndex) {
      setState(() => _currentIndex = newIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Container(
          color: Colors.grey[200],
          child: const Center(child: Text('无图像')),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: GestureDetector(
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.network(
                widget.imageUrls[_currentIndex],
                fit: BoxFit.cover,
                gaplessPlayback: true, // Crucial for smooth scrubbing
              ),
            ),
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.thirteen_mp,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '左右拖动旋转 (${_currentIndex + 1}/${widget.imageUrls.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
