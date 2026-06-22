class StarterResponse {
  final List<String> suggestions;
  final String? model;

  StarterResponse({this.suggestions = const [], this.model});

  factory StarterResponse.fromJson(Map<String, dynamic> json) {
    return StarterResponse(
      suggestions: (json['suggestions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      model: json['model'] as String?,
    );
  }
}
