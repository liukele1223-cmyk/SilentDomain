import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/image_transfer_metric.dart';

abstract interface class ImageTransferMetricsStore {
  Future<void> record(ImageTransferMetric metric);

  Future<List<ImageTransferMetric>> loadRecent({int limit = 80});

  Future<void> clear();
}

/// 保存在本机加密 Hive 资料库中的传输性能记录。
///
/// 最多保留最近 120 条，只保存诊断元数据，避免长期占用空间或保留聊天内容。
class HiveImageTransferMetricsStore implements ImageTransferMetricsStore {
  HiveImageTransferMetricsStore._(this._box);

  static const _boxName = 'silent_domain_image_transfer_metrics';
  static const _keyName = 'silent_domain_image_transfer_metrics_key_v1';
  static const maximumEntryCount = 120;

  final Box<dynamic> _box;
  Future<void> _mutationQueue = Future<void>.value();

  static Future<HiveImageTransferMetricsStore> create({
    FlutterSecureStorage? secureStorage,
  }) async {
    await Hive.initFlutter();
    final storage = secureStorage ?? const FlutterSecureStorage();
    final key = await _readOrCreateKey(storage);
    final box = await Hive.openBox<dynamic>(
      _boxName,
      encryptionCipher: HiveAesCipher(key),
    );
    return HiveImageTransferMetricsStore._(box);
  }

  static Future<List<int>> _readOrCreateKey(
    FlutterSecureStorage storage,
  ) async {
    final encoded = await storage.read(key: _keyName);
    if (encoded != null) {
      final key = base64Url.decode(encoded);
      if (key.length != 32) {
        throw const FormatException('图片传输诊断密钥无效');
      }
      return key;
    }
    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await storage.write(key: _keyName, value: base64UrlEncode(key));
    return key;
  }

  @override
  Future<void> record(ImageTransferMetric metric) =>
      _enqueueMutation(() => _recordNow(metric));

  Future<void> _recordNow(ImageTransferMetric metric) async {
    await _box.put(metric.id, metric.toMap());
    final entries = <MapEntry<dynamic, ImageTransferMetric>>[];
    final invalidKeys = <dynamic>[];
    for (final entry in _box.toMap().entries) {
      final value = entry.value;
      if (value is! Map) {
        invalidKeys.add(entry.key);
        continue;
      }
      try {
        entries.add(
          MapEntry(
            entry.key,
            ImageTransferMetric.fromMap(Map<String, dynamic>.from(value)),
          ),
        );
      } on Object {
        invalidKeys.add(entry.key);
      }
    }
    entries.sort((a, b) => b.value.occurredAt.compareTo(a.value.occurredAt));
    final excessKeys = entries
        .skip(maximumEntryCount)
        .map((entry) => entry.key);
    final keysToDelete = <dynamic>[...invalidKeys, ...excessKeys];
    if (keysToDelete.isNotEmpty) await _box.deleteAll(keysToDelete);
  }

  @override
  Future<List<ImageTransferMetric>> loadRecent({int limit = 80}) async {
    await _mutationQueue;
    final records = <ImageTransferMetric>[];
    for (final value in _box.values.whereType<Map>()) {
      try {
        records.add(
          ImageTransferMetric.fromMap(Map<String, dynamic>.from(value)),
        );
      } on Object {
        // 诊断记录损坏不应影响聊天、图片或其他本地资料库。
      }
    }
    records.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return records.take(limit.clamp(0, maximumEntryCount).toInt()).toList();
  }

  @override
  Future<void> clear() => _enqueueMutation(() async {
    await _box.clear();
  });

  Future<void> _enqueueMutation(Future<void> Function() mutation) {
    final operation = _mutationQueue.then((_) => mutation());
    _mutationQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}

/// Widget 测试与纯 UI 预览使用的内存实现。
class MemoryImageTransferMetricsStore implements ImageTransferMetricsStore {
  MemoryImageTransferMetricsStore({List<ImageTransferMetric>? initialRecords})
    : _records = [...?initialRecords] {
    _sortAndTrim();
  }

  final List<ImageTransferMetric> _records;

  @override
  Future<void> record(ImageTransferMetric metric) async {
    _records.removeWhere((item) => item.id == metric.id);
    _records.add(metric);
    _sortAndTrim();
  }

  void _sortAndTrim() {
    _records.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (_records.length > HiveImageTransferMetricsStore.maximumEntryCount) {
      _records.removeRange(
        HiveImageTransferMetricsStore.maximumEntryCount,
        _records.length,
      );
    }
  }

  @override
  Future<List<ImageTransferMetric>> loadRecent({int limit = 80}) async {
    return _records
        .take(
          limit
              .clamp(0, HiveImageTransferMetricsStore.maximumEntryCount)
              .toInt(),
        )
        .toList();
  }

  @override
  Future<void> clear() async => _records.clear();
}
