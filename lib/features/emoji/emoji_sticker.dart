import 'dart:typed_data';

/// 用户导入的本地表情元数据。
class EmojiSticker {
  const EmojiSticker({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// 加密资料库中的逻辑路径，不暴露用户相册原始路径。
  final String path;
  final DateTime createdAt;
}

/// 解密后仅在内存中使用的表情图像数据。
class EmojiStickerAsset {
  const EmojiStickerAsset({required this.sticker, required this.bytes});

  final EmojiSticker sticker;
  final Uint8List bytes;
}
