import 'dart:typed_data';

/// 用户导入的本地表情元数据。
class EmojiSticker {
  const EmojiSticker({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    this.byteLength = 0,
    this.isLocalSticker = true,
  });

  final String id;
  final String name;

  /// 加密资料库中的逻辑路径，不暴露用户相册原始路径。
  final String path;
  final DateTime createdAt;

  /// 加密资料库中图片数据的大小，仅用于本机存储占用展示。
  final int byteLength;

  /// 是否已由用户保存到“我的表情”。接收附件默认不会加入该列表。
  final bool isLocalSticker;
}

/// 解密后仅在内存中使用的表情图像数据。
class EmojiStickerAsset {
  const EmojiStickerAsset({required this.sticker, required this.bytes});

  final EmojiSticker sticker;
  final Uint8List bytes;
}
