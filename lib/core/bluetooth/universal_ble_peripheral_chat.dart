import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'ble_protocol.dart';

class PeripheralBlePacket {
  const PeripheralBlePacket({required this.deviceId, required this.bytes});

  final String deviceId;
  final List<int> bytes;
}

/// 静域 BLE 外围端 GATT 服务。
///
/// 一个外围端可同时接受多个中心端连接；每个中心端独立维护分帧状态。
class UniversalBlePeripheralChat {
  UniversalBlePeripheralChat() {
    _subscriptionListener = UniversalBlePeripheral
        .characteristicSubscriptionStream
        .listen(_flushPendingNotifications);
    _mtuListener = UniversalBlePeripheral.mtuChangedStream.listen((event) {
      // ATT 通知值同样受 MTU - 3 限制，保留默认值作为协商前的安全回退。
      _maxFrameSizes[event.deviceId] = BleFrameCodec.normalizeMaximumFrameSize(
        event.mtu - 3,
      );
    });
  }

  final StreamController<PeripheralBlePacket> _incomingController =
      StreamController<PeripheralBlePacket>.broadcast();
  final Map<String, _PeripheralFrameBuffer> _buffers =
      <String, _PeripheralFrameBuffer>{};
  final Map<String, List<BlePacket>> _pendingNotifications =
      <String, List<BlePacket>>{};
  final Map<String, int> _maxFrameSizes = <String, int>{};
  final Map<String, Future<void>> _notificationQueues =
      <String, Future<void>>{};
  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>?
  _subscriptionListener;
  StreamSubscription<BlePeripheralMtuChanged>? _mtuListener;
  bool _initialized = false;
  bool _closed = false;

  static const _maximumNotificationAttempts = 5;
  static const _notificationTimeout = Duration(seconds: 2);
  // Android 的通知 API 只表示数据已交给本机蓝牙栈，并不代表对端已经取走。
  // 轻微间隔能避免双向图片传输时将其内部缓冲一次性灌满。
  static const _notificationFrameInterval = Duration(milliseconds: 8);

  Stream<PeripheralBlePacket> get incomingPackets => _incomingController.stream;

  Future<void> initialize({String localName = 'Silent Domain'}) async {
    _ensureOpen();
    await _ensurePermissions();
    final capabilities = await UniversalBlePeripheral.getCapabilities();
    if (!capabilities.supportsPeripheralMode) {
      throw UnsupportedError('当前设备不支持 BLE 外围端模式');
    }

    UniversalBlePeripheral.setWriteRequestHandlers(_handleWriteRequest);
    final services = await UniversalBlePeripheral.getServices();
    final hasService = services.any(
      (service) =>
          BleUuidParser.compareStrings(service, SilentDomainBleUuid.service),
    );
    if (!hasService) {
      await UniversalBlePeripheral.addService(
        BlePeripheralService(
          uuid: SilentDomainBleUuid.service,
          primary: true,
          characteristics: [
            BlePeripheralCharacteristic(
              uuid: SilentDomainBleUuid.writeCharacteristic,
              properties: [
                CharacteristicProperty.write,
                CharacteristicProperty.writeWithoutResponse,
              ],
              permissions: [PeripheralAttributePermission.writeable],
            ),
            BlePeripheralCharacteristic(
              uuid: SilentDomainBleUuid.notifyCharacteristic,
              properties: [CharacteristicProperty.notify],
              permissions: [],
            ),
          ],
        ),
      );
    }

    // Android 的主广播包与扫描响应包各最多容纳约 31 字节。把 128 位服务
    // UUID 放在扫描响应包，避免与设备名共存时因超长而异步广播失败。
    final advertisingState = UniversalBlePeripheral.advertisingStateStream
        .firstWhere(
          (event) =>
              event.state == PeripheralAdvertisingState.advertising ||
              event.state == PeripheralAdvertisingState.error,
        )
        .timeout(const Duration(seconds: 5));
    await UniversalBlePeripheral.startAdvertising(
      services: [SilentDomainBleUuid.service],
      localName: localName,
      platformConfig: PeripheralPlatformConfig(
        android: PeripheralAndroidOptions(addServicesInScanResponse: true),
      ),
    );
    final event = await advertisingState;
    if (event.state == PeripheralAdvertisingState.error) {
      throw StateError(event.error ?? '蓝牙广播启动失败');
    }
    _initialized = true;
  }

  Future<void> _ensurePermissions() async {
    if (await UniversalBle.hasPermissions()) {
      return;
    }
    await UniversalBle.requestPermissions();
    if (!await UniversalBle.hasPermissions()) {
      throw StateError('蓝牙权限未授予');
    }
  }

  Future<void> send(String deviceId, BlePacket packet) {
    _ensureReady();
    return _enqueueNotification(deviceId, () async {
      final subscribedClients =
          await UniversalBlePeripheral.getSubscribedClients(
            SilentDomainBleUuid.notifyCharacteristic,
          ).timeout(_notificationTimeout);
      if (!subscribedClients.contains(deviceId)) {
        _pendingNotifications
            .putIfAbsent(deviceId, () => <BlePacket>[])
            .add(packet);
        return;
      }
      await _sendNow(deviceId, packet);
    });
  }

  /// 图片分片、分片确认和最终回执可能同时产生。GATT 通知中的应用帧若
  /// 交错，中心端无法区分两条逻辑消息；每个客户端必须使用同一发送队列。
  Future<void> _enqueueNotification(
    String deviceId,
    Future<void> Function() operation,
  ) {
    final previous = _notificationQueues[deviceId] ?? Future<void>.value();
    final task = previous.then((_) => operation());
    _notificationQueues[deviceId] = task.then<void>((_) {}, onError: (_, _) {});
    return task;
  }

  Future<void> _sendNow(String deviceId, BlePacket packet) async {
    final maxFrameSize = await resolveMaximumFrameSize(deviceId);
    for (final frame in BleFrameCodec.split(
      packet.encode(),
      maxFrameSize: maxFrameSize,
    )) {
      await _notifyFrameWithRetry(deviceId, frame);
      await Future<void>.delayed(_notificationFrameInterval);
    }
  }

  int maximumFrameSizeFor(String deviceId) =>
      _maxFrameSizes[deviceId] ?? BleFrameCodec.payloadSize;

  /// MTU 事件可能先于 Dart 监听器抵达；发送前主动查询一次平台端缓存。
  /// 查询失败时继续使用 20 字节帧，不牺牲既有兼容性和可靠性。
  Future<int> resolveMaximumFrameSize(String deviceId) async {
    final cached = maximumFrameSizeFor(deviceId);
    if (cached > BleFrameCodec.payloadSize) return cached;
    try {
      final maximumNotifyLength =
          await UniversalBlePeripheral.getMaximumNotifyLength(
            deviceId,
          ).timeout(_notificationTimeout);
      if (maximumNotifyLength != null) {
        final resolved = BleFrameCodec.normalizeMaximumFrameSize(
          maximumNotifyLength,
        );
        _maxFrameSizes[deviceId] = resolved;
        return resolved;
      }
    } on Object {
      // 最大通知长度查询是尽力而为；默认帧仍是安全回退。
    }
    return cached;
  }

  /// 通知队列在高频图片传输时同样可能暂时繁忙；只重试当前帧，保持顺序。
  Future<void> _notifyFrameWithRetry(String deviceId, Uint8List frame) async {
    for (var attempt = 0; attempt < _maximumNotificationAttempts; attempt++) {
      try {
        await UniversalBlePeripheral.updateCharacteristicValue(
          characteristicId: SilentDomainBleUuid.notifyCharacteristic,
          deviceId: deviceId,
          value: frame,
        ).timeout(_notificationTimeout);
        return;
      } on Object {
        if (attempt == _maximumNotificationAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 60 * (attempt + 1)));
      }
    }
  }

  void _flushPendingNotifications(
    BlePeripheralCharacteristicSubscriptionChanged event,
  ) {
    if (!event.isSubscribed ||
        !BleUuidParser.compareStrings(
          event.characteristicId,
          SilentDomainBleUuid.notifyCharacteristic,
        )) {
      return;
    }
    final packets = _pendingNotifications.remove(event.deviceId);
    if (packets == null) return;
    for (final packet in packets) {
      unawaited(
        _enqueueNotification(
          event.deviceId,
          () => _sendNow(event.deviceId, packet),
        ),
      );
    }
  }

  PeripheralWriteRequestResult _handleWriteRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    if (!BleUuidParser.compareStrings(
      characteristicId,
      SilentDomainBleUuid.writeCharacteristic,
    )) {
      return PeripheralWriteRequestResult(status: 6);
    }
    if (offset != 0 || value == null || value.isEmpty) {
      return PeripheralWriteRequestResult(status: 13);
    }

    try {
      final frame = BleFrameCodec.decode(value);
      final buffer = _buffers.putIfAbsent(deviceId, _PeripheralFrameBuffer.new);
      final bytes = buffer.add(frame);
      if (bytes != null) {
        _incomingController.add(
          PeripheralBlePacket(deviceId: deviceId, bytes: bytes),
        );
        _buffers.remove(deviceId);
      }
      return PeripheralWriteRequestResult();
    } on FormatException {
      return PeripheralWriteRequestResult(status: 13);
    }
  }

  Future<void> stop() async {
    if (!_initialized) return;
    await UniversalBlePeripheral.stopAdvertising();
    _pendingNotifications.clear();
    _maxFrameSizes.clear();
    _notificationQueues.clear();
    _buffers.clear();
    _initialized = false;
  }

  Future<void> dispose() async {
    if (_closed) return;
    await stop();
    UniversalBlePeripheral.setWriteRequestHandlers(null);
    await _subscriptionListener?.cancel();
    await _mtuListener?.cancel();
    _buffers.clear();
    _closed = true;
    await _incomingController.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('BLE 外围端服务已关闭');
  }

  void _ensureReady() {
    _ensureOpen();
    if (!_initialized) throw StateError('BLE 外围端服务尚未初始化');
  }
}

class _PeripheralFrameBuffer {
  int? total;
  int? transferId;
  final Map<int, List<int>> frames = <int, List<int>>{};

  List<int>? add(Frame frame) {
    if (transferId != frame.transferId || total != frame.total) {
      total = frame.total;
      transferId = frame.transferId;
      frames.clear();
    }
    frames[frame.index] = frame.payload;
    if (frames.length != frame.total) return null;

    final result = <int>[];
    for (var index = 0; index < frame.total; index++) {
      final payload = frames[index];
      if (payload == null) return null;
      result.addAll(payload);
    }
    return result;
  }
}
