import 'package:flutter/material.dart';

class EventTypeConfig {
  final String label;
  final Color color;
  final IconData icon;

  const EventTypeConfig({
    required this.label,
    required this.color,
    required this.icon,
  });
}

class EventTypeTheme {
  static const Map<String, EventTypeConfig> _configs = {
    '购买': EventTypeConfig(
      label: '购买',
      color: Color(0xFF1565C0), // Blue 800
      icon: Icons.shopping_cart,
    ),
    '修理': EventTypeConfig(
      label: '修理',
      color: Color(0xFF00897B), // Teal 600
      icon: Icons.build,
    ),
    '赠与': EventTypeConfig(
      label: '赠与',
      color: Color(0xFF8E24AA), // Purple 600
      icon: Icons.card_giftcard,
    ),
    '使用': EventTypeConfig(
      label: '使用',
      color: Color(0xFF5D4037), // Brown 600
      icon: Icons.touch_app,
    ),
    '清洁': EventTypeConfig(
      label: '清洁',
      color: Color(0xFF2E7D32), // Green 800
      icon: Icons.cleaning_services,
    ),
    '移动': EventTypeConfig(
      label: '移动',
      color: Color(0xFF546E7A), // Blue Grey 600
      icon: Icons.local_shipping,
    ),
    '拍照': EventTypeConfig(
      label: '拍照',
      color: Color(0xFFFFA000), // Amber 700
      icon: Icons.camera_alt,
    ),
    '录音': EventTypeConfig(
      label: '录音',
      color: Color(0xFFD81B60), // Pink 600
      icon: Icons.mic,
    ),
    '其他': EventTypeConfig(
      label: '其他',
      color: Color(0xFF616161), // Grey 700
      icon: Icons.more_horiz,
    ),
  };

  static List<String> get types => _configs.keys.toList();

  static Color getColor(String? type) {
    if (type == null) return const Color(0xFF424242);
    return _configs[type]?.color ?? const Color(0xFF424242);
  }

  static IconData getIcon(String? type) {
    if (type == null) return Icons.event;
    return _configs[type]?.icon ?? Icons.event;
  }

  static EventTypeConfig? getConfig(String? type) {
    return _configs[type];
  }
}
