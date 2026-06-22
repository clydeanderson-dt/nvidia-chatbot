class ChatResponse {
  final String reply;
  final List<String> suggestions;
  final String? model;
  final String? suggestionsModel;

  ChatResponse({
    required this.reply,
    this.suggestions = const [],
    this.model,
    this.suggestionsModel,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      reply: json['reply'] as String,
      suggestions: (json['suggestions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      model: json['model'] as String?,
      suggestionsModel: json['suggestions_model'] as String?,
    );
  }
}
