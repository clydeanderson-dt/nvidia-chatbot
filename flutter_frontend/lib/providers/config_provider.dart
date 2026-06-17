import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';
import '../models/chaos_config.dart';
import '../services/api_service.dart';

const _kSystemPromptKey = 'chatbot_system_prompt';
const _kProviderKey = 'chatbot_provider';
const _kDefaultSystemPrompt = 'You are a helpful, knowledgeable, and friendly AI assistant.';
const _kDefaultProvider = 'nim_api';

/// Provider for app and chaos configuration state.
///
/// App config (system prompt, provider) is persisted in SharedPreferences.
/// Chaos config is read-only and sourced from the backend (controlled by
/// DevCycle feature flags). It is refetched when the app resumes to stay
/// in sync with DevCycle changes.
class ConfigProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ApiService _api = ApiService();

  AppConfig _appConfig = const AppConfig();
  ChaosConfig _chaosConfig = const ChaosConfig();
  String _chaosVariation = 'unknown';
  bool _loading = false;
  String? _error;

  // Getters
  AppConfig get appConfig => _appConfig;
  ChaosConfig get chaosConfig => _chaosConfig;
  String get chaosVariation => _chaosVariation;
  bool get loading => _loading;
  String? get error => _error;
  bool get isAnyChaosActive => _chaosConfig.isAnyActive;

  // Convenience getters for chat
  String get systemPrompt => _appConfig.systemPrompt;
  String get llmProvider => _appConfig.provider;

  ConfigProvider() {
    loadConfig();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadConfig();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Load app config from SharedPreferences and chaos status from backend.
  Future<void> loadConfig() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final systemPrompt = prefs.getString(_kSystemPromptKey) ?? _kDefaultSystemPrompt;
      final provider = prefs.getString(_kProviderKey) ?? _kDefaultProvider;
      _appConfig = AppConfig(systemPrompt: systemPrompt, provider: provider);

      final status = await _api.getChaosStatus();
      _chaosConfig = status.config;
      _chaosVariation = status.preset ?? 'unknown';
    } catch (e) {
      debugPrint('Failed to load config: $e');
      _error = 'Failed to load configuration';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Refresh chaos status only (silent, no loading state).
  Future<void> refreshChaosConfig() async {
    try {
      final status = await _api.getChaosStatus();
      final variation = status.preset ?? 'unknown';
      if (_chaosConfig.toJson().toString() != status.config.toJson().toString() ||
          _chaosVariation != variation) {
        _chaosConfig = status.config;
        _chaosVariation = variation;
        notifyListeners();
      }
    } catch (e) {
      // Silent fail - don't spam logs on network errors
    }
  }

  // ── App Config Methods ─────────────────────────────────────────────────────

  /// Update app configuration (system prompt and/or provider) in local storage.
  Future<void> updateAppConfig({String? systemPrompt, String? provider}) async {
    if (systemPrompt == null && provider == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (systemPrompt != null) {
        await prefs.setString(_kSystemPromptKey, systemPrompt);
      }
      if (provider != null) {
        await prefs.setString(_kProviderKey, provider);
      }
      _appConfig = _appConfig.copyWith(
        systemPrompt: systemPrompt,
        provider: provider,
      );
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to save app config: $e');
      _error = 'Failed to save settings';
      notifyListeners();
      rethrow;
    }
  }

  /// Set system prompt (convenience method).
  Future<void> setSystemPrompt(String value) async {
    if (value.trim() == _appConfig.systemPrompt.trim()) return;
    await updateAppConfig(systemPrompt: value);
  }

  /// Set LLM provider (convenience method).
  Future<void> setLlmProvider(String value) async {
    if (value == _appConfig.provider) return;
    await updateAppConfig(provider: value);
  }

  /// Clear any error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
