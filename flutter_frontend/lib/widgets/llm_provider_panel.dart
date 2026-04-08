import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';
import 'package:flutter/material.dart';

const _providers = [
  ('nim_api', 'NVIDIA NIM API'),
  ('self_hosted', 'Self-Hosted NIM'),
];

class LlmProviderPanel extends StatefulWidget {
  final String provider;
  final void Function(String) onChanged;
  final bool locked;

  const LlmProviderPanel({
    super.key,
    required this.provider,
    required this.onChanged,
    required this.locked,
  });

  @override
  State<LlmProviderPanel> createState() => _LlmProviderPanelState();
}

class _LlmProviderPanelState extends State<LlmProviderPanel> {
  late String _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.provider;
  }

  @override
  void didUpdateWidget(LlmProviderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _draft = widget.provider;
    }
  }

  bool get _isDirty => _draft != widget.provider;

  String get _currentLabel =>
      _providers.firstWhere((p) => p.$1 == widget.provider).$2;

  void _handleApply() {
    if (!_isDirty) return;
    // Dynatrace RUM (Classic) - not necessary for RUM on Grail
    // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions

    // final tapAction = Dynatrace().enterAction('Tap set LLM provider');
    // final subAction = tapAction.enterAction('Set LLM provider');
    widget.onChanged(_draft);
    // Dynatrace RUM (Classic) - not necessary for RUM on Grail
    // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions
    
    // subAction.leaveAction();
    // tapAction.leaveAction();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: UserInteractionWidget(
        customName: 'Toggle LLM provider panel',
        child: ExpansionTile(
        title: Row(
          children: [
            Text(
              'LLM PROVIDER',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '($_currentLabel)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          RadioGroup<String>(
            groupValue: _draft,
            onChanged: widget.locked
                ? (value) {}
                : (value) => setState(() { if (value != null) _draft = value; }),
            child: Column(
              children: _providers.map((p) {
                return Semantics(
                  label: 'Select ${p.$2}',
                  child: RadioListTile<String>(
                    title: Text(p.$2, style: const TextStyle(fontSize: 14)),
                    value: p.$1,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          if (widget.locked)
            Text(
              'Clear the conversation to change the LLM provider.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose which backend serves your requests.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
                ElevatedButton(
                  onPressed: _isDirty ? _handleApply : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066CC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
        ],
        ),
      ),
    );
  }
}
