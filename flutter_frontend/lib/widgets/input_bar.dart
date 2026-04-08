import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';
import 'package:flutter/material.dart';

class InputBar extends StatefulWidget {
  final Future<void> Function(String) onSend;
  final bool isStreaming;

  const InputBar({
    super.key,
    required this.onSend,
    required this.isStreaming,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();

  Future<void> _handleSend(String rootActionName) async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isStreaming) return;
    _controller.clear();
    // Dynatrace RUM (Classic) - not necessary for RUM on Grail
    // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions

    // final tapAction = Dynatrace().enterAction(rootActionName);
    // final subAction = tapAction.enterAction('Send prompt');
    try {
      await widget.onSend(text);
    } finally {
      // Dynatrace RUM (Classic) - not necessary for RUM on Grail
      // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions
      
      // subAction.leaveAction();
      // tapAction.leaveAction();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: UserInteractionWidget(
                customName: 'Message input field',
                child: TextField(
                controller: _controller,
                maxLines: 5,
                minLines: 1,
                enabled: !widget.isStreaming,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend('Submit message via keyboard'),
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFF0066CC)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 15),
              ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: widget.isStreaming ? null : () => _handleSend('Tap send button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066CC),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(widget.isStreaming ? '…' : 'Send'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
