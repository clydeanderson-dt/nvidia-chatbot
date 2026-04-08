class StarterResponse {
  final List<String> suggestions;

  StarterResponse({this.suggestions = const []});

  factory StarterResponse.fromJson(Map<String, dynamic> json) {
    return StarterResponse(
      suggestions: (json['suggestions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}
