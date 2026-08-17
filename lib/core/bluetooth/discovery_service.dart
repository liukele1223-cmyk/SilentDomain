import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

class NearbyDevice {
  const NearbyDevice({required this.id, required this.name, this.rssi});

  final String id;
  final String name;
  final int? rssi;
}

abstract interface class DiscoveryService {
  Stream<List<NearbyDevice>> get devices;

  Future<void> startScan();

  Future<void> stopScan();

  Future<void> connect(NearbyDevice device);

  Future<void> disconnect();

  Future<void> dispose();
}

/// BLE 发现与连接实现，使用 BSD 3-Clause 许可的 Universal BLE。
class BleDiscoveryService implements DiscoveryService {
  BleDiscoveryService() {
    _scanSubscription = UniversalBle.scanStream.listen((device) {
      final name = (device.name ?? device.rawName ?? '').trim();
      if (name.isEmpty) return;
      _devicesController.add([
        NearbyDevice(id: device.deviceId, name: name, rssi: device.rssi),
      ]);
    });
  }

  final _devicesController = StreamController<List<NearbyDevice>>.broadcast();
  StreamSubscription<BleDevice>? _scanSubscription;
  String? _connectedDeviceId;

  @override
  Stream<List<NearbyDevice>> get devices => _devicesController.stream;

  @override
  Future<void> startScan() async {
    await _ensurePermissions();
    final state = await UniversalBle.getBluetoothAvailabilityState();
    if (state != AvailabilityState.poweredOn) {
      throw StateError('请先打开蓝牙');
    }
    await UniversalBle.startScan();
    Timer(const Duration(seconds: 12), stopScan);
  }

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(NearbyDevice device) async {
    await _ensurePermissions();
    await UniversalBle.connect(device.id, timeout: const Duration(seconds: 15));
    _connectedDeviceId = device.id;
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

  @override
  Future<void> disconnect() async {
    final id = _connectedDeviceId;
    if (id != null) await UniversalBle.disconnect(id);
    _connectedDeviceId = null;
  }

  @override
  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    await _devicesController.close();
  }
}

/// 测试和桌面预览使用的替代实现，不访问真实蓝牙硬件。
class FakeDiscoveryService implements DiscoveryService {
  FakeDiscoveryService({List<NearbyDevice>? initialDevices})
    : _devices = [...?initialDevices];

  final List<NearbyDevice> _devices;
  final _controller = StreamController<List<NearbyDevice>>.broadcast();

  @override
  Stream<List<NearbyDevice>> get devices => _controller.stream;

  @override
  Future<void> startScan() async {
    _controller.add(List.unmodifiable(_devices));
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(NearbyDevice device) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() => _controller.close();
}
