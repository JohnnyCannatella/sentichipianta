class ChatMessage {
  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  final String text;
  final bool isUser;
  final DateTime timestamp;

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final role = map['role'] as String? ?? 'assistant';
    return ChatMessage(
      text: map['content'] as String? ?? '',
      isUser: role == 'user',
      timestamp: DateTime.parse(map['created_at'] as String),
    );
  }
}
