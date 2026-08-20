import 'dart:typed_data';

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
    this.emojiSnapshot,
    this.transferProgress,
  });

  final String id;
  final String sender;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;

  /// 本机表情资料库中的引用。表情文件传输将在图片传输阶段实现。
  final String? emojiId;
  final String? emojiName;

  /// 为聊天记录保存的压缩图片快照。它只写入本机加密消息库，不会附带在
  /// 普通协议包里；图片仍通过分片传输，避免重复占用蓝牙带宽。
  final Uint8List? emojiSnapshot;

  /// 图片发送中的进度，取值 0 到 1；已完成或普通文本为 null。
  final double? transferProgress;

  Message copyWith({
    String? id,
    String? sender,
    String? content,
    DateTime? timestamp,
    MessageStatus? status,
    String? emojiId,
    String? emojiName,
    Uint8List? emojiSnapshot,
    double? transferProgress,
  }) {
    return Message(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      emojiId: emojiId ?? this.emojiId,
      emojiName: emojiName ?? this.emojiName,
      emojiSnapshot: emojiSnapshot ?? this.emojiSnapshot,
      transferProgress: transferProgress ?? this.transferProgress,
    );
  }
}
