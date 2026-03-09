class ItemEvent {
  final DateTime at;
  final String title;
  final String? note;
  final String? audioUrl;
  final String? type;

  const ItemEvent({
    required this.at,
    required this.title,
    this.note,
    this.audioUrl,
    this.type,
  });

  factory ItemEvent.fromJson(Map<String, dynamic> json) {
    return ItemEvent(
      at: DateTime.parse(json['at'] as String),
      title: json['title'] as String,
      note: json['note'] as String?,
      audioUrl: json['audio_url'] as String?,
      type: json['type'] as String?,
    );
  }
}

class Item {
  final String id;
  final String? title;
  final String? category;
  final List<String> imagePaths;
  final List<String> tags;
  final String? description;
  final Map<String, dynamic>? aiMetadata;
  final DateTime? createdAt;
  final List<ItemEvent> events;
  final String? modelPath;
  final String? videoPath;

  const Item({
    required this.id,
    required this.imagePaths,
    required this.tags,
    this.title,
    this.category,
    this.description,
    this.aiMetadata,
    this.createdAt,
    this.events = const [],
    this.modelPath,
    this.videoPath,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'] as String,
      title: json['title'] as String?,
      category: json['category'] as String?,
      imagePaths: (json['image_paths'] as List<dynamic>? ?? const [])
          .cast<String>(),
      tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
      description: json['description'] as String?,
      aiMetadata: json['ai_metadata'] as Map<String, dynamic>?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      events: (json['events'] as List<dynamic>? ?? const [])
          .map((e) => ItemEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      modelPath: json['model_path'] as String?,
      videoPath: json['video_path'] as String?,
    );
  }
}
