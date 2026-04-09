import 'package:flutter/material.dart';

import '../models/chaos_config.dart';
import '../providers/config_provider.dart';

/// Grid of chaos preset buttons.
class ChaosPresetButtons extends StatelessWidget {
  final ConfigProvider config;

  const ChaosPresetButtons({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chaosPresets.map((preset) {
            final isHealthy = preset.name == 'healthy';
            final isActive = _isPresetActive(preset.name, config.chaosConfig);
            
            return _PresetButton(
              preset: preset,
              isActive: isActive,
              isHealthy: isHealthy,
              onTap: () => config.applyChaosPreset(preset.name),
            );
          }).toList(),
        ),
      ],
    );
  }

  bool _isPresetActive(String presetName, ChaosConfig chaos) {
    // Simple heuristic: healthy if nothing active
    if (presetName == 'healthy') {
      return !chaos.isAnyActive;
    }
    // For other presets, do a rough check based on key characteristics
    switch (presetName) {
      case 'slow_llm':
        return chaos.llmDelayMs >= 5000;
      case 'flaky_network':
        return chaos.http500Rate >= 0.3;
      case 'rate_limited':
        return chaos.rateLimitEnabled;
      case 'degraded':
        return chaos.llmErrorRate >= 0.2 && chaos.fixedDelayMs >= 1000;
      default:
        return false;
    }
  }
}

class _PresetButton extends StatelessWidget {
  final ChaosPreset preset;
  final bool isActive;
  final bool isHealthy;
  final VoidCallback onTap;

  const _PresetButton({
    required this.preset,
    required this.isActive,
    required this.isHealthy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color fgColor;
    final Color borderColor;

    if (isActive && isHealthy) {
      bgColor = Colors.green[50]!;
      fgColor = Colors.green[800]!;
      borderColor = Colors.green[400]!;
    } else if (isActive) {
      bgColor = Colors.blue[50]!;
      fgColor = Colors.blue[800]!;
      borderColor = Colors.blue[400]!;
    } else {
      bgColor = Colors.grey[100]!;
      fgColor = Colors.grey[700]!;
      borderColor = Colors.grey[300]!;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isActive ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _capitalize(preset.name),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: fgColor,
                    ),
                  ),
                ),
                if (isActive)
                  Icon(Icons.check_circle, size: 18, color: fgColor),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              preset.description,
              style: TextStyle(
                fontSize: 12,
                color: fgColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) {
    return s.split('_').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }
}
