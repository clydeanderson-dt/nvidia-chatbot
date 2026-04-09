import 'package:dynatrace_flutter_plugin/dynatrace_flutter_plugin.dart';
import 'package:flutter/material.dart';

import '../providers/config_provider.dart';

/// Section for HTTP error injection controls.
class HttpErrorsSection extends StatelessWidget {
  final ConfigProvider config;

  const HttpErrorsSection({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final chaos = config.chaosConfig;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // HTTP 500 Rate
        UserInteractionWidget(
          customName: 'HTTP 500 rate slider',
          child: _SliderField(
            label: 'HTTP 500 Rate',
            value: chaos.http500Rate * 100,
            min: 0,
            max: 100,
            divisions: 100,
            suffix: '%',
            hint: 'Probability of HTTP 500 Internal Server Error',
            onChanged: (v) => config.updateChaosConfig({'http_500_rate': v / 100}),
          ),
        ),
        const SizedBox(height: 16),

        // HTTP 503 Rate
        UserInteractionWidget(
          customName: 'HTTP 503 rate slider',
          child: _SliderField(
            label: 'HTTP 503 Rate',
            value: chaos.http503Rate * 100,
            min: 0,
            max: 100,
            divisions: 100,
            suffix: '%',
            hint: 'Probability of HTTP 503 Service Unavailable',
            onChanged: (v) => config.updateChaosConfig({'http_503_rate': v / 100}),
          ),
        ),
        const SizedBox(height: 16),

        // Session Error Rate
        UserInteractionWidget(
          customName: 'Session error rate slider',
          child: _SliderField(
            label: 'Session Error Rate',
            value: chaos.sessionErrorRate * 100,
            min: 0,
            max: 100,
            divisions: 100,
            suffix: '%',
            hint: 'Probability of session-related errors',
            onChanged: (v) => config.updateChaosConfig({'session_error_rate': v / 100}),
          ),
        ),
      ],
    );
  }
}

class _SliderField extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String suffix;
  final String? hint;
  final ValueChanged<double> onChanged;

  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.suffix,
    this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${value.toInt()}$suffix',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        if (hint != null)
          Text(
            hint!,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
      ],
    );
  }
}
