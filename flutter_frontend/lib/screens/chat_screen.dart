import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../providers/config_provider.dart';
import '../widgets/chaos_banner.dart';
import '../widgets/chat_window.dart';
import '../widgets/input_bar.dart';
import '../widgets/suggestion_chips.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh chaos config when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConfigProvider>().refreshChaosConfig();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final config = context.watch<ConfigProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI Chatbot',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          UserInteractionWidget(
            customName: 'Settings button',
            child: IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () => Navigator.pushNamed(context, '/config'),
            ),
          ),
          UserInteractionWidget(
            customName: 'Clear conversation button',
            child: TextButton(
            onPressed: () async {
              // Dynatrace RUM (Classic) - not necessary for RUM on Grail
              // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions

              // final tapAction = Dynatrace().enterAction('Tap clear button');
              // final subAction = tapAction.enterAction('Clear history');
              try {
                await chat.clearHistory();
              } finally {
                // Dynatrace RUM (Classic) - not necessary for RUM on Grail
                // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions
                
                // subAction.leaveAction();
                // tapAction.leaveAction();
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: const Text('Clear'),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          ChaosBanner(
            visible: config.isAnyChaosActive,
            onTap: () => Navigator.pushNamed(context, '/config'),
          ),
          Expanded(
            child: ChatWindow(
              messages: chat.messages,
              isStreaming: chat.isStreaming,
            ),
          ),
          SuggestionChips(
            suggestions: chat.suggestions,
            onSelect: chat.sendMessage,
          ),
          InputBar(
            onSend: chat.sendMessage,
            isStreaming: chat.isStreaming,
          ),
        ],
      ),
    );
  }
}
