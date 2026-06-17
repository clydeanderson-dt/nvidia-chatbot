/// Chaos configuration model for fault injection settings.
///
/// Values are sourced from DevCycle feature flags via the backend.
/// This model is read-only on the client; mutations happen in DevCycle.
class ChaosConfig {
  // LLM-specific failures
  final int llmDelayMs;
  final double llmErrorRate;
  final bool rateLimitEnabled;
  final double malformedResponseRate;
  final double emptyResponseRate;
  final bool hallucinationEnabled;
  final bool tokenLimitErrorEnabled;

  // Latency injection
  final int fixedDelayMs;
  final int randomDelayMinMs;
  final int randomDelayMaxMs;
  final int spikeDelayMs;
  final double spikeProbability;

  // HTTP error injection
  final double http500Rate;
  final double http503Rate;
  final double sessionErrorRate;

  const ChaosConfig({
    this.llmDelayMs = 0,
    this.llmErrorRate = 0.0,
    this.rateLimitEnabled = false,
    this.malformedResponseRate = 0.0,
    this.emptyResponseRate = 0.0,
    this.hallucinationEnabled = false,
    this.tokenLimitErrorEnabled = false,
    this.fixedDelayMs = 0,
    this.randomDelayMinMs = 0,
    this.randomDelayMaxMs = 0,
    this.spikeDelayMs = 0,
    this.spikeProbability = 0.0,
    this.http500Rate = 0.0,
    this.http503Rate = 0.0,
    this.sessionErrorRate = 0.0,
  });

  /// Check if any chaos setting is active (non-default).
  bool get isAnyActive {
    return llmDelayMs > 0 ||
        llmErrorRate > 0 ||
        rateLimitEnabled ||
        malformedResponseRate > 0 ||
        emptyResponseRate > 0 ||
        hallucinationEnabled ||
        tokenLimitErrorEnabled ||
        fixedDelayMs > 0 ||
        randomDelayMaxMs > 0 ||
        spikeDelayMs > 0 ||
        http500Rate > 0 ||
        http503Rate > 0 ||
        sessionErrorRate > 0;
  }

  factory ChaosConfig.fromJson(Map<String, dynamic> json) {
    return ChaosConfig(
      llmDelayMs: (json['llm_delay_ms'] as num?)?.toInt() ?? 0,
      llmErrorRate: (json['llm_error_rate'] as num?)?.toDouble() ?? 0.0,
      rateLimitEnabled: json['rate_limit_enabled'] as bool? ?? false,
      malformedResponseRate: (json['malformed_response_rate'] as num?)?.toDouble() ?? 0.0,
      emptyResponseRate: (json['empty_response_rate'] as num?)?.toDouble() ?? 0.0,
      hallucinationEnabled: json['hallucination_enabled'] as bool? ?? false,
      tokenLimitErrorEnabled: json['token_limit_error_enabled'] as bool? ?? false,
      fixedDelayMs: (json['fixed_delay_ms'] as num?)?.toInt() ?? 0,
      randomDelayMinMs: (json['random_delay_min_ms'] as num?)?.toInt() ?? 0,
      randomDelayMaxMs: (json['random_delay_max_ms'] as num?)?.toInt() ?? 0,
      spikeDelayMs: (json['spike_delay_ms'] as num?)?.toInt() ?? 0,
      spikeProbability: (json['spike_probability'] as num?)?.toDouble() ?? 0.0,
      http500Rate: (json['http_500_rate'] as num?)?.toDouble() ?? 0.0,
      http503Rate: (json['http_503_rate'] as num?)?.toDouble() ?? 0.0,
      sessionErrorRate: (json['session_error_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'llm_delay_ms': llmDelayMs,
    'llm_error_rate': llmErrorRate,
    'rate_limit_enabled': rateLimitEnabled,
    'malformed_response_rate': malformedResponseRate,
    'empty_response_rate': emptyResponseRate,
    'hallucination_enabled': hallucinationEnabled,
    'token_limit_error_enabled': tokenLimitErrorEnabled,
    'fixed_delay_ms': fixedDelayMs,
    'random_delay_min_ms': randomDelayMinMs,
    'random_delay_max_ms': randomDelayMaxMs,
    'spike_delay_ms': spikeDelayMs,
    'spike_probability': spikeProbability,
    'http_500_rate': http500Rate,
    'http_503_rate': http503Rate,
    'session_error_rate': sessionErrorRate,
  };
}

/// Chaos status payload returned by `GET /api/chaos/status`.
class ChaosStatus {
  final bool active;
  final ChaosConfig config;
  final String? preset;

  const ChaosStatus({
    required this.active,
    required this.config,
    required this.preset,
  });

  factory ChaosStatus.fromJson(Map<String, dynamic> json) {
    return ChaosStatus(
      active: json['active'] as bool? ?? false,
      config: ChaosConfig.fromJson(
        (json['config'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      preset: json['preset'] as String?,
    );
  }
}
