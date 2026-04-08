class ChatResponse {
  final String reply;
  final List<String> suggestions;

  ChatResponse({required this.reply, this.suggestions = const []});

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      reply: json['reply'] as String,
      suggestions: (json['suggestions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}
