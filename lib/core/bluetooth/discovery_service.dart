import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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

  Future<void> dispose();
}

/// BLE 发现实现。真实连接和 GATT 通信将在后续子阶段加入。
class BleDiscoveryService implements DiscoveryService {
  BleDiscoveryService() {
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      final devices = <String, NearbyDevice>{};
      for (final result in results) {
        final name = result.device.platformName.trim();
        if (name.isEmpty) continue;
        devices[result.device.remoteId.str] = NearbyDevice(
          id: result.device.remoteId.str,
          name: name,
          rssi: result.rssi,
        );
      }
      _devicesController.add(devices.values.toList());
    });
  }

  final _devicesController = StreamController<List<NearbyDevice>>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  Stream<List<NearbyDevice>> get devices => _devicesController.stream;

  @override
  Future<void> startScan() async {
    if (!await FlutterBluePlus.isSupported) {
      throw StateError('当前设备不支持蓝牙低功耗扫描');
    }
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      throw StateError('请先打开蓝牙');
    }
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

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
  Future<void> dispose() => _controller.close();
}
