class AiChatSession {
  final int sessionId;
  final int supervisorId;
  final DateTime createdAt;
  final DateTime updatedAt;

  AiChatSession({
    required this.sessionId,
    required this.supervisorId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiChatSession.fromJson(Map<String, dynamic> json) => AiChatSession(
        sessionId: json['session_id'] ?? 0,
        supervisorId: json['supervisor_id'] ?? 0,
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      );

  String get title {
    final d = createdAt.toLocal();
    return 'Chat ${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class AiChatMessage {
  final int messageId;
  final int sessionId;
  final String role;
  final String content;
  final DateTime createdAt;
  final int tokensUsed;

  AiChatMessage({
    required this.messageId,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.tokensUsed = 0,
  });

  factory AiChatMessage.fromJson(Map<String, dynamic> json) => AiChatMessage(
        messageId: json['message_id'] ?? 0,
        sessionId: json['session_id'] ?? 0,
        role: json['role'] ?? 'user',
        content: json['content'] ?? '',
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        tokensUsed: json['tokens_used'] ?? 0,
      );

  bool get isUser => role == 'user';
}
