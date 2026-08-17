import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'ble_protocol.dart';

/// 中心端 GATT 会话：负责固定 UUID 下的数据收发、分帧和通知重组。
/// 认证与端到端加密将在安全阶段接入本会话的数据入口。
class UniversalBleChatSession implements BleChatSession {
  UniversalBleChatSession._(this.deviceId);

  final String deviceId;
  final StreamController<List<int>> _incomingController =
      StreamController<List<int>>.broadcast();
  StreamSubscription<dynamic>? _notificationListener;

  int? _frameTotal;
  final Map<int, List<int>> _frames = <int, List<int>>{};
  bool _closed = false;

  /// 发现服务、校验特征并订阅通知，返回可用于聊天的会话。
  static Future<UniversalBleChatSession> connect(String deviceId) async {
    final services = await UniversalBle.discoverServices(deviceId);
    BleCharacteristic? notifyCharacteristic;

    for (final service in services) {
      if (!BleUuidParser.compareStrings(
        service.uuid,
        SilentDomainBleUuid.service,
      )) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (BleUuidParser.compareStrings(
              characteristic.uuid,
              SilentDomainBleUuid.notifyCharacteristic,
            ) &&
            characteristic.properties.contains(CharacteristicProperty.notify)) {
          notifyCharacteristic = characteristic;
          break;
        }
      }
    }

    if (notifyCharacteristic == null) {
      throw StateError('未找到静域 BLE 通知特征');
    }
    final subscription = notifyCharacteristic.notifications;
    if (!subscription.isSupported) {
      throw StateError('静域 BLE 通知特征不支持通知');
    }

    final session = UniversalBleChatSession._(deviceId);
    session._notificationListener = subscription.listen(
      (value) => session._handleFrame(value),
    );
    await subscription.subscribe();
    return session;
  }

  @override
  Stream<List<int>> get incomingBytes => _incomingController.stream;

  @override
  Future<void> send(BlePacket packet) async {
    _ensureOpen();
    for (final frame in BleFrameCodec.split(packet.encode())) {
      await UniversalBle.write(
        deviceId,
        SilentDomainBleUuid.service,
        SilentDomainBleUuid.writeCharacteristic,
        frame,
        withoutResponse: false,
      );
    }
  }

  void _handleFrame(Uint8List value) {
    if (_closed) return;
    try {
      final frame = BleFrameCodec.decode(value);
      if (_frameTotal != frame.total) {
        _frameTotal = frame.total;
        _frames.clear();
      }
      _frames[frame.index] = frame.payload;
      if (_frames.length != frame.total) return;

      final bytes = <int>[];
      for (var index = 0; index < frame.total; index++) {
        final payload = _frames[index];
        if (payload == null) return;
        bytes.addAll(payload);
      }
      _incomingController.add(bytes);
      _frames.clear();
      _frameTotal = null;
    } on FormatException {
      // 丢弃非法帧，避免单个 BLE 数据包中断整个会话。
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('BLE 会话已关闭');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _notificationListener?.cancel();
    await _incomingController.close();
    await UniversalBle.unsubscribe(
      deviceId,
      SilentDomainBleUuid.service,
      SilentDomainBleUuid.notifyCharacteristic,
    );
  }
}
