/// App configuration model for system prompt and LLM provider.
class AppConfig {
  final String systemPrompt;
  final String provider;

  const AppConfig({
    this.systemPrompt = 'You are a helpful, knowledgeable, and friendly AI assistant.',
    this.provider = 'nim_api',
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      systemPrompt: json['system_prompt'] as String? ?? 
          'You are a helpful, knowledgeable, and friendly AI assistant.',
      provider: json['provider'] as String? ?? 'nim_api',
    );
  }

  Map<String, dynamic> toJson() => {
    'system_prompt': systemPrompt,
    'provider': provider,
  };

  AppConfig copyWith({
    String? systemPrompt,
    String? provider,
  }) {
    return AppConfig(
      systemPrompt: systemPrompt ?? this.systemPrompt,
      provider: provider ?? this.provider,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfig &&
          runtimeType == other.runtimeType &&
          systemPrompt == other.systemPrompt &&
          provider == other.provider;

  @override
  int get hashCode => systemPrompt.hashCode ^ provider.hashCode;
}
