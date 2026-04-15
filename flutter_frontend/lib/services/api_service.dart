import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';

import '../config.dart';
import '../models/chaos_config.dart';
import '../models/chat_request.dart';
import '../models/chat_response.dart';
import '../models/starter_request.dart';
import '../models/starter_response.dart';

class ApiService {
  static final _headers = {'Content-Type': 'application/json'};
  final http.Client _client = Dynatrace().createHttpClient();

  Future<ChatResponse> postChat(ChatRequest request) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/chat'),
      headers: _headers,
      body: jsonEncode(request.toJson()),
    );
    if (response.statusCode != 200) {
      // Try to parse error detail from response
      String errorMsg = 'Server error: ${response.statusCode}';
      try {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        if (errorData.containsKey('detail')) {
          errorMsg = errorData['detail'] as String;
        }
      } catch (_) {
        // If parsing fails, use default message
      }
      throw Exception(errorMsg);
    }
    return ChatResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<StarterResponse> postStarters(StarterRequest request) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/chat/starters'),
      headers: _headers,
      body: jsonEncode(request.toJson()),
    );
    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }
    return StarterResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteSession(String sessionId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/chat/${Uri.encodeComponent(sessionId)}'),
    );
    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  // ── Chaos Config API ─────────────────────────────────────────────────────────

  Future<ChaosConfig> getChaosConfig() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/chaos'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }
    return ChaosConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ChaosConfig> patchChaosConfig(Map<String, dynamic> updates) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/chaos'),
      headers: _headers,
      body: jsonEncode(updates),
    );
    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }
    return ChaosConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ChaosConfig> resetChaosConfig() async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/chaos/reset'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }
    return ChaosConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ChaosConfig> applyChaosPreset(String presetName) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/chaos/preset/${Uri.encodeComponent(presetName)}'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }
    return ChaosConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
