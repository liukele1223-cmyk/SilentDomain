import 'dart:async';
import 'dart:convert';

import 'package:universal_ble/universal_ble.dart';

import 'ble_protocol.dart';
import 'universal_ble_chat_session.dart';
import '../security/device_identity_service.dart';

typedef BleMtuRequester = Future<int> Function();

/// MTU 协商只做有限次数尝试；失败时始终回退到兼容的 20 字节帧。
Future<int> negotiateBleMaximumFrameSize(
  BleMtuRequester requestMtu, {
  int maximumAttempts = 2,
  Duration retryDelay = const Duration(milliseconds: 350),
}) async {
  for (var attempt = 0; attempt < maximumAttempts; attempt++) {
    try {
      final mtu = await requestMtu();
      return BleFrameCodec.normalizeMaximumFrameSize(mtu - 3);
    } on Object {
      if (attempt == maximumAttempts - 1) break;
      await Future<void>.delayed(retryDelay);
    }
  }
  return BleFrameCodec.payloadSize;
}

class NearbyDevice {
  const NearbyDevice({required this.id, required this.name, this.rssi});

  final String id;
  final String name;
  final int? rssi;
}

abstract interface class DiscoveryService {
  Stream<List<NearbyDevice>> get devices;

  Stream<BlePacket> get incomingPackets;

  bool get isConnected;

  int get maximumFrameSize;

  Future<bool> acquireHighPerformanceConnection();

  Future<void> releaseHighPerformanceConnection({required bool acquired});

  Future<void> startScan();

  Future<void> stopScan();

  Future<void> connect(NearbyDevice device, {required String verificationCode});

  Future<void> disconnect();

  Future<void> sendPacket(BlePacket packet);

  Future<void> dispose();
}

/// BLE 发现与连接实现，使用 BSD 3-Clause 许可的 Universal BLE。
class BleDiscoveryService implements DiscoveryService {
  BleDiscoveryService({SessionSecurityRegistry? securityRegistry})
    : _securityRegistry = securityRegistry ?? SessionSecurityRegistry() {
    _scanSubscription = UniversalBle.scanStream.listen((device) {
      final name = (device.name ?? device.rawName ?? '').trim();
      // 仅显示广播静域专用服务 UUID 的设备。真正的服务 UUID 现在会被
      // Android 外围端写入广播包，因此手环和耳机不会出现在结果中。
      final isSilentDomain = device.services.any(
        (uuid) =>
            BleUuidParser.compareStrings(uuid, SilentDomainBleUuid.service),
      );
      if (!isSilentDomain) return;
      _discoveredDevices[device.deviceId] = NearbyDevice(
        id: device.deviceId,
        name: name.isEmpty ? '静域设备' : name,
        rssi: device.rssi,
      );
      final devices = _discoveredDevices.values.toList()
        ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
      _devicesController.add(List.unmodifiable(devices));
    });
  }

  final _devicesController = StreamController<List<NearbyDevice>>.broadcast();
  final _incomingPacketsController = StreamController<BlePacket>.broadcast();
  final SessionSecurityRegistry _securityRegistry;
  final Map<String, NearbyDevice> _discoveredDevices = <String, NearbyDevice>{};
  StreamSubscription<BleDevice>? _scanSubscription;
  Timer? _scanTimer;
  String? _connectedDeviceId;
  UniversalBleChatSession? _chatSession;
  StreamSubscription<List<int>>? _incomingSubscription;
  int _highPerformanceLeaseCount = 0;
  Future<void>? _highPerformanceActivation;

  @override
  Stream<List<NearbyDevice>> get devices => _devicesController.stream;

  @override
  Stream<BlePacket> get incomingPackets => _incomingPacketsController.stream;

  @override
  bool get isConnected => _chatSession != null;

  @override
  int get maximumFrameSize =>
      _chatSession?.maximumFrameSize ?? BleFrameCodec.payloadSize;

  @override
  Future<bool> acquireHighPerformanceConnection() async {
    final deviceId = _connectedDeviceId;
    if (deviceId == null || _chatSession == null) return false;
    _highPerformanceLeaseCount++;
    final activation = _highPerformanceActivation ??=
        _activateHighPerformanceConnection(deviceId);
    try {
      await activation;
      return true;
    } on Object {
      if (_highPerformanceLeaseCount > 0) _highPerformanceLeaseCount--;
      if (_highPerformanceLeaseCount == 0 &&
          identical(_highPerformanceActivation, activation)) {
        _highPerformanceActivation = null;
      }
      return false;
    }
  }

  Future<void> _activateHighPerformanceConnection(String deviceId) async {
    await UniversalBle.requestConnectionPriority(
      deviceId,
      BleConnectionPriority.highPerformance,
      timeout: const Duration(seconds: 2),
    );
    // 请求返回表示本机蓝牙栈已接受；给连接参数更新留出一个短窗口。
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Future<void> releaseHighPerformanceConnection({
    required bool acquired,
  }) async {
    if (!acquired || _highPerformanceLeaseCount == 0) return;
    _highPerformanceLeaseCount--;
    if (_highPerformanceLeaseCount > 0) return;
    _highPerformanceActivation = null;
    final deviceId = _connectedDeviceId;
    if (deviceId == null || _chatSession == null) return;
    try {
      await UniversalBle.requestConnectionPriority(
        deviceId,
        BleConnectionPriority.balanced,
        timeout: const Duration(seconds: 2),
      );
    } on Object {
      // 恢复平衡模式是节能清理，不得反向改变已完成的消息结果。
    }
  }

  @override
  Future<void> startScan() async {
    await _ensurePermissions();
    final state = await UniversalBle.getBluetoothAvailabilityState();
    if (state != AvailabilityState.poweredOn) {
      throw StateError('请先打开蓝牙');
    }
    _discoveredDevices.clear();
    _devicesController.add(const []);
    await UniversalBle.startScan(
      scanFilter: ScanFilter(withServices: [SilentDomainBleUuid.service]),
    );
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 12), stopScan);
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await UniversalBle.stopScan();
  }

  @override
  Future<void> connect(
    NearbyDevice device, {
    required String verificationCode,
  }) async {
    await _ensurePermissions();
    await UniversalBle.connect(device.id, timeout: const Duration(seconds: 15));
    UniversalBleChatSession? session;
    try {
      // 先打开写入通道，将验证码请求送达广播端；通知订阅可随后建立。
      final maxFrameSize = await _negotiateMaxFrameSize(device.id);
      session = await UniversalBleChatSession.open(
        device.id,
        maxFrameSize: maxFrameSize,
      );
      final offer = await _securityRegistry.createInitiatorOffer(
        verificationCode,
      );
      final acknowledgement = session.incomingBytes
          .map(_decodePacketOrNull)
          .where((packet) => packet != null)
          .cast<BlePacket>()
          .firstWhere(
            (packet) =>
                packet.type == BlePacketType.acknowledgement &&
                packet.id == 'pairing-request',
          )
          .timeout(const Duration(seconds: 30));
      await session.send(
        BlePacket(
          type: BlePacketType.hello,
          id: 'pairing-request',
          payload: jsonEncode(offer.toJson()),
        ),
      );
      await session.subscribeNotifications();
      final response = await acknowledgement;
      await _securityRegistry.completeInitiator(
        expectedVerificationCode: verificationCode,
        encodedResponse: response.payload,
      );
      _chatSession = session;
      _connectedDeviceId = device.id;
      _incomingSubscription = session.incomingBytes.listen((bytes) {
        final packet = _decodePacketOrNull(bytes);
        if (packet != null) _incomingPacketsController.add(packet);
      });
    } on Object {
      _securityRegistry.clearCentralSession();
      await session?.close();
      await UniversalBle.disconnect(device.id);
      rethrow;
    }
  }

  BlePacket? _decodePacketOrNull(List<int> bytes) {
    try {
      return BlePacket.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  Future<int> _negotiateMaxFrameSize(String deviceId) async {
    return negotiateBleMaximumFrameSize(
      () => UniversalBle.requestMtu(
        deviceId,
        247,
        timeout: const Duration(seconds: 4),
      ),
    );
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
    _highPerformanceLeaseCount = 0;
    _highPerformanceActivation = null;
    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    await _chatSession?.close();
    _chatSession = null;
    _securityRegistry.clearCentralSession();
    if (id != null) await UniversalBle.disconnect(id);
    _connectedDeviceId = null;
  }

  @override
  Future<void> sendPacket(BlePacket packet) async {
    final session = _chatSession;
    if (session == null) throw StateError('尚未建立静域通信通道');
    await session.send(packet);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    _scanTimer?.cancel();
    await _scanSubscription?.cancel();
    await _devicesController.close();
    await _incomingPacketsController.close();
  }
}

/// 测试和桌面预览使用的替代实现，不访问真实蓝牙硬件。
class FakeDiscoveryService implements DiscoveryService {
  FakeDiscoveryService({List<NearbyDevice>? initialDevices})
    : _devices = [...?initialDevices];

  final List<NearbyDevice> _devices;
  final _controller = StreamController<List<NearbyDevice>>.broadcast();
  final _incomingController = StreamController<BlePacket>.broadcast();
  bool _connected = false;

  @override
  Stream<List<NearbyDevice>> get devices => _controller.stream;

  @override
  Stream<BlePacket> get incomingPackets => _incomingController.stream;

  @override
  bool get isConnected => _connected;

  @override
  int get maximumFrameSize => BleFrameCodec.payloadSize;

  @override
  Future<bool> acquireHighPerformanceConnection() async => false;

  @override
  Future<void> releaseHighPerformanceConnection({
    required bool acquired,
  }) async {}

  @override
  Future<void> startScan() async {
    _controller.add(List.unmodifiable(_devices));
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(
    NearbyDevice device, {
    required String verificationCode,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<void> sendPacket(BlePacket packet) async {
    _incomingController.add(packet);
  }

  /// 测试辅助入口：模拟另一台设备送达的数据包。
  void emitIncomingPacket(BlePacket packet) {
    _incomingController.add(packet);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
    await _incomingController.close();
  }
}
