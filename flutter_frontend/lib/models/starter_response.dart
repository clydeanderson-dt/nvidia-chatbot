class StarterResponse {
  final List<String> suggestions;
  final String? model;
  final String? suggestionsModel;

  StarterResponse({
    this.suggestions = const [],
    this.model,
    this.suggestionsModel,
  });

  factory StarterResponse.fromJson(Map<String, dynamic> json) {
    return StarterResponse(
      suggestions: (json['suggestions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      model: json['model'] as String?,
      suggestionsModel: json['suggestions_model'] as String?,
    );
  }
}
