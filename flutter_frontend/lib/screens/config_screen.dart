import 'dart:convert';

import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/config_provider.dart';

const _devcycleFeatureUrl =
    'https://app.devcycle.com/o/org_SeGjnZQOwOYgQWYZ/p/nvidia-chatbot/features/chaos-preset';

String _pct(double n) => '${(n * 100).toStringAsFixed(0)}%';
String _ms(int n) => '${n}ms';
String _bool(bool b) => b ? 'Enabled' : 'Disabled';

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

  Future<void> _openDevCycle() async {
    final uri = Uri.parse(_devcycleFeatureUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open DevCycle dashboard')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFromConfig(config);
    });

    final variation = config.chaosVariation;
    final variationLabel = (variation.isNotEmpty && variation != 'unknown') ? variation : '—';
    final chaosConfig = config.chaosConfig;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Configuration',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        leading: UserInteractionWidget(
          customName: 'Back button',
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: config.loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (config.isAnyChaosActive)
                    _ChaosActiveBanner(variationLabel: variationLabel),

                  _SectionCard(
                    title: 'App Settings',
                    child: _buildAppSettings(config),
                  ),
                  const SizedBox(height: 16),

                  _DevCycleBanner(
                    variationLabel: variationLabel,
                    onOpenDashboard: _openDevCycle,
                  ),
                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'LLM Failures',
                    child: Column(
                      children: [
                        _ReadOnlyRow(label: 'LLM Delay', value: _ms(chaosConfig.llmDelayMs)),
                        _ReadOnlyRow(label: 'LLM Error Rate', value: _pct(chaosConfig.llmErrorRate)),
                        _ReadOnlyRow(label: 'Empty Response Rate', value: _pct(chaosConfig.emptyResponseRate)),
                        _ReadOnlyRow(label: 'Malformed Response Rate', value: _pct(chaosConfig.malformedResponseRate)),
                        _ReadOnlyRow(label: 'Rate Limiting', value: _bool(chaosConfig.rateLimitEnabled)),
                        _ReadOnlyRow(label: 'Hallucination Markers', value: _bool(chaosConfig.hallucinationEnabled)),
                        _ReadOnlyRow(label: 'Token Limit Errors', value: _bool(chaosConfig.tokenLimitErrorEnabled)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'Latency Injection',
                    child: Column(
                      children: [
                        _ReadOnlyRow(label: 'Fixed Delay', value: _ms(chaosConfig.fixedDelayMs)),
                        _ReadOnlyRow(
                          label: 'Random Delay',
                          value: '${_ms(chaosConfig.randomDelayMinMs)} – ${_ms(chaosConfig.randomDelayMaxMs)}',
                        ),
                        _ReadOnlyRow(
                          label: 'Spike Delay',
                          value: '${_ms(chaosConfig.spikeDelayMs)} @ ${_pct(chaosConfig.spikeProbability)} probability',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'HTTP Error Injection',
                    child: Column(
                      children: [
                        _ReadOnlyRow(label: 'HTTP 500 Rate', value: _pct(chaosConfig.http500Rate)),
                        _ReadOnlyRow(label: 'HTTP 503 Rate', value: _pct(chaosConfig.http503Rate)),
                        _ReadOnlyRow(label: 'Session Error Rate', value: _pct(chaosConfig.sessionErrorRate)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

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
                          'app': config.appConfig.toJson(),
                          'chaos': chaosConfig.toJson(),
                          'variation': variation,
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

  Widget _buildAppSettings(ConfigProvider config) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('System Prompt', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        UserInteractionWidget(
          customName: 'System prompt config field',
          child: TextField(
            controller: _systemPromptController,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: "Describe the assistant's persona and behavior…",
            ),
            onChanged: (_) => _checkDirty(config),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Defines the AI assistant's personality and behavior.",
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
        const SizedBox(height: 16),
        const Text('LLM Provider', style: TextStyle(fontWeight: FontWeight.w500)),
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
                child: UserInteractionWidget(
                  customName: 'Select NVIDIA NIM API',
                  child: RadioListTile<String>(
                    title: const Text('NVIDIA NIM API', style: TextStyle(fontSize: 14)),
                    value: 'nim_api',
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Expanded(
                child: UserInteractionWidget(
                  customName: 'Select self-hosted NIM',
                  child: RadioListTile<String>(
                    title: const Text('Self-Hosted NIM', style: TextStyle(fontSize: 14)),
                    value: 'self_hosted',
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose which LLM backend serves requests.',
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: UserInteractionWidget(
            customName: 'Save app settings button',
            child: ElevatedButton(
              onPressed: _isDirty ? () => _saveAppSettings(config) : null,
              child: const Text('Save App Settings'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChaosActiveBanner extends StatelessWidget {
  final String variationLabel;
  const _ChaosActiveBanner({required this.variationLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: RichText(
              text: TextSpan(
                style: TextStyle(color: Colors.orange[900], fontSize: 14),
                children: [
                  const TextSpan(text: '⚠️ Chaos mode is active — variation: '),
                  TextSpan(
                    text: variationLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' — failures may be injected into requests.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DevCycleBanner extends StatelessWidget {
  final String variationLabel;
  final VoidCallback onOpenDashboard;

  const _DevCycleBanner({
    required this.variationLabel,
    required this.onOpenDashboard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC4B5FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🚩 Controlled by DevCycle Feature Flags',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Chaos scenarios are managed via DevCycle. ',
                style: TextStyle(fontSize: 13),
              ),
              UserInteractionWidget(
                customName: 'Open DevCycle dashboard',
                child: InkWell(
                  onTap: onOpenDashboard,
                  child: const Text(
                    'View in DevCycle dashboard →',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6D28D9),
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Active variation',
                style: TextStyle(fontSize: 13, color: Colors.grey[800]),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6D28D9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  variationLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
