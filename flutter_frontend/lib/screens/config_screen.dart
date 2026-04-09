import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/config_provider.dart';
import '../widgets/chaos_preset_buttons.dart';
import '../widgets/http_errors_section.dart';
import '../widgets/latency_injection_section.dart';
import '../widgets/llm_failures_section.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late TextEditingController _systemPromptController;
  String _draftProvider = 'nim_api';
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _systemPromptController = TextEditingController();
    // Refresh chaos config when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConfigProvider>().refreshChaosConfig();
    });
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    super.dispose();
  }

  void _syncFromConfig(ConfigProvider config) {
    if (_systemPromptController.text.isEmpty || !_isDirty) {
      _systemPromptController.text = config.systemPrompt;
      _draftProvider = config.llmProvider;
      _isDirty = false;
    }
  }

  void _checkDirty(ConfigProvider config) {
    final dirty = _systemPromptController.text.trim() != config.systemPrompt.trim() ||
        _draftProvider != config.llmProvider;
    if (dirty != _isDirty) {
      setState(() => _isDirty = dirty);
    }
  }

  Future<void> _saveAppSettings(ConfigProvider config) async {
    try {
      await config.updateAppConfig(
        systemPrompt: _systemPromptController.text.trim(),
        provider: _draftProvider,
      );
      setState(() => _isDirty = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigProvider>();
    
    // Sync draft state from config on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFromConfig(config);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Configuration',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: config.loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chaos Warning Banner
                  if (config.isAnyChaosActive)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[300]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange[800]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Chaos engineering is active. Some requests may fail or be delayed.',
                              style: TextStyle(color: Colors.orange[900]),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // App Settings Section
                  _SectionCard(
                    title: 'App Settings',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'System Prompt',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _systemPromptController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Enter the system prompt / persona...',
                          ),
                          onChanged: (_) => _checkDirty(config),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'LLM Provider',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        RadioGroup<String>(
                          groupValue: _draftProvider,
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _draftProvider = v);
                              _checkDirty(config);
                            }
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('NVIDIA NIM API', style: TextStyle(fontSize: 14)),
                                  value: 'nim_api',
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('Self-Hosted NIM', style: TextStyle(fontSize: 14)),
                                  value: 'self_hosted',
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isDirty ? () => _saveAppSettings(config) : null,
                            child: const Text('Save App Settings'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Chaos Presets Section
                  _SectionCard(
                    title: 'Chaos Presets',
                    child: ChaosPresetButtons(config: config),
                  ),
                  const SizedBox(height: 16),

                  // LLM Failures Section
                  _SectionCard(
                    title: 'LLM Failures',
                    child: LlmFailuresSection(config: config),
                  ),
                  const SizedBox(height: 16),

                  // Latency Injection Section
                  _SectionCard(
                    title: 'Latency Injection',
                    child: LatencyInjectionSection(config: config),
                  ),
                  const SizedBox(height: 16),

                  // HTTP Errors Section
                  _SectionCard(
                    title: 'HTTP Error Injection',
                    child: HttpErrorsSection(config: config),
                  ),
                  const SizedBox(height: 16),

                  // Current Configuration Display
                  _SectionCard(
                    title: 'Current Configuration',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert({
                          'app_config': config.appConfig.toJson(),
                          'chaos_config': config.chaosConfig.toJson(),
                        }),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
