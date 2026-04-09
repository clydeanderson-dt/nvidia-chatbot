import 'package:flutter/material.dart';

import '../providers/config_provider.dart';

/// Section for LLM failure injection controls.
class LlmFailuresSection extends StatelessWidget {
  final ConfigProvider config;

  const LlmFailuresSection({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final chaos = config.chaosConfig;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LLM Delay
        _SliderField(
          label: 'LLM Delay',
          value: chaos.llmDelayMs.toDouble(),
          min: 0,
          max: 10000,
          divisions: 100,
          suffix: 'ms',
          hint: 'Delay before LLM responds',
          onChanged: (v) => config.updateChaosConfig({'llm_delay_ms': v.toInt()}),
        ),
        const SizedBox(height: 16),

        // LLM Error Rate
        _SliderField(
          label: 'LLM Error Rate',
          value: chaos.llmErrorRate * 100,
          min: 0,
          max: 100,
          divisions: 100,
          suffix: '%',
          hint: 'Probability of LLM call failure',
          onChanged: (v) => config.updateChaosConfig({'llm_error_rate': v / 100}),
        ),
        const SizedBox(height: 16),

        // Empty Response Rate
        _SliderField(
          label: 'Empty Response Rate',
          value: chaos.emptyResponseRate * 100,
          min: 0,
          max: 100,
          divisions: 100,
          suffix: '%',
          hint: 'Probability of empty LLM response',
          onChanged: (v) => config.updateChaosConfig({'empty_response_rate': v / 100}),
        ),
        const SizedBox(height: 16),

        // Rate Limit Toggle
        _SwitchField(
          label: 'Rate Limiting',
          value: chaos.rateLimitEnabled,
          hint: 'Return 429 after ${chaos.rateLimitAfterN} requests',
          onChanged: (v) => config.updateChaosConfig({'rate_limit_enabled': v}),
        ),
        if (chaos.rateLimitEnabled) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                const Text('Limit after ', style: TextStyle(fontSize: 14)),
                SizedBox(
                  width: 60,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: chaos.rateLimitAfterN.toString()),
                    onSubmitted: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n > 0) {
                        config.updateChaosConfig({'rate_limit_after_n': n});
                      }
                    },
                  ),
                ),
                const Text(' requests', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Hallucination Toggle
        _SwitchField(
          label: 'Hallucination',
          value: chaos.hallucinationEnabled,
          hint: 'Inject hallucination marker text',
          onChanged: (v) => config.updateChaosConfig({'hallucination_enabled': v}),
        ),
        const SizedBox(height: 16),

        // Token Limit Error Toggle
        _SwitchField(
          label: 'Token Limit Error',
          value: chaos.tokenLimitErrorEnabled,
          hint: 'Simulate token/context limit errors',
          onChanged: (v) => config.updateChaosConfig({'token_limit_error_enabled': v}),
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
        Row(
          children: [
            Expanded(
              child: Text(
                '$label: ${value.toInt()}$suffix',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
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

class _SwitchField extends StatelessWidget {
  final String label;
  final bool value;
  final String? hint;
  final ValueChanged<bool> onChanged;

  const _SwitchField({
    required this.label,
    required this.value,
    this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
            ),
          ],
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
