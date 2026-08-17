import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../models/message.dart';

abstract final class SilentDomainBleUuid {
  static const service = '7e3a0001-4b9a-4c1d-9e2a-53494c454e54';
  static const writeCharacteristic = '7e3a0002-4b9a-4c1d-9e2a-53494c454e54';
  static const notifyCharacteristic = '7e3a0003-4b9a-4c1d-9e2a-53494c454e54';
}

enum BlePacketType { hello, message, acknowledgement }

class BlePacket {
  const BlePacket({
    required this.type,
    required this.id,
    required this.payload,
    this.sequence = 0,
  });

  final BlePacketType type;
  final String id;
  final String payload;
  final int sequence;

  Uint8List encode() {
    final json = jsonEncode({
      'type': type.name,
      'id': id,
      'payload': payload,
      'sequence': sequence,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  static BlePacket decode(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('BLE packet must be a JSON object');
    }
    return BlePacket(
      type: BlePacketType.values.byName(value['type'] as String),
      id: value['id'] as String,
      payload: value['payload'] as String,
      sequence: value['sequence'] as int? ?? 0,
    );
  }

  static BlePacket fromMessage(Message message) {
    return BlePacket(
      type: BlePacketType.message,
      id: message.id,
      payload: jsonEncode({
        'sender': message.sender,
        'content': message.content,
        'timestamp': message.timestamp.toIso8601String(),
        'status': message.status.name,
      }),
    );
  }
}

/// 将一个 BLE 数据包切成不超过 MTU 友好长度的帧。
abstract final class BleFrameCodec {
  static const payloadSize = 180;
  static const _headerSize = 4;

  static List<Uint8List> split(Uint8List bytes) {
    final chunkSize = payloadSize - _headerSize;
    final total = (bytes.length / chunkSize).ceil().clamp(1, 65535);
    return List.generate(total, (index) {
      final start = index * chunkSize;
      final end = (start + chunkSize).clamp(0, bytes.length);
      final frame = Uint8List(_headerSize + end - start);
      final data = ByteData.sublistView(frame);
      data.setUint16(0, index);
      data.setUint16(2, total);
      frame.setRange(_headerSize, frame.length, bytes, start);
      return frame;
    });
  }

  static Frame decode(Uint8List frame) {
    if (frame.length < _headerSize) {
      throw const FormatException('BLE frame header is incomplete');
    }
    final data = ByteData.sublistView(frame);
    final index = data.getUint16(0);
    final total = data.getUint16(2);
    if (total == 0 || index >= total) {
      throw const FormatException('BLE frame sequence is invalid');
    }
    return Frame(
      index: index,
      total: total,
      payload: frame.sublist(_headerSize),
    );
  }
}

class Frame {
  const Frame({
    required this.index,
    required this.total,
    required this.payload,
  });

  final int index;
  final int total;
  final List<int> payload;
}

abstract interface class BleChatSession {
  Stream<List<int>> get incomingBytes;

  Future<void> send(BlePacket packet);

  Future<void> close();
}

/// 协议层测试实现，后续由 Universal BLE GATT 会话替换。
class MemoryBleChatSession implements BleChatSession {
  final _controller = StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get incomingBytes => _controller.stream;

  @override
  Future<void> send(BlePacket packet) async {
    _controller.add(packet.encode());
  }

  @override
  Future<void> close() => _controller.close();
}
