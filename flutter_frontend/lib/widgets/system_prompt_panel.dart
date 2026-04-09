import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';
import 'package:flutter/material.dart';

class SystemPromptPanel extends StatefulWidget {
  final String systemPrompt;
  final void Function(String) onChanged;
  final bool locked;

  const SystemPromptPanel({
    super.key,
    required this.systemPrompt,
    required this.onChanged,
    required this.locked,
  });

  @override
  State<SystemPromptPanel> createState() => _SystemPromptPanelState();
}

class _SystemPromptPanelState extends State<SystemPromptPanel> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.systemPrompt);
  }

  @override
  void didUpdateWidget(SystemPromptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.systemPrompt != widget.systemPrompt &&
        _controller.text != widget.systemPrompt) {
      _controller.text = widget.systemPrompt;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isDirty => _controller.text.trim() != widget.systemPrompt.trim();

  void _handleSet() {
    if (!_isDirty) return;
    // Dynatrace RUM (Classic) - not necessary for RUM on Grail
    // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions

    // final tapAction = Dynatrace().enterAction('Tap set system prompt');
    // final subAction = tapAction.enterAction('Set system prompt');
    widget.onChanged(_controller.text);
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
        customName: 'Toggle system prompt panel',
        child: ExpansionTile(
        title: Text(
          'SYSTEM PROMPT',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: Colors.grey.shade600,
          ),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          UserInteractionWidget(
            customName: 'System prompt input field',
            child: TextField(
            controller: _controller,
            maxLines: 4,
            readOnly: widget.locked,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: "Describe the assistant's persona and behavior…",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(10),
              isDense: true,
              filled: widget.locked,
              fillColor: widget.locked ? const Color(0xFFF5F5F5) : null,
            ),
            style: TextStyle(
              fontSize: 14,
              color: widget.locked ? Colors.grey : null,
            ),
          ),
          ),
          const SizedBox(height: 6),
          if (widget.locked)
            Text(
              'Clear the conversation to change the system prompt.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Click Set to apply and refresh suggestions.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
                UserInteractionWidget(
                  customName: 'Set system prompt button',
                  child: ElevatedButton(
                    onPressed: _isDirty ? _handleSet : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0066CC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text('Set'),
                  ),
                ),
              ],
            ),
        ],
        ),
      ),
    );
  }
}
