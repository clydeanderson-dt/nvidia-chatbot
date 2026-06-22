class StarterRequest {
  final String systemPrompt;
  final String provider;
  final String? sessionId;

  StarterRequest({
    required this.systemPrompt,
    this.provider = 'nim_api',
    this.sessionId,
  });

  Map<String, dynamic> toJson() => {
    'system_prompt': systemPrompt,
    'provider': provider,
    if (sessionId != null) 'session_id': sessionId,
  };
}
