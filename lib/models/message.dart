/// 本地聊天消息的状态。
enum MessageStatus { sending, success, failed }

/// 阶段 2 使用的本地消息模型。
class Message {
  const Message({
    required this.id,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.status = MessageStatus.success,
    this.emojiId,
    this.emojiName,
  });

  final String id;
  final String sender;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;

  /// 本机表情资料库中的引用。表情文件传输将在图片传输阶段实现。
  final String? emojiId;
  final String? emojiName;

  Message copyWith({
    String? id,
    String? sender,
    String? content,
    DateTime? timestamp,
    MessageStatus? status,
    String? emojiId,
    String? emojiName,
  }) {
    return Message(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      emojiId: emojiId ?? this.emojiId,
      emojiName: emojiName ?? this.emojiName,
    );
  }
}
