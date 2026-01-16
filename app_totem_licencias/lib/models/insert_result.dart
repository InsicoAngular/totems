class InsertResult {
  final bool success;
  final int ticket;
  final dynamic extra;
  final String? message;  // Agregar este campo

  InsertResult({
    required this.success,
    this.ticket = 0,
    this.extra,
    this.message,
  });

  factory InsertResult.fromJson(Map<String, dynamic> json) {
    return InsertResult(
      success: json['success'] as bool,
      ticket: (json['ticket'] ?? 0) as int,
      extra: json['extra'],
      message: json['message'] as String?,
    );
  }
}