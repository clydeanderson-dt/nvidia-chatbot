class ChatResponse {
  final String reply;
  final List<String> suggestions;
  final String? model;

  ChatResponse({required this.reply, this.suggestions = const [], this.model});

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      reply: json['reply'] as String,
      suggestions: (json['suggestions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      model: json['model'] as String?,
    );
  }
}
