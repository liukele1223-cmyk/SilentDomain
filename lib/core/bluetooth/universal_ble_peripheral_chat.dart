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
  UniversalBlePeripheralChat();

  final StreamController<PeripheralBlePacket> _incomingController =
      StreamController<PeripheralBlePacket>.broadcast();
  final Map<String, _PeripheralFrameBuffer> _buffers =
      <String, _PeripheralFrameBuffer>{};
  bool _initialized = false;
  bool _closed = false;

  Stream<PeripheralBlePacket> get incomingPackets => _incomingController.stream;

  Future<void> initialize({String localName = 'Silent Domain'}) async {
    _ensureOpen();
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

    await UniversalBlePeripheral.startAdvertising(
      services: [SilentDomainBleUuid.service],
      localName: localName,
    );
    _initialized = true;
  }

  Future<void> send(String deviceId, BlePacket packet) async {
    _ensureReady();
    for (final frame in BleFrameCodec.split(packet.encode())) {
      await UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: SilentDomainBleUuid.notifyCharacteristic,
        deviceId: deviceId,
        value: frame,
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
    _initialized = false;
  }

  Future<void> dispose() async {
    if (_closed) return;
    await stop();
    UniversalBlePeripheral.setWriteRequestHandlers(null);
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
