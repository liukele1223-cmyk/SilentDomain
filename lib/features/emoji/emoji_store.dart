import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as image;

import 'emoji_sticker.dart';

abstract interface class EmojiStore {
  /// 用户主动保存到“我的表情”的图片。
  Future<List<EmojiSticker>> loadStickers();

  /// 收到但尚未主动保存为表情的聊天图片附件。
  Future<List<EmojiSticker>> loadTransferredAttachments();

  Future<EmojiStickerAsset?> loadAsset(String id);

  Future<EmojiSticker> importImage(Uint8List sourceBytes);

  /// 保存已校验的聊天附件。它不会自动进入“我的表情”，除非用户主动保存。
  Future<EmojiSticker> importTransferredImage(
    Uint8List bytes, {
    required String name,
  });

  /// 仅在用户主动操作时，将接收附件加入“我的表情”。
  Future<EmojiSticker?> saveAsLocalSticker(String id);

  Future<EmojiSticker?> renameSticker(String id, String name);

  /// 删除一张本地表情及其加密图片数据。
  Future<void> deleteSticker(String id);

  /// 批量删除资料库项目，返回实际删除数量。
  Future<int> deleteStickers(Iterable<String> ids);

  Future<EmojiStorageStats> loadStorageStats();

  /// 清理未被用户保存为表情的接收附件。对应聊天消息保留文字回退提示。
  Future<int> clearTransferredAttachments();
}

class EmojiStorageStats {
  const EmojiStorageStats({
    required this.localCount,
    required this.localBytes,
    required this.attachmentCount,
    required this.attachmentBytes,
  });

  final int localCount;
  final int localBytes;
  final int attachmentCount;
  final int attachmentBytes;

  int get totalBytes => localBytes + attachmentBytes;
}

/// 为了移除 EXIF，先解码像素数据，再按透明度重新编码。
/// 透明表情保留为无损 WebP；普通照片改为高质量 JPEG，以显著减少离线
/// 蓝牙传输所需的字节数。两种格式都不会带入原图的 EXIF。
abstract final class EmojiImageSanitizer {
  static const maximumDimension = 256;
  // 透明图采用无损 WebP；在 BLE 上它通常比同尺寸 JPEG 大得多。192px 在
  // 聊天内的显示尺寸仍有余量，能显著降低透明表情的分片数和等待时间。
  static const maximumTransparentDimension = 192;

  static Uint8List sanitize(Uint8List sourceBytes) {
    final decoded = image.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const FormatException('无法识别这张图片');
    }
    final oriented = image.bakeOrientation(decoded);
    final hasTransparency = _hasTransparentPixels(oriented);
    final maximumDimensionForImage = hasTransparency
        ? maximumTransparentDimension
        : maximumDimension;
    final largestSide = max(oriented.width, oriented.height);
    final normalized = largestSide > maximumDimensionForImage
        ? image.copyResize(
            oriented,
            width: oriented.width >= oriented.height
                ? maximumDimensionForImage
                : null,
            height: oriented.height > oriented.width
                ? maximumDimensionForImage
                : null,
            interpolation: image.Interpolation.average,
          )
        : oriented;
    if (hasTransparency) {
      return image.encodeWebP(normalized);
    }
    return image.encodeJpg(normalized, quality: 80);
  }

  static bool _hasTransparentPixels(image.Image source) {
    if (!source.hasAlpha) return false;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        if (source.getPixel(x, y).a < 255) return true;
      }
    }
    return false;
  }
}

/// 表情元数据和图像字节都位于独立的 Hive AES 加密资料库中。
class HiveEmojiStore implements EmojiStore {
  HiveEmojiStore._(this._box);

  static const _boxName = 'silent_domain_emoji_assets';
  static const _keyName = 'silent_domain_emoji_hive_key_v1';

  final Box<dynamic> _box;
  int _idSequence = 0;

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
        // 旧版本没有该字段，按可见处理，避免升级后隐藏用户已有表情。
        .where((value) => value['isLocalSticker'] != false)
        .map((value) => _stickerFromMap(Map<String, dynamic>.from(value)))
        .toList();
    stickers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return stickers;
  }

  @override
  Future<List<EmojiSticker>> loadTransferredAttachments() async {
    final attachments = _box.values
        .whereType<Map>()
        .where((value) => value['isLocalSticker'] == false)
        .map((value) => _stickerFromMap(Map<String, dynamic>.from(value)))
        .toList();
    attachments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return attachments;
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
    return _storeImage(bytes, name: _defaultName(), isLocalSticker: true);
  }

  @override
  Future<EmojiSticker> importTransferredImage(
    Uint8List bytes, {
    required String name,
  }) async {
    if (bytes.isEmpty || image.decodeImage(bytes) == null) {
      throw const FormatException('无法识别接收到的图片');
    }
    return _storeImage(bytes, name: name, isLocalSticker: false);
  }

  @override
  Future<EmojiSticker?> saveAsLocalSticker(String id) async {
    final value = _box.get(id);
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    map['isLocalSticker'] = true;
    await _box.put(id, map);
    return _stickerFromMap(map);
  }

  @override
  Future<EmojiSticker?> renameSticker(String id, String name) async {
    final normalizedName = _normalizeName(name);
    final value = _box.get(id);
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    map['name'] = normalizedName;
    await _box.put(id, map);
    return _stickerFromMap(map);
  }

  @override
  Future<void> deleteSticker(String id) => _box.delete(id);

  @override
  Future<int> deleteStickers(Iterable<String> ids) async {
    final existingIds = ids.toSet().where(_box.containsKey).toList();
    if (existingIds.isEmpty) return 0;
    await _box.deleteAll(existingIds);
    return existingIds.length;
  }

  @override
  Future<EmojiStorageStats> loadStorageStats() async {
    var localCount = 0;
    var localBytes = 0;
    var attachmentCount = 0;
    var attachmentBytes = 0;
    for (final value in _box.values.whereType<Map>()) {
      final map = Map<String, dynamic>.from(value);
      final bytes = _byteLength(map);
      if (map['isLocalSticker'] != false) {
        localCount++;
        localBytes += bytes;
      } else {
        attachmentCount++;
        attachmentBytes += bytes;
      }
    }
    return EmojiStorageStats(
      localCount: localCount,
      localBytes: localBytes,
      attachmentCount: attachmentCount,
      attachmentBytes: attachmentBytes,
    );
  }

  @override
  Future<int> clearTransferredAttachments() async {
    final ids = <dynamic>[];
    for (final key in _box.keys) {
      final value = _box.get(key);
      if (value is Map && value['isLocalSticker'] == false) ids.add(key);
    }
    if (ids.isNotEmpty) await _box.deleteAll(ids);
    return ids.length;
  }

  Future<EmojiSticker> _storeImage(
    Uint8List bytes, {
    required String name,
    required bool isLocalSticker,
  }) async {
    final now = DateTime.now();
    final id = 'emoji-${now.microsecondsSinceEpoch}-${_idSequence++}';
    final sticker = EmojiSticker(
      id: id,
      name: name,
      path: 'hive://$_boxName/$id.png',
      createdAt: now,
      byteLength: bytes.length,
      isLocalSticker: isLocalSticker,
    );
    await _box.put(id, {
      'id': sticker.id,
      'name': sticker.name,
      'path': sticker.path,
      'createdAt': sticker.createdAt.toIso8601String(),
      'bytes': base64UrlEncode(bytes),
      'isLocalSticker': isLocalSticker,
      'byteLength': bytes.length,
    });
    return sticker;
  }

  String _defaultName() {
    final now = DateTime.now();
    return '表情 ${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  static EmojiSticker _stickerFromMap(Map<String, dynamic> map) {
    return EmojiSticker(
      id: map['id'] as String,
      name: map['name'] as String,
      path: map['path'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      byteLength: _byteLength(map),
      isLocalSticker: map['isLocalSticker'] != false,
    );
  }

  static int _byteLength(Map<String, dynamic> map) {
    final stored = map['byteLength'];
    if (stored is int && stored >= 0) return stored;
    final encoded = map['bytes'];
    return encoded is String ? base64Url.decode(encoded).length : 0;
  }

  static String _normalizeName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 96) {
      throw ArgumentError.value(name, 'name', '表情名称长度无效');
    }
    return normalized;
  }
}

/// Widget 测试使用的纯内存表情资料库。
class MemoryEmojiStore implements EmojiStore {
  final Map<String, EmojiStickerAsset> _assets = {};
  final Set<String> _localStickerIds = <String>{};
  int _idSequence = 0;

  @override
  Future<List<EmojiSticker>> loadStickers() async {
    final stickers = _assets.entries
        .where((entry) => _localStickerIds.contains(entry.key))
        .map((entry) => entry.value.sticker)
        .toList();
    stickers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return stickers;
  }

  @override
  Future<List<EmojiSticker>> loadTransferredAttachments() async {
    final attachments = _assets.entries
        .where((entry) => !_localStickerIds.contains(entry.key))
        .map((entry) => entry.value.sticker)
        .toList();
    attachments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return attachments;
  }

  @override
  Future<EmojiStickerAsset?> loadAsset(String id) async => _assets[id];

  @override
  Future<EmojiSticker> importImage(Uint8List sourceBytes) async {
    final bytes = EmojiImageSanitizer.sanitize(sourceBytes);
    return _storeImage(bytes, name: '测试表情', isLocalSticker: true);
  }

  @override
  Future<EmojiSticker> importTransferredImage(
    Uint8List bytes, {
    required String name,
  }) async {
    if (bytes.isEmpty || image.decodeImage(bytes) == null) {
      throw const FormatException('无法识别接收到的图片');
    }
    return _storeImage(bytes, name: name, isLocalSticker: false);
  }

  @override
  Future<EmojiSticker?> saveAsLocalSticker(String id) async {
    final asset = _assets[id];
    if (asset == null) return null;
    _localStickerIds.add(id);
    _assets[id] = EmojiStickerAsset(
      sticker: EmojiSticker(
        id: asset.sticker.id,
        name: asset.sticker.name,
        path: asset.sticker.path,
        createdAt: asset.sticker.createdAt,
        byteLength: asset.bytes.length,
        isLocalSticker: true,
      ),
      bytes: asset.bytes,
    );
    return _assets[id]!.sticker;
  }

  @override
  Future<EmojiSticker?> renameSticker(String id, String name) async {
    final asset = _assets[id];
    if (asset == null) return null;
    final normalizedName = HiveEmojiStore._normalizeName(name);
    _assets[id] = EmojiStickerAsset(
      sticker: EmojiSticker(
        id: asset.sticker.id,
        name: normalizedName,
        path: asset.sticker.path,
        createdAt: asset.sticker.createdAt,
        byteLength: asset.bytes.length,
        isLocalSticker: _localStickerIds.contains(id),
      ),
      bytes: asset.bytes,
    );
    return _assets[id]!.sticker;
  }

  @override
  Future<void> deleteSticker(String id) async {
    _assets.remove(id);
    _localStickerIds.remove(id);
  }

  @override
  Future<int> deleteStickers(Iterable<String> ids) async {
    var deleted = 0;
    for (final id in ids.toSet()) {
      if (_assets.remove(id) != null) {
        _localStickerIds.remove(id);
        deleted++;
      }
    }
    return deleted;
  }

  @override
  Future<EmojiStorageStats> loadStorageStats() async {
    var localBytes = 0;
    var attachmentBytes = 0;
    for (final entry in _assets.entries) {
      if (_localStickerIds.contains(entry.key)) {
        localBytes += entry.value.bytes.length;
      } else {
        attachmentBytes += entry.value.bytes.length;
      }
    }
    return EmojiStorageStats(
      localCount: _localStickerIds.length,
      localBytes: localBytes,
      attachmentCount: _assets.length - _localStickerIds.length,
      attachmentBytes: attachmentBytes,
    );
  }

  @override
  Future<int> clearTransferredAttachments() async {
    final ids = _assets.keys
        .where((id) => !_localStickerIds.contains(id))
        .toList();
    for (final id in ids) {
      _assets.remove(id);
    }
    return ids.length;
  }

  Future<EmojiSticker> _storeImage(
    Uint8List bytes, {
    required String name,
    required bool isLocalSticker,
  }) async {
    final now = DateTime.now();
    final id = 'memory-emoji-${now.microsecondsSinceEpoch}-${_idSequence++}';
    final sticker = EmojiSticker(
      id: id,
      name: name,
      path: 'memory://$id.png',
      createdAt: now,
      byteLength: bytes.length,
      isLocalSticker: isLocalSticker,
    );
    _assets[id] = EmojiStickerAsset(
      sticker: sticker,
      bytes: Uint8List.fromList(bytes),
    );
    if (isLocalSticker) _localStickerIds.add(id);
    return sticker;
  }
}
