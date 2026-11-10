/// A customer review question the admin has set up. The BA ticks the ones
/// that apply to each product when submitting low stock.
class ReviewQuestion {
  final int id;
  final String text;
  const ReviewQuestion({required this.id, required this.text});

  factory ReviewQuestion.fromJson(Map<String, dynamic> j) {
    final raw = j['question_id'];
    return ReviewQuestion(
      id: raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}') ?? 0,
      text: '${j['question_text'] ?? ''}'.trim(),
    );
  }
}

/// Answer of the server to "may this account be used on this phone?"
class DeviceCheck {
  final bool allowed;
  final String message;
  const DeviceCheck(this.allowed, this.message);
}
