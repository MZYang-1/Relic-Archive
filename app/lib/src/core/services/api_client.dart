import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../../models/item.dart';

class ApiClient {
  final String baseUrl;
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? apiBaseUrl();

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final uri = Uri.parse('$baseUrl/token');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    if (response.statusCode != 200) {
      throw Exception('Login failed: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', data['access_token']);
    return data;
  }

  Future<Map<String, dynamic>> register(String email, String password) async {
    final uri = Uri.parse('$baseUrl/users/');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Register failed: ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Item>> listItems({
    String? query,
    String? tag,
    String? mood,
    String? category,
  }) async {
    final uri = Uri.parse('$baseUrl/items/').replace(
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
        if (mood != null && mood.isNotEmpty) 'mood': mood,
        if (category != null && category.isNotEmpty) 'category': category,
      },
    );
    final response = await http.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('List items failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as List<dynamic>;
    return body.map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Item> getItem(String itemId) async {
    final uri = Uri.parse('$baseUrl/items/$itemId');
    final response = await http.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(
        'Get item failed: ${response.statusCode} ${response.body}',
      );
    }
    return Item.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> uploadImage(File file) async {
    final uri = Uri.parse('$baseUrl/upload/');
    final request = http.MultipartRequest('POST', uri);
    final token = await _getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final filename = p.basename(file.path);
    MediaType? type;
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.jpg' || ext == '.jpeg') {
      type = MediaType('image', 'jpeg');
    } else if (ext == '.png') {
      type = MediaType('image', 'png');
    } else if (ext == '.webp') {
      type = MediaType('image', 'webp');
    } else if (ext == '.gif') {
      type = MediaType('image', 'gif');
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: filename,
        contentType: type,
      ),
    );
    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Upload failed: ${response.statusCode}');
    }
    final body = await response.stream.bytesToString();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadModel(File file) async {
    final uri = Uri.parse('$baseUrl/upload/model/');
    final request = http.MultipartRequest('POST', uri);
    final token = await _getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final filename = p.basename(file.path);
    request.files.add(
      await http.MultipartFile.fromPath('file', file.path, filename: filename),
    );
    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Model upload failed: ${response.statusCode}');
    }
    final body = await response.stream.bytesToString();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadVideo(File file) async {
    final uri = Uri.parse('$baseUrl/upload/video/');
    final request = http.MultipartRequest('POST', uri);
    final token = await _getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final filename = p.basename(file.path);
    MediaType? type;
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.mp4') {
      type = MediaType('video', 'mp4');
    } else if (ext == '.mov') {
      type = MediaType('video', 'quicktime');
    } else if (ext == '.avi') {
      type = MediaType('video', 'x-msvideo');
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: filename,
        contentType: type,
      ),
    );
    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Video upload failed: ${response.statusCode}');
    }
    final body = await response.stream.bytesToString();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reconstructModel(
    String itemId,
    List<File> files,
  ) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/reconstruct');
    final request = http.MultipartRequest('POST', uri);
    final token = await _getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    for (var file in files) {
      final filename = p.basename(file.path);
      request.files.add(
        await http.MultipartFile.fromPath(
          'files',
          file.path,
          filename: filename,
        ),
      );
    }

    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Reconstruction failed: ${response.statusCode}');
    }
    final body = await response.stream.bytesToString();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getTaskStatus(String taskId) async {
    final uri = Uri.parse('$baseUrl/tasks/$taskId');
    final response = await http.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('Get task failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listTasks({String? itemId}) async {
    final uri = Uri.parse(
      '$baseUrl/tasks/',
    ).replace(queryParameters: itemId != null ? {'item_id': itemId} : null);
    final response = await http.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('List tasks failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as List<dynamic>;
    return body.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<Item> reconstructFromExisting(String itemId) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/reconstruct_from_existing');
    final response = await http.post(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(
        'Reconstruct from existing failed: ${response.statusCode} ${response.body}',
      );
    }
    return Item.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Item> createItem({
    List<String> imagePaths = const [],
    String? title,
  }) async {
    final uri = Uri.parse('$baseUrl/items/');
    final response = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode({'title': title, 'image_paths': imagePaths}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Create item failed: ${response.statusCode} ${response.body}',
      );
    }
    return Item.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Item> appendItemImage({
    required String itemId,
    required String url,
  }) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/images');
    final response = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode({'url': url}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Append image failed: ${response.statusCode} ${response.body}',
      );
    }
    return Item.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Item> describeItem(String itemId, {String? style}) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/describe');
    final response = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode({'style': style}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Describe item failed: ${response.statusCode} ${response.body}',
      );
    }
    return Item.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Item> classifyItem(String itemId) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/classify');
    final response = await http.post(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(
        'Classify item failed: ${response.statusCode} ${response.body}',
      );
    }
    return Item.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> listCollections() async {
    final uri = Uri.parse('$baseUrl/collections/');
    final resp = await http.get(uri, headers: await _headers());
    if (resp.statusCode != 200) {
      throw Exception('List collections failed: ${resp.statusCode}');
    }
    return (jsonDecode(resp.body) as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  Future<Map<String, dynamic>> createCollection({
    required String name,
    String? description,
    String? theme,
    bool? isPrivate,
  }) async {
    final uri = Uri.parse('$baseUrl/collections/');
    final resp = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'description': description,
        'theme': theme,
        'is_private': isPrivate,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Create collection failed: ${resp.statusCode} ${resp.body}',
      );
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<Item>> listCollectionItems(String collectionId) async {
    final uri = Uri.parse('$baseUrl/collections/$collectionId/items');
    final resp = await http.get(uri, headers: await _headers());
    if (resp.statusCode != 200) {
      throw Exception('List collection items failed: ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as List<dynamic>;
    return body.map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addItemToCollection({
    required String collectionId,
    required String itemId,
  }) async {
    final uri = Uri.parse('$baseUrl/collections/$collectionId/items');
    final resp = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode({'item_id': itemId}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Add item to collection failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<void> removeItemFromCollection({
    required String collectionId,
    required String itemId,
  }) async {
    final uri = Uri.parse('$baseUrl/collections/$collectionId/items/$itemId');
    final resp = await http.delete(uri, headers: await _headers());
    if (resp.statusCode != 200) {
      throw Exception(
        'Remove item from collection failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<Map<String, dynamic>> updateCollection({
    required String collectionId,
    String? name,
    String? description,
    String? theme,
    bool? isPrivate,
  }) async {
    final uri = Uri.parse('$baseUrl/collections/$collectionId');
    final resp = await http.patch(
      uri,
      headers: await _headers(),
      body: jsonEncode({
        ...?(name == null ? null : {'name': name}),
        ...?(description == null ? null : {'description': description}),
        ...?(theme == null ? null : {'theme': theme}),
        ...?(isPrivate == null ? null : {'is_private': isPrivate}),
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Update collection failed: ${resp.statusCode} ${resp.body}',
      );
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Item> updateItem(
    String itemId, {
    List<String>? tags,
    String? mood,
    String? modelPath,
    String? videoPath,
  }) async {
    final uri = Uri.parse('$baseUrl/items/$itemId');
    final body = <String, dynamic>{};
    if (tags != null) body['tags'] = tags;
    if (mood != null) body['ai_metadata'] = {'mood': mood};
    if (modelPath != null) body['model_path'] = modelPath;
    if (videoPath != null) body['video_path'] = videoPath;
    final response = await http.patch(
      uri,
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Update item failed: ${response.statusCode} ${response.body}',
      );
    }
    return Item.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Item> appendItemEvent({
    required String itemId,
    required DateTime at,
    required String title,
    String? note,
    String? audioUrl,
    String? type,
  }) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/events');
    final response = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode({
        'at': at.toIso8601String(),
        'title': title,
        'note': note,
        'audio_url': audioUrl,
        'type': type,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Append event failed: ${response.statusCode} ${response.body}',
      );
    }
    return Item.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> uploadAudio(File file) async {
    final uri = Uri.parse('$baseUrl/upload/audio/');
    final request = http.MultipartRequest('POST', uri);
    final token = await _getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final filename = p.basename(file.path);
    MediaType? type;
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.m4a') {
      type = MediaType('audio', 'mp4');
    } else if (ext == '.mp3') {
      type = MediaType('audio', 'mpeg');
    } else if (ext == '.wav') {
      type = MediaType('audio', 'wav');
    } else if (ext == '.aac') {
      type = MediaType('audio', 'aac');
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: filename,
        contentType: type,
      ),
    );
    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Upload audio failed: ${response.statusCode}');
    }
    final body = await response.stream.bytesToString();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Item> deleteItemEvent({
    required String itemId,
    required int index,
  }) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/events/$index');
    final response = await http.delete(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(
        'Delete event failed: ${response.statusCode} ${response.body}',
      );
    }
    return Item.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Item> updateItemEvent({
    required String itemId,
    required int index,
    DateTime? at,
    String? title,
    String? note,
    String? audioUrl,
    String? type,
  }) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/events/$index');
    final body = <String, dynamic>{};
    if (at != null) body['at'] = at.toIso8601String();
    if (title != null) body['title'] = title;
    if (note != null) body['note'] = note;
    if (audioUrl != null) body['audio_url'] = audioUrl;
    if (type != null) body['type'] = type;
    final response = await http.patch(
      uri,
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Update event failed: ${response.statusCode} ${response.body}',
      );
    }
    return Item.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
