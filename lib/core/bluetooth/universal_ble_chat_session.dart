import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'ble_protocol.dart';

/// 中心端 GATT 会话：负责固定 UUID 下的数据收发、分帧和通知重组。
/// 认证与端到端加密将在安全阶段接入本会话的数据入口。
class UniversalBleChatSession implements BleChatSession {
  UniversalBleChatSession._(this.deviceId, this._maxFrameSize);

  final String deviceId;
  final int _maxFrameSize;
  final StreamController<List<int>> _incomingController =
      StreamController<List<int>>.broadcast();
  StreamSubscription<dynamic>? _notificationListener;
  CharacteristicSubscription? _subscription;

  int? _frameTotal;
  int? _frameTransferId;
  final Map<int, List<int>> _frames = <int, List<int>>{};
  Future<void> _sendQueue = Future<void>.value();
  bool _closed = false;

  static const _maximumWriteAttempts = 5;
  static const _writeTimeout = Duration(seconds: 2);

  /// 发现服务并打开会话。通知订阅由 [subscribeNotifications] 单独启动，
  /// 以便连接请求先通过写入特征抵达外围端。
  static Future<UniversalBleChatSession> open(
    String deviceId, {
    int maxFrameSize = BleFrameCodec.payloadSize,
  }) async {
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

    final session = UniversalBleChatSession._(deviceId, maxFrameSize);
    session._notificationListener = subscription.listen(
      (value) => session._handleFrame(value),
    );
    session._subscription = subscription;
    return session;
  }

  /// 建立通知订阅以接收外围端回包。
  Future<void> subscribeNotifications() async {
    _ensureOpen();
    final subscription = _subscription;
    if (subscription == null) {
      throw StateError('静域 BLE 通知订阅尚未准备好');
    }
    // 部分 Android 设备会在 discoverServices 后立即进行连接参数协商。
    // 此时写 CCCD 描述符会返回 WRITE_REQUEST_BUSY，先等待链路稳定。
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await _subscribeWithRetry(subscription);
  }

  Future<void> _subscribeWithRetry(
    CharacteristicSubscription subscription,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await subscription.subscribe();
        return;
      } on Object catch (error) {
        lastError = error;
        final message = error.toString();
        final isTemporarilyBusy =
            message.contains('writeRequestBusy') ||
            message.contains('WRITE_REQUEST_BUSY');
        if (!isTemporarilyBusy || attempt == 5) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 500 + 250 * attempt));
      }
    }
    throw StateError('通知订阅失败：$lastError');
  }

  @override
  Stream<List<int>> get incomingBytes => _incomingController.stream;

  @override
  Future<void> send(BlePacket packet) {
    _ensureOpen();
    final task = _sendQueue.then((_) => _sendFrames(packet));
    // 后续发送不能因一条失败消息永久停在错误 Future 上。
    _sendQueue = task.then<void>((_) {}, onError: (_, _) {});
    return task;
  }

  Future<void> _sendFrames(BlePacket packet) async {
    final frames = BleFrameCodec.split(
      packet.encode(),
      maxFrameSize: _maxFrameSize,
    );
    // 所有帧使用有响应写入，长消息的速度来自协商到的更大 MTU。实测当前
    // Android 组合会丢弃无响应长写入，因此优先保证逐条消息可靠送达。
    for (var index = 0; index < frames.length; index++) {
      await _writeFrameWithRetry(frames[index]);
    }
  }

  /// Android 在连续有响应写入时可能短暂报告繁忙。该错误通常不代表链路
  /// 已断开，重试当前帧可避免整张图片在接近完成时直接失败。
  Future<void> _writeFrameWithRetry(Uint8List frame) async {
    for (var attempt = 0; attempt < _maximumWriteAttempts; attempt++) {
      try {
        await UniversalBle.write(
          deviceId,
          SilentDomainBleUuid.service,
          SilentDomainBleUuid.writeCharacteristic,
          frame,
          withoutResponse: false,
        ).timeout(_writeTimeout);
        return;
      } on Object {
        if (attempt == _maximumWriteAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 60 * (attempt + 1)));
      }
    }
  }

  void _handleFrame(Uint8List value) {
    if (_closed) return;
    try {
      final frame = BleFrameCodec.decode(value);
      if (_frameTransferId != frame.transferId || _frameTotal != frame.total) {
        _frameTotal = frame.total;
        _frameTransferId = frame.transferId;
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
      _frameTransferId = null;
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
