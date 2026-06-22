import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
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

class _ChatScreenState extends State<ChatScreen> with RouteAware {
  @override
  void initState() {
    super.initState();
    // Reset conversation and load starters when screen first loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConfigProvider>().refreshChaosConfig();
      context.read<ChatProvider>().resetAndFetchStarters();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when returning to this screen from another route
    // Reset conversation and load new starters
    context.read<ConfigProvider>().refreshChaosConfig();
    context.read<ChatProvider>().resetAndFetchStarters();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final config = context.watch<ConfigProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text(
              'AI Chatbot',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            if (chat.model != null) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  chat.model!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ],
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
            isLoading: chat.isSuggestionsLoading,
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
