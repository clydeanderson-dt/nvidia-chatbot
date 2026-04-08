class StarterRequest {
  final String systemPrompt;
  final String provider;

  StarterRequest({
    required this.systemPrompt,
    this.provider = 'nim_api',
  });

  Map<String, dynamic> toJson() => {
    'system_prompt': systemPrompt,
    'provider': provider,
  };
}
