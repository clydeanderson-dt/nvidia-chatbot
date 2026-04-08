import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';
import 'package:flutter/material.dart';

class SuggestionChips extends StatelessWidget {
  final List<String> suggestions;
  final Future<void> Function(String) onSelect;

  const SuggestionChips({
    super.key,
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: suggestions.map((s) {
          return UserInteractionWidget(
            customName: 'Suggestion chip',
            child: OutlinedButton(
            onPressed: () async {
              // Dynatrace RUM (Classic) - not necessary for RUM on Grail
              // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions

              // final tapAction = Dynatrace().enterAction('Tap suggestion chip');
              // final subAction = tapAction.enterAction('Send prompt');
              try {
                await onSelect(s);
              } finally {
                // Dynatrace RUM (Classic) - not necessary for RUM on Grail
                // https://pub.dev/packages/dynatrace_flutter_plugin#create-custom-actions
                
                // subAction.leaveAction();
                // tapAction.leaveAction();
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0066CC),
              side: const BorderSide(color: Color(0xFF0066CC), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              textStyle: const TextStyle(fontSize: 14),
            ),
            child: Text(s, textAlign: TextAlign.left),
            ),
          );
        }).toList(),
      ),
    );
  }
}
