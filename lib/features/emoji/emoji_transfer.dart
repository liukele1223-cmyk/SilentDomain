import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 图片传输开始时发送的公开元数据。
///
/// 图像字节本身仍会经过当前 BLE 会话的 AES-256-GCM 加密；这里不包含相册
/// 路径、原始文件名或 EXIF 等隐私信息。
class EmojiTransferManifest {
  const EmojiTransferManifest({
    required this.content,
    required this.name,
    required this.timestamp,
    required this.byteLength,
    required this.chunkCount,
    required this.checksum,
  });

  /// 单张表情上限。导入阶段已缩放至最长边 512px，限制仍可防御异常数据。
  static const maximumByteLength = 256 * 1024;

  /// 每个应用层分片的原始字节数。它会再由 BLE 会话层按协商 MTU 分帧。
  static const chunkByteLength = 1024;

  final String content;
  final String name;
  final DateTime timestamp;
  final int byteLength;
  final int chunkCount;
  final String checksum;

  Map<String, Object> toJson() => {
    'content': content,
    'name': name,
    'timestamp': timestamp.toIso8601String(),
    'byteLength': byteLength,
    'chunkCount': chunkCount,
    'checksum': checksum,
  };

  factory EmojiTransferManifest.fromJson(Map<String, dynamic> json) {
    final content = json['content'];
    final name = json['name'];
    final timestamp = json['timestamp'];
    final byteLength = json['byteLength'];
    final chunkCount = json['chunkCount'];
    final checksum = json['checksum'];
    if (content is! String ||
        name is! String ||
        timestamp is! String ||
        byteLength is! int ||
        chunkCount is! int ||
        checksum is! String ||
        content.length > 512 ||
        name.length > 96 ||
        byteLength <= 0 ||
        byteLength > maximumByteLength ||
        chunkCount != _expectedChunkCount(byteLength)) {
      throw const FormatException('图片传输元数据无效');
    }
    return EmojiTransferManifest(
      content: content,
      name: name,
      timestamp: DateTime.parse(timestamp),
      byteLength: byteLength,
      chunkCount: chunkCount,
      checksum: checksum,
    );
  }

  static int _expectedChunkCount(int byteLength) =>
      (byteLength / chunkByteLength).ceil();
}

/// 纯协议层的分片、校验和接收重组工具，便于自动测试。
abstract final class EmojiTransferCodec {
  /// 每批分片得到接收端确认后，发送端才继续下一批。小批量确认能在弱 BLE
  /// 链路及时发现丢包，而不会等整张图片发送到 100% 才失败。
  // 适度扩大确认批次，减少双方同时传图时争抢 BLE 反向通知的次数。
  static const acknowledgementInterval = 6;

  static Future<String> checksum(Uint8List bytes) async {
    final digest = await Sha256().hash(bytes);
    return base64UrlEncode(digest.bytes);
  }

  static List<Uint8List> split(Uint8List bytes) {
    if (bytes.isEmpty ||
        bytes.length > EmojiTransferManifest.maximumByteLength) {
      throw const FormatException('图片大小不在允许范围内');
    }
    return List<Uint8List>.generate(
      (bytes.length / EmojiTransferManifest.chunkByteLength).ceil(),
      (index) {
        final start = index * EmojiTransferManifest.chunkByteLength;
        final end = (start + EmojiTransferManifest.chunkByteLength).clamp(
          0,
          bytes.length,
        );
        return Uint8List.fromList(bytes.sublist(start, end));
      },
    );
  }

  static String encodeChunk(int index, Uint8List bytes) =>
      jsonEncode({'index': index, 'bytes': base64UrlEncode(bytes)});

  static ({int index, Uint8List bytes}) decodeChunk(String payload) {
    final value = jsonDecode(payload);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('图片分片格式无效');
    }
    final index = value['index'];
    final encoded = value['bytes'];
    if (index is! int || index < 0 || encoded is! String) {
      throw const FormatException('图片分片字段无效');
    }
    final bytes = Uint8List.fromList(base64Url.decode(encoded));
    if (bytes.isEmpty || bytes.length > EmojiTransferManifest.chunkByteLength) {
      throw const FormatException('图片分片大小无效');
    }
    return (index: index, bytes: bytes);
  }
}

/// 接收端暂存单个图片。只有全部分片、长度和校验和均正确时才返回数据。
class EmojiTransferAccumulator {
  EmojiTransferAccumulator(this.manifest);

  final EmojiTransferManifest manifest;
  final Map<int, Uint8List> _chunks = <int, Uint8List>{};

  double get progress => _chunks.length / manifest.chunkCount;

  bool hasChunk(int index) => _chunks.containsKey(index);

  void add(int index, Uint8List bytes) {
    if (index < 0 || index >= manifest.chunkCount) {
      throw const FormatException('图片分片序号无效');
    }
    final existing = _chunks[index];
    if (existing != null && !_sameBytes(existing, bytes)) {
      throw const FormatException('收到冲突的图片分片');
    }
    _chunks[index] = bytes;
  }

  Future<Uint8List> assemble() async {
    if (_chunks.length != manifest.chunkCount) {
      throw const FormatException('图片分片不完整');
    }
    final result = BytesBuilder(copy: false);
    for (var index = 0; index < manifest.chunkCount; index++) {
      final bytes = _chunks[index];
      if (bytes == null) throw const FormatException('图片分片不完整');
      result.add(bytes);
    }
    final data = result.toBytes();
    if (data.length != manifest.byteLength ||
        await EmojiTransferCodec.checksum(data) != manifest.checksum) {
      throw const FormatException('图片完整性校验失败');
    }
    return data;
  }

  static bool _sameBytes(Uint8List first, Uint8List second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}
