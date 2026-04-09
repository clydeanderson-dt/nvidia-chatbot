/// Chaos configuration model for fault injection settings.
class ChaosConfig {
  // LLM-specific failures
  final int llmDelayMs;
  final double llmErrorRate;
  final bool rateLimitEnabled;
  final int rateLimitAfterN;
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
    this.rateLimitAfterN = 5,
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
        randomDelayMinMs > 0 ||
        randomDelayMaxMs > 0 ||
        spikeDelayMs > 0 ||
        spikeProbability > 0 ||
        http500Rate > 0 ||
        http503Rate > 0 ||
        sessionErrorRate > 0;
  }

  factory ChaosConfig.fromJson(Map<String, dynamic> json) {
    return ChaosConfig(
      llmDelayMs: (json['llm_delay_ms'] as num?)?.toInt() ?? 0,
      llmErrorRate: (json['llm_error_rate'] as num?)?.toDouble() ?? 0.0,
      rateLimitEnabled: json['rate_limit_enabled'] as bool? ?? false,
      rateLimitAfterN: (json['rate_limit_after_n'] as num?)?.toInt() ?? 5,
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
    'rate_limit_after_n': rateLimitAfterN,
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

  ChaosConfig copyWith({
    int? llmDelayMs,
    double? llmErrorRate,
    bool? rateLimitEnabled,
    int? rateLimitAfterN,
    double? malformedResponseRate,
    double? emptyResponseRate,
    bool? hallucinationEnabled,
    bool? tokenLimitErrorEnabled,
    int? fixedDelayMs,
    int? randomDelayMinMs,
    int? randomDelayMaxMs,
    int? spikeDelayMs,
    double? spikeProbability,
    double? http500Rate,
    double? http503Rate,
    double? sessionErrorRate,
  }) {
    return ChaosConfig(
      llmDelayMs: llmDelayMs ?? this.llmDelayMs,
      llmErrorRate: llmErrorRate ?? this.llmErrorRate,
      rateLimitEnabled: rateLimitEnabled ?? this.rateLimitEnabled,
      rateLimitAfterN: rateLimitAfterN ?? this.rateLimitAfterN,
      malformedResponseRate: malformedResponseRate ?? this.malformedResponseRate,
      emptyResponseRate: emptyResponseRate ?? this.emptyResponseRate,
      hallucinationEnabled: hallucinationEnabled ?? this.hallucinationEnabled,
      tokenLimitErrorEnabled: tokenLimitErrorEnabled ?? this.tokenLimitErrorEnabled,
      fixedDelayMs: fixedDelayMs ?? this.fixedDelayMs,
      randomDelayMinMs: randomDelayMinMs ?? this.randomDelayMinMs,
      randomDelayMaxMs: randomDelayMaxMs ?? this.randomDelayMaxMs,
      spikeDelayMs: spikeDelayMs ?? this.spikeDelayMs,
      spikeProbability: spikeProbability ?? this.spikeProbability,
      http500Rate: http500Rate ?? this.http500Rate,
      http503Rate: http503Rate ?? this.http503Rate,
      sessionErrorRate: sessionErrorRate ?? this.sessionErrorRate,
    );
  }
}

/// Chaos preset for quick configuration profiles.
class ChaosPreset {
  final String name;
  final String description;

  const ChaosPreset({
    required this.name,
    required this.description,
  });
}

/// Available chaos presets (matching backend).
const List<ChaosPreset> chaosPresets = [
  ChaosPreset(name: 'healthy', description: 'All chaos disabled'),
  ChaosPreset(name: 'slow_llm', description: '5 second LLM delay'),
  ChaosPreset(name: 'flaky_network', description: '30% HTTP 500s, random delays'),
  ChaosPreset(name: 'rate_limited', description: 'Rate limit after 3 requests'),
  ChaosPreset(name: 'degraded', description: '20% LLM errors, 10% empty, 1s delay'),
];
