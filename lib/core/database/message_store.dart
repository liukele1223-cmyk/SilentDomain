import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/message.dart';

abstract interface class MessageStore {
  Future<List<Message>> loadMessages();

  Future<void> saveMessage(Message message);
}

/// Hive 数据库实现：内容使用 AES 加密，密钥由系统安全存储保护。
class HiveMessageStore implements MessageStore {
  HiveMessageStore._(this._box);

  static const _boxName = 'silent_domain_messages';
  static const _keyName = 'silent_domain_hive_key_v1';

  final Box<dynamic> _box;

  static Future<HiveMessageStore> create({
    FlutterSecureStorage? secureStorage,
  }) async {
    await Hive.initFlutter();
    final storage = secureStorage ?? const FlutterSecureStorage();
    final key = await _readOrCreateKey(storage);
    final box = await Hive.openBox<dynamic>(
      _boxName,
      encryptionCipher: HiveAesCipher(key),
    );
    return HiveMessageStore._(box);
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
  Future<List<Message>> loadMessages() async {
    return _box.values
        .whereType<Map>()
        .map((value) => _fromMap(Map<String, dynamic>.from(value)))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<void> saveMessage(Message message) {
    return _box.put(message.id, _toMap(message));
  }

  static Map<String, dynamic> _toMap(Message message) {
    return {
      'id': message.id,
      'sender': message.sender,
      'content': message.content,
      'timestamp': message.timestamp.toIso8601String(),
      'status': message.status.name,
      'emojiId': message.emojiId,
      'emojiName': message.emojiName,
    };
  }

  static Message _fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      sender: map['sender'] as String,
      content: map['content'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      status: MessageStatus.values.byName(map['status'] as String),
      emojiId: map['emojiId'] as String?,
      emojiName: map['emojiName'] as String?,
    );
  }
}

/// Widget 测试和纯 UI 预览使用的内存实现。
class MemoryMessageStore implements MessageStore {
  MemoryMessageStore({List<Message>? initialMessages})
    : _messages = [...?initialMessages];

  final List<Message> _messages;

  @override
  Future<List<Message>> loadMessages() async => [..._messages];

  @override
  Future<void> saveMessage(Message message) async {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] = message;
    }
  }
}
