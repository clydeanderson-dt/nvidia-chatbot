import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_request.dart';
import '../models/starter_request.dart';
import '../services/api_service.dart';
import 'config_provider.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final String sessionId = const Uuid().v4();

  List<ChatMessage> messages = [];
  bool isStreaming = false;
  List<String> suggestions = [];

  // Reference to ConfigProvider for system prompt and LLM provider
  ConfigProvider? _configProvider;

  // Convenience getters that delegate to ConfigProvider
  String get systemPrompt => _configProvider?.systemPrompt ?? 
      'You are a helpful, knowledgeable, and friendly AI assistant.';
  String get llmProvider => _configProvider?.llmProvider ?? 'nim_api';

  bool get isLocked => messages.isNotEmpty;

  ChatProvider() {
    // Don't fetch starters here - wait for ConfigProvider to be set
  }

  /// Called by MultiProvider to inject ConfigProvider dependency.
  void setConfigProvider(ConfigProvider provider) {
    if (_configProvider == provider) return;
    _configProvider = provider;
    // Fetch starters once we have config (and if messages are empty)
    if (messages.isEmpty && suggestions.isEmpty) {
      fetchStarterSuggestions();
    }
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
      // Refresh chaos config after receiving response
      _configProvider?.refreshChaosConfig();
    } catch (e) {
      // Extract error message from exception if available
      String errorMsg = 'Sorry, something went wrong. Please try again.';
      if (e is Exception) {
        final match = RegExp(r'Exception: (.+)').firstMatch(e.toString());
        if (match != null) {
          errorMsg = match.group(1) ?? errorMsg;
        }
      }
      messages.last.content = errorMsg;
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
    // Refresh chaos config after clearing
    _configProvider?.refreshChaosConfig();
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
