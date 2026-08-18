import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as image;

import 'emoji_sticker.dart';

abstract interface class EmojiStore {
  Future<List<EmojiSticker>> loadStickers();

  Future<EmojiStickerAsset?> loadAsset(String id);

  Future<EmojiSticker> importImage(Uint8List sourceBytes);
}

/// 为了移除 EXIF，先解码像素数据，再重新编码为 PNG。
/// PNG 文件不会带入原图的 EXIF；同时将最长边限制为 512 像素，适合聊天表情。
abstract final class EmojiImageSanitizer {
  static Uint8List sanitize(Uint8List sourceBytes) {
    final decoded = image.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const FormatException('无法识别这张图片');
    }
    final oriented = image.bakeOrientation(decoded);
    final largestSide = max(oriented.width, oriented.height);
    final normalized = largestSide > 512
        ? image.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? 512 : null,
            height: oriented.height > oriented.width ? 512 : null,
            interpolation: image.Interpolation.average,
          )
        : oriented;
    return Uint8List.fromList(image.encodePng(normalized, level: 6));
  }
}

/// 表情元数据和图像字节都位于独立的 Hive AES 加密资料库中。
class HiveEmojiStore implements EmojiStore {
  HiveEmojiStore._(this._box);

  static const _boxName = 'silent_domain_emoji_assets';
  static const _keyName = 'silent_domain_emoji_hive_key_v1';

  final Box<dynamic> _box;

  static Future<HiveEmojiStore> create({
    FlutterSecureStorage? secureStorage,
  }) async {
    await Hive.initFlutter();
    final storage = secureStorage ?? const FlutterSecureStorage();
    final key = await _readOrCreateKey(storage);
    final box = await Hive.openBox<dynamic>(
      _boxName,
      encryptionCipher: HiveAesCipher(key),
    );
    return HiveEmojiStore._(box);
  }

  static Future<List<int>> _readOrCreateKey(
    FlutterSecureStorage storage,
  ) async {
    final encoded = await storage.read(key: _keyName);
    if (encoded != null) return base64Url.decode(encoded);

    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await storage.write(key: _keyName, value: base64Url.encode(key));
    return key;
  }

  @override
  Future<List<EmojiSticker>> loadStickers() async {
    final stickers = _box.values
        .whereType<Map>()
        .map((value) => _stickerFromMap(Map<String, dynamic>.from(value)))
        .toList();
    stickers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return stickers;
  }

  @override
  Future<EmojiStickerAsset?> loadAsset(String id) async {
    final value = _box.get(id);
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final encodedBytes = map['bytes'] as String?;
    if (encodedBytes == null) return null;
    return EmojiStickerAsset(
      sticker: _stickerFromMap(map),
      bytes: Uint8List.fromList(base64Url.decode(encodedBytes)),
    );
  }

  @override
  Future<EmojiSticker> importImage(Uint8List sourceBytes) async {
    final bytes = EmojiImageSanitizer.sanitize(sourceBytes);
    final now = DateTime.now();
    final id = 'emoji-${now.microsecondsSinceEpoch}';
    final sticker = EmojiSticker(
      id: id,
      name:
          '表情 ${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}',
      path: 'hive://$_boxName/$id.png',
      createdAt: now,
    );
    await _box.put(id, {
      'id': sticker.id,
      'name': sticker.name,
      'path': sticker.path,
      'createdAt': sticker.createdAt.toIso8601String(),
      'bytes': base64UrlEncode(bytes),
    });
    return sticker;
  }

  static EmojiSticker _stickerFromMap(Map<String, dynamic> map) {
    return EmojiSticker(
      id: map['id'] as String,
      name: map['name'] as String,
      path: map['path'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

/// Widget 测试使用的纯内存表情资料库。
class MemoryEmojiStore implements EmojiStore {
  final Map<String, EmojiStickerAsset> _assets = {};

  @override
  Future<List<EmojiSticker>> loadStickers() async {
    final stickers = _assets.values.map((asset) => asset.sticker).toList();
    stickers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return stickers;
  }

  @override
  Future<EmojiStickerAsset?> loadAsset(String id) async => _assets[id];

  @override
  Future<EmojiSticker> importImage(Uint8List sourceBytes) async {
    final bytes = EmojiImageSanitizer.sanitize(sourceBytes);
    final now = DateTime.now();
    final id = 'memory-emoji-${now.microsecondsSinceEpoch}';
    final sticker = EmojiSticker(
      id: id,
      name: '测试表情',
      path: 'memory://$id.png',
      createdAt: now,
    );
    _assets[id] = EmojiStickerAsset(sticker: sticker, bytes: bytes);
    return sticker;
  }
}
