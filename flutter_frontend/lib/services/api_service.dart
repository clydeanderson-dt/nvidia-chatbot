import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';

import '../config.dart';
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
      throw Exception('Server error: ${response.statusCode}');
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
}
