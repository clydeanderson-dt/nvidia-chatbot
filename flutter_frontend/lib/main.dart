import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/chat_provider.dart';
import 'providers/config_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/config_screen.dart';

import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';

void main() => Dynatrace().start(MainApp());

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
        ChangeNotifierProxyProvider<ConfigProvider, ChatProvider>(
          create: (_) => ChatProvider(),
          update: (_, configProvider, chatProvider) {
            chatProvider?.setConfigProvider(configProvider);
            return chatProvider ?? ChatProvider();
          },
        ),
      ],
      child: MaterialApp(
        title: 'AI Chatbot',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF0066CC),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0066CC),
            foregroundColor: Color.fromRGBO(255, 255, 255, 1),
          ),
        ),
        // navigatorObservers: [
        //   DynatraceNavigationObserver(), // https://pub.dev/packages/dynatrace_flutter_plugin#navigation-observer
        // ],
        initialRoute: '/',
        routes: {
          '/': (context) => const ChatScreen(),
          '/config': (context) => const ConfigScreen(),
        },
      ),
    );
  }
}
