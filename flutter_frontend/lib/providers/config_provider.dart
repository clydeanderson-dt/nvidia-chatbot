import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/app_config.dart';
import '../models/chaos_config.dart';
import '../services/api_service.dart';

/// Provider for app and chaos configuration state.
/// 
/// Fetches configuration from the backend on init and provides methods
/// to update settings. All state is in-memory only (no persistence).
/// 
/// Chaos config is polled every 5 seconds and refetched when the app resumes
/// to stay in sync with changes made from other frontends.
class ConfigProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ApiService _api = ApiService();

  AppConfig _appConfig = const AppConfig();
  ChaosConfig _chaosConfig = const ChaosConfig();
  bool _loading = false;
  String? _error;
  Timer? _pollTimer;

  // Getters
  AppConfig get appConfig => _appConfig;
  ChaosConfig get chaosConfig => _chaosConfig;
  bool get loading => _loading;
  String? get error => _error;
  bool get isAnyChaosActive => _chaosConfig.isAnyActive;

  // Convenience getters for chat
  String get systemPrompt => _appConfig.systemPrompt;
  String get llmProvider => _appConfig.provider;

  ConfigProvider() {
    loadConfig();
    // Add app lifecycle observer for refetch on resume
    WidgetsBinding.instance.addObserver(this);
    // Poll chaos config every 5 seconds to sync across frontends
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollChaosConfig();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refetch config when app comes to foreground
      loadConfig();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Load both app and chaos config from backend.
  Future<void> loadConfig() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _api.getAppConfig(),
        _api.getChaosConfig(),
      ]);
      _appConfig = results[0] as AppConfig;
      _chaosConfig = results[1] as ChaosConfig;
    } catch (e) {
      debugPrint('Failed to load config: $e');
      _error = 'Failed to load configuration';
      // Keep defaults on error
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Poll chaos config only (silent, no loading state).
  /// Used by periodic timer to sync with changes from other frontends.
  Future<void> _pollChaosConfig() async {
    try {
      final config = await _api.getChaosConfig();
      if (_chaosConfig != config) {
        _chaosConfig = config;
        notifyListeners();
      }
    } catch (e) {
      // Silent fail - don't spam logs on network errors during polling
    }
  }

  // ── App Config Methods ─────────────────────────────────────────────────────

  /// Update app configuration (system prompt and/or provider).
  Future<void> updateAppConfig({String? systemPrompt, String? provider}) async {
    final updates = <String, dynamic>{};
    if (systemPrompt != null) updates['system_prompt'] = systemPrompt;
    if (provider != null) updates['provider'] = provider;
    
    if (updates.isEmpty) return;

    try {
      _appConfig = await _api.patchAppConfig(updates);
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to update app config: $e');
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

  // ── Chaos Config Methods ───────────────────────────────────────────────────

  /// Update chaos configuration (partial update).
  Future<void> updateChaosConfig(Map<String, dynamic> updates) async {
    if (updates.isEmpty) return;

    try {
      _chaosConfig = await _api.patchChaosConfig(updates);
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to update chaos config: $e');
      _error = 'Failed to update chaos settings';
      notifyListeners();
      rethrow;
    }
  }

  /// Reset all chaos settings to defaults.
  Future<void> resetChaosConfig() async {
    try {
      _chaosConfig = await _api.resetChaosConfig();
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to reset chaos config: $e');
      _error = 'Failed to reset chaos settings';
      notifyListeners();
      rethrow;
    }
  }

  /// Apply a named chaos preset.
  Future<void> applyChaosPreset(String presetName) async {
    try {
      _chaosConfig = await _api.applyChaosPreset(presetName);
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to apply preset $presetName: $e');
      _error = 'Failed to apply preset';
      notifyListeners();
      rethrow;
    }
  }

  /// Clear any error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
