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
  bool isSuggestionsLoading = false;

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
      
      // Set loading state and fetch suggestions
      isSuggestionsLoading = true;
      notifyListeners();
      
      suggestions = response.suggestions;
      isSuggestionsLoading = false;
      
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

  /// Reset conversation and fetch new starter suggestions.
  /// This clears local state and reloads starters without deleting the server session
  /// unless there are messages to clear.
  Future<void> resetAndFetchStarters() async {
    if (messages.isNotEmpty) {
      // If there's conversation history, clear it from server
      await clearHistory();
    } else {
      // Otherwise just fetch new starters (e.g., if config changed)
      await fetchStarterSuggestions();
    }
  }

  Future<void> fetchStarterSuggestions() async {
    debugPrint('fetchStarterSuggestions: entering Dynatrace action');
    // Dynatrace RUM (Classic) - not necessary for RUM on Grail
    // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions

    // DynatraceRootAction webAction = Dynatrace().enterAction('Generate initial suggestions');

    isSuggestionsLoading = true;
    notifyListeners();
    
    try {
      final response = await _api.postStarters(StarterRequest(
        systemPrompt: systemPrompt,
        provider: llmProvider,
        sessionId: sessionId,
      ));
      suggestions = response.suggestions;
    } catch (e) {
      // Starter suggestions are best-effort.
    }
    finally {
        isSuggestionsLoading = false;
        notifyListeners();
        
        // Dynatrace RUM (Classic) - not necessary for RUM on Grail
        // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions
        
        // webAction.leaveAction();
    }
  }
}
