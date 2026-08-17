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
  }

  final StreamController<PeripheralBlePacket> _incomingController =
      StreamController<PeripheralBlePacket>.broadcast();
  final Map<String, _PeripheralFrameBuffer> _buffers =
      <String, _PeripheralFrameBuffer>{};
  final Map<String, List<BlePacket>> _pendingNotifications =
      <String, List<BlePacket>>{};
  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>?
  _subscriptionListener;
  bool _initialized = false;
  bool _closed = false;

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
              properties: [CharacteristicProperty.write],
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

  Future<void> send(String deviceId, BlePacket packet) async {
    _ensureReady();
    final subscribedClients = await UniversalBlePeripheral.getSubscribedClients(
      SilentDomainBleUuid.notifyCharacteristic,
    );
    if (!subscribedClients.contains(deviceId)) {
      _pendingNotifications
          .putIfAbsent(deviceId, () => <BlePacket>[])
          .add(packet);
      return;
    }
    await _sendNow(deviceId, packet);
  }

  Future<void> _sendNow(String deviceId, BlePacket packet) async {
    for (final frame in BleFrameCodec.split(packet.encode())) {
      await UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: SilentDomainBleUuid.notifyCharacteristic,
        deviceId: deviceId,
        value: frame,
      );
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
      unawaited(_sendNow(event.deviceId, packet));
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
    _initialized = false;
  }

  Future<void> dispose() async {
    if (_closed) return;
    await stop();
    UniversalBlePeripheral.setWriteRequestHandlers(null);
    await _subscriptionListener?.cancel();
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
  final Map<int, List<int>> frames = <int, List<int>>{};

  List<int>? add(Frame frame) {
    if (total != frame.total) {
      total = frame.total;
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
