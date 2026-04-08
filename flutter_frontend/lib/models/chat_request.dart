class ChatRequest {
  final String sessionId;
  final String message;
  final String systemPrompt;
  final String provider;

  ChatRequest({
    required this.sessionId,
    required this.message,
    required this.systemPrompt,
    this.provider = 'nim_api',
  });

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'message': message,
    'system_prompt': systemPrompt,
    'provider': provider,
  };
}
