import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import 'message_bubble.dart';

class ChatWindow extends StatefulWidget {
  final List<ChatMessage> messages;
  final bool isStreaming;

  const ChatWindow({
    super.key,
    required this.messages,
    required this.isStreaming,
  });

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(ChatWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length ||
        widget.messages.lastOrNull?.content != oldWidget.messages.lastOrNull?.content) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) {
      return const Center(
        child: Text(
          'Send a message to start chatting.',
          style: TextStyle(color: Colors.grey, fontSize: 15),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) {
        final reversedIndex = widget.messages.length - 1 - index;
        final msg = widget.messages[reversedIndex];
        final isLastAssistant = widget.isStreaming &&
            reversedIndex == widget.messages.length - 1 &&
            msg.role == 'assistant';
        return MessageBubble(
          role: msg.role,
          content: msg.content,
          isStreaming: isLastAssistant,
        );
      },
    );
  }
}
