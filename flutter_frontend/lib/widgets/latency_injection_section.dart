import 'package:flutter/material.dart';

import '../providers/config_provider.dart';

/// Section for latency injection controls.
class LatencyInjectionSection extends StatelessWidget {
  final ConfigProvider config;

  const LatencyInjectionSection({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final chaos = config.chaosConfig;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed Delay
        _SliderField(
          label: 'Fixed Delay',
          value: chaos.fixedDelayMs.toDouble(),
          min: 0,
          max: 5000,
          divisions: 50,
          suffix: 'ms',
          hint: 'Fixed delay added to all responses',
          onChanged: (v) => config.updateChaosConfig({'fixed_delay_ms': v.toInt()}),
        ),
        const SizedBox(height: 20),

        // Random Delay Range
        const Text(
          'Random Delay Range',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: 'Min (ms)',
                value: chaos.randomDelayMinMs,
                onChanged: (v) => config.updateChaosConfig({'random_delay_min_ms': v}),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _NumberField(
                label: 'Max (ms)',
                value: chaos.randomDelayMaxMs,
                onChanged: (v) => config.updateChaosConfig({'random_delay_max_ms': v}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Random delay between min and max added to each request',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 20),

        // Spike Delay
        const Text(
          'Spike Delay',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: 'Spike (ms)',
                value: chaos.spikeDelayMs,
                onChanged: (v) => config.updateChaosConfig({'spike_delay_ms': v}),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Probability: ${(chaos.spikeProbability * 100).toInt()}%',
                    style: const TextStyle(fontSize: 14),
                  ),
                  Slider(
                    value: chaos.spikeProbability * 100,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    onChanged: (v) => config.updateChaosConfig({'spike_probability': v / 100}),
                  ),
                ],
              ),
            ),
          ],
        ),
        Text(
          'Occasional large delay spikes',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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

class _NumberField extends StatefulWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value.toString() != _controller.text) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (v) {
        final n = int.tryParse(v);
        if (n != null && n >= 0) {
          widget.onChanged(n);
        }
      },
    );
  }
}
