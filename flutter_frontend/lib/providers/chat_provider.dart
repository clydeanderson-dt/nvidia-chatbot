import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_request.dart';
import '../models/starter_request.dart';
import '../services/api_service.dart';

import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final String sessionId = const Uuid().v4();

  List<ChatMessage> messages = [];
  bool isStreaming = false;
  List<String> suggestions = [];
  String systemPrompt = 'You are a helpful, knowledgeable, and friendly AI assistant.';
  String llmProvider = 'nim_api';

  bool get isLocked => messages.isNotEmpty;

  ChatProvider() {
    fetchStarterSuggestions();
  }

  Future<void> sendMessage(String text) async {
    
    
    final trimmed = text.trim();
    if (trimmed.isEmpty || isStreaming) return;

    suggestions = [];
    messages.add(ChatMessage(role: 'user', content: trimmed));
    messages.add(ChatMessage(role: 'assistant', content: ''));
    isStreaming = true;
    notifyListeners();

    try {
      final response = await _api.postChat(ChatRequest(
        sessionId: sessionId,
        message: trimmed,
        systemPrompt: systemPrompt,
        provider: llmProvider,
      ));
      messages.last.content = response.reply;
      suggestions = response.suggestions;
    } catch (e) {
      messages.last.content = 'Sorry, something went wrong. Please try again.';
      suggestions = [];
    } finally {
      isStreaming = false;
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    try {
      await _api.deleteSession(sessionId);
    } catch (e) {
      debugPrint('Failed to clear server session: $e');
    }
    messages = [];
    suggestions = [];
    notifyListeners();
    fetchStarterSuggestions();
  }

  void setSystemPrompt(String value) {
    if (isLocked || value.trim() == systemPrompt.trim()) return;
    systemPrompt = value;
    notifyListeners();
    if (messages.isEmpty) {
      fetchStarterSuggestions();
    }
  }

  void setLlmProvider(String value) {
    if (isLocked || value == llmProvider) return;
    llmProvider = value;
    notifyListeners();
  }

  Future<void> fetchStarterSuggestions() async {
    debugPrint('fetchStarterSuggestions: entering Dynatrace action');
    // Dynatrace RUM (Classic) - not necessary for RUM on Grail
    // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions

    // DynatraceRootAction webAction = Dynatrace().enterAction('Generate initial suggestions');

    try {
      final response = await _api.postStarters(StarterRequest(
        systemPrompt: systemPrompt,
        provider: llmProvider,
      ));
      suggestions = response.suggestions;
      notifyListeners();
    } catch (e) {
      // Starter suggestions are best-effort.
    }
    finally {
        // Dynatrace RUM (Classic) - not necessary for RUM on Grail
        // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions
        
        // webAction.leaveAction();
    }
  }
}
