import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin client for the Argosy /api/v1 surface — only what the player spike needs.
/// Mirrors proto/openapi/argosy.yaml. Throws a String on non-2xx for easy display.
class ApiClient {
  String baseUrl;
  String? token;
  ApiClient(this.baseUrl);

  Map<String, String> get authHeaders =>
      token == null ? {} : {'Authorization': 'Bearer $token'};

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Future<Map<String, dynamic>> login(String user, String pass) async {
    final r = await http.post(_u('/api/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': user, 'password': pass}));
    if (r.statusCode != 200) throw 'login ${r.statusCode}: ${r.body}';
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Registers this device for [userId] and stores the returned bearer token.
  Future<void> registerDevice(
      String user, String pass, String userId, String deviceName) async {
    final r = await http.post(_u('/api/v1/auth/devices'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': user,
          'password': pass,
          'userId': userId,
          'deviceName': deviceName,
          'platform': 'phone',
        }));
    if (r.statusCode != 201) throw 'device reg ${r.statusCode}: ${r.body}';
    token = (jsonDecode(r.body) as Map<String, dynamic>)['token'] as String;
  }

  Future<Map<String, dynamic>> me() async {
    final r = await http.get(_u('/api/v1/auth/me'), headers: authHeaders);
    if (r.statusCode != 200) throw 'me ${r.statusCode}';
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> libraries() async {
    final r = await http.get(_u('/api/v1/libraries'), headers: authHeaders);
    if (r.statusCode != 200) throw 'libraries ${r.statusCode}';
    return jsonDecode(r.body) as List<dynamic>;
  }

  Future<List<dynamic>> movies(String libraryId) async {
    final r = await http.get(
        _u('/api/v1/libraries/$libraryId/movies', {'limit': '200'}),
        headers: authHeaders);
    if (r.statusCode != 200) throw 'movies ${r.statusCode}';
    return (jsonDecode(r.body) as Map<String, dynamic>)['items'] as List<dynamic>;
  }

  Future<List<dynamic>> recent() async {
    final r =
        await http.get(_u('/api/v1/recent', {'limit': '50'}), headers: authHeaders);
    if (r.statusCode != 200) throw 'recent ${r.statusCode}';
    return jsonDecode(r.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> playback(String itemId) async {
    final r =
        await http.get(_u('/api/v1/items/$itemId/playback'), headers: authHeaders);
    if (r.statusCode != 200) throw 'playback ${r.statusCode}';
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> subtitles(String itemId) async {
    final r =
        await http.get(_u('/api/v1/items/$itemId/subtitles'), headers: authHeaders);
    if (r.statusCode != 200) return [];
    return jsonDecode(r.body) as List<dynamic>;
  }

  /// POST .../transcode → 202 TranscodeSession. Advertises HEVC capability.
  Future<Map<String, dynamic>> startTranscode(String itemId,
      {double startAt = 0, bool hevc = true}) async {
    final r = await http.post(_u('/api/v1/items/$itemId/transcode'),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'startAt': startAt, 'hevc': hevc}));
    if (r.statusCode != 202) throw 'transcode ${r.statusCode}: ${r.body}';
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> stopTranscode(String sessionId) async {
    await http.delete(_u('/api/v1/transcode/$sessionId'), headers: authHeaders);
  }

  Future<Map<String, dynamic>?> progress(String itemId) async {
    final r =
        await http.get(_u('/api/v1/items/$itemId/progress'), headers: authHeaders);
    if (r.statusCode != 200) return null;
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> reportProgress(String itemId, double pos, double? dur) async {
    await http.put(_u('/api/v1/items/$itemId/progress'),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode(
            {'positionSeconds': pos, if (dur != null) 'durationSeconds': dur}));
  }

  // --- URL builders ---------------------------------------------------------
  // Stream + subtitles accept ?token=; HLS transcode artifacts do NOT (header only).
  String streamUrl(String itemId) =>
      '$baseUrl/api/v1/items/$itemId/stream?token=$token';
  String subtitleUrl(String itemId, String trackId) =>
      '$baseUrl/api/v1/items/$itemId/subtitles/$trackId?token=$token';
  String absolute(String relPath) =>
      relPath.startsWith('http') ? relPath : '$baseUrl$relPath';
}
