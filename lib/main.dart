import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'core/bluetooth/discovery_service.dart';
import 'core/bluetooth/ble_protocol.dart';
import 'core/bluetooth/universal_ble_peripheral_chat.dart';
import 'core/database/message_store.dart';
import 'core/security/device_identity_service.dart';
import 'features/emoji/emoji_message_content.dart';
import 'features/emoji/emoji_picker_sheet.dart';
import 'features/emoji/emoji_sticker.dart';
import 'features/emoji/emoji_store.dart';
import 'features/theme/theme_settings.dart';
import 'features/theme/theme_picker_sheet.dart';
import 'models/message.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final messageStore = await HiveMessageStore.create();
  final emojiStore = await HiveEmojiStore.create();
  final themeController = ThemeController(await ThemeStore.create());
  await themeController.load();
  final securityRegistry = SessionSecurityRegistry();
  runApp(
    SilentDomainApp(
      messageStore: messageStore,
      emojiStore: emojiStore,
      themeController: themeController,
      discoveryService: BleDiscoveryService(securityRegistry: securityRegistry),
      peripheralService: UniversalBlePeripheralChat(),
      securityRegistry: securityRegistry,
    ),
  );
}

class SilentDomainApp extends StatelessWidget {
  SilentDomainApp({
    super.key,
    MessageStore? messageStore,
    EmojiStore? emojiStore,
    ThemeController? themeController,
    DiscoveryService? discoveryService,
    UniversalBlePeripheralChat? peripheralService,
    SessionSecurityRegistry? securityRegistry,
  }) : messageStore = messageStore ?? MemoryMessageStore(),
       emojiStore = emojiStore ?? MemoryEmojiStore(),
       themeController = themeController ?? ThemeController(null),
       discoveryService = discoveryService ?? FakeDiscoveryService(),
       peripheralService = peripheralService ?? UniversalBlePeripheralChat(),
       securityRegistry = securityRegistry ?? SessionSecurityRegistry();

  final MessageStore messageStore;
  final EmojiStore emojiStore;
  final ThemeController themeController;
  final DiscoveryService discoveryService;
  final UniversalBlePeripheralChat peripheralService;
  final SessionSecurityRegistry securityRegistry;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: '静域',
        debugShowCheckedModeBanner: false,
        theme: SilentDomainThemes.build(themeController.settings),
        themeAnimationDuration: themeController.isPreviewing
            ? Duration.zero
            : const Duration(milliseconds: 260),
        home: SplashPage(
          messageStore: messageStore,
          emojiStore: emojiStore,
          themeController: themeController,
          discoveryService: discoveryService,
          peripheralService: peripheralService,
          securityRegistry: securityRegistry,
        ),
      ),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({
    required this.messageStore,
    required this.emojiStore,
    required this.themeController,
    required this.discoveryService,
    required this.peripheralService,
    required this.securityRegistry,
    super.key,
  });

  final MessageStore messageStore;
  final EmojiStore emojiStore;
  final ThemeController themeController;
  final DiscoveryService discoveryService;
  final UniversalBlePeripheralChat peripheralService;
  final SessionSecurityRegistry securityRegistry;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => AppShell(
              messageStore: widget.messageStore,
              emojiStore: widget.emojiStore,
              themeController: widget.themeController,
              discoveryService: widget.discoveryService,
              peripheralService: widget.peripheralService,
              securityRegistry: widget.securityRegistry,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _DomainMark(size: 88),
              const SizedBox(height: 24),
              Text(
                '静域',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'SILENT DOMAIN',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF718096),
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    required this.messageStore,
    required this.emojiStore,
    required this.themeController,
    required this.discoveryService,
    required this.peripheralService,
    required this.securityRegistry,
    super.key,
  });

  final MessageStore messageStore;
  final EmojiStore emojiStore;
  final ThemeController themeController;
  final DiscoveryService discoveryService;
  final UniversalBlePeripheralChat peripheralService;
  final SessionSecurityRegistry securityRegistry;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        discoveryService: widget.discoveryService,
        peripheralService: widget.peripheralService,
        securityRegistry: widget.securityRegistry,
        onOpenChat: _openChat,
      ),
      ChatPage(
        messageStore: widget.messageStore,
        emojiStore: widget.emojiStore,
        discoveryService: widget.discoveryService,
        peripheralService: widget.peripheralService,
        securityRegistry: widget.securityRegistry,
      ),
      SettingsPage(themeController: widget.themeController),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: '聊天',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }

  void _openChat() {
    setState(() => _index = 1);
  }

  @override
  void dispose() {
    widget.peripheralService.dispose();
    super.dispose();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    required this.discoveryService,
    required this.peripheralService,
    required this.securityRegistry,
    required this.onOpenChat,
    super.key,
  });

  final DiscoveryService discoveryService;
  final UniversalBlePeripheralChat peripheralService;
  final SessionSecurityRegistry securityRegistry;
  final VoidCallback onOpenChat;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _broadcasting = false;
  String? _broadcastError;
  StreamSubscription<PeripheralBlePacket>? _incomingPacketSubscription;
  bool _pairingDialogVisible = false;

  @override
  void initState() {
    super.initState();
    _incomingPacketSubscription = widget.peripheralService.incomingPackets
        .listen((incoming) => unawaited(_handlePairingPacket(incoming)));
  }

  @override
  void dispose() {
    _incomingPacketSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const _DomainMark(size: 42),
                  const SizedBox(width: 12),
                  Text(
                    '静域',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            sliver: SliverToBoxAdapter(
              child: _ConnectionCard(
                onPressed: () => _showConnectionDialog(context),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            sliver: SliverToBoxAdapter(
              child: _BroadcastCard(
                broadcasting: _broadcasting,
                error: _broadcastError,
                onPressed: _toggleBroadcast,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(
              child: Text(
                '最近聊天',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
            sliver: SliverToBoxAdapter(
              child: _EmptyState(
                icon: Icons.forum_outlined,
                title: '还没有聊天',
                subtitle: '连接附近设备后，聊天记录会显示在这里',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectionDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => DeviceDiscoverySheet(
        service: widget.discoveryService,
        onOpenChat: () {
          Navigator.of(sheetContext).pop();
          widget.onOpenChat();
        },
      ),
    );
  }

  Future<void> _toggleBroadcast() async {
    setState(() => _broadcastError = null);
    try {
      if (_broadcasting) {
        await widget.peripheralService.stop();
      } else {
        await widget.peripheralService.initialize();
      }
      if (mounted) setState(() => _broadcasting = !_broadcasting);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _broadcastError = _friendlyBleError(error));
      }
    }
  }

  Future<void> _handlePairingPacket(PeripheralBlePacket incoming) async {
    if (!mounted || _pairingDialogVisible) return;
    BlePacket packet;
    try {
      packet = BlePacket.decode(incoming.bytes);
    } on FormatException {
      return;
    }
    if (packet.type != BlePacketType.hello || packet.id != 'pairing-request') {
      return;
    }

    SecureHandshakePayload offer;
    SecureHandshakePayload response;
    try {
      offer = SecureHandshakePayload.fromJson(
        jsonDecode(packet.payload) as Map<String, dynamic>,
      );
      response = await widget.securityRegistry.acceptInitiatorOffer(
        remoteDeviceId: incoming.deviceId,
        encodedOffer: packet.payload,
      );
    } on Object {
      return;
    }
    if (!mounted) return;

    _pairingDialogVisible = true;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.verified_user_outlined),
          title: const Text('收到连接请求'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请与另一台手机核对验证码'),
              const SizedBox(height: 18),
              Text(
                offer.verificationCode,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认连接'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        await widget.peripheralService.send(
          incoming.deviceId,
          BlePacket(
            type: BlePacketType.acknowledgement,
            id: packet.id,
            payload: jsonEncode(response.toJson()),
          ),
        );
      }
    } finally {
      _pairingDialogVisible = false;
    }
  }

  String _friendlyBleError(Object error) {
    final message = error.toString();
    if (message.contains('permission') || message.contains('Permission')) {
      return '需要“附近的设备”权限才能开始广播，请在系统提示中允许。';
    }
    if (message.contains('not support') || message.contains('不支持')) {
      return '当前设备不支持蓝牙低功耗广播。';
    }
    return '广播启动失败，请确认蓝牙已开启后重试。';
  }
}

class _BroadcastCard extends StatelessWidget {
  const _BroadcastCard({
    required this.broadcasting,
    required this.error,
    required this.onPressed,
  });

  final bool broadcasting;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: broadcasting ? const Color(0xFFE5F4EC) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  broadcasting
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_tethering_outlined,
                  color: broadcasting
                      ? const Color(0xFF2D8A59)
                      : const Color(0xFF477AA9),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    broadcasting ? '正在广播，可被附近设备发现' : '让附近设备发现我',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: Color(0xFFD94A4A))),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(
                broadcasting ? Icons.stop_rounded : Icons.bluetooth_rounded,
              ),
              label: Text(broadcasting ? '停止广播' : '开始广播'),
            ),
          ],
        ),
      ),
    );
  }
}

class DeviceDiscoverySheet extends StatefulWidget {
  const DeviceDiscoverySheet({
    required this.service,
    required this.onOpenChat,
    super.key,
  });

  final DiscoveryService service;
  final VoidCallback onOpenChat;

  @override
  State<DeviceDiscoverySheet> createState() => _DeviceDiscoverySheetState();
}

class _DeviceDiscoverySheetState extends State<DeviceDiscoverySheet> {
  bool _isScanning = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: StreamBuilder<List<NearbyDevice>>(
          stream: widget.service.devices,
          initialData: const [],
          builder: (context, snapshot) {
            final devices = snapshot.data ?? const <NearbyDevice>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('发现附近设备', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('静域使用蓝牙低功耗发现附近设备，不需要互联网。'),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFD94A4A)),
                  ),
                ],
                const SizedBox(height: 18),
                if (_isScanning)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('正在搜索附近的静域设备…'),
                  ),
                if (devices.isEmpty && !_isScanning)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text('暂未发现设备'),
                  ),
                for (final device in devices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFDDEBFA),
                      child: Icon(
                        Icons.phone_android_rounded,
                        color: Color(0xFF477AA9),
                      ),
                    ),
                    title: Text(device.name),
                    subtitle: Text('信号强度 ${device.rssi ?? '--'} dBm'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final shouldOpenChat = await Navigator.of(context)
                          .push<bool>(
                            MaterialPageRoute<bool>(
                              builder: (_) => ConnectionRequestPage(
                                device: device,
                                service: widget.service,
                              ),
                            ),
                          );
                      if (shouldOpenChat == true && mounted) {
                        widget.onOpenChat();
                      }
                    },
                  ),
                FilledButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching_rounded),
                  label: Text(_isScanning ? '正在搜索…' : '开始搜索'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _error = null;
    });
    try {
      await widget.service.startScan();
      // 扫描服务会在 12 秒后停止。保持界面中的搜索状态，避免按钮闪回。
      await Future<void>.delayed(const Duration(seconds: 12));
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }
}

class ConnectionRequestPage extends StatefulWidget {
  const ConnectionRequestPage({
    required this.device,
    required this.service,
    super.key,
  });

  final NearbyDevice device;
  final DiscoveryService service;

  @override
  State<ConnectionRequestPage> createState() => _ConnectionRequestPageState();
}

class _ConnectionRequestPageState extends State<ConnectionRequestPage> {
  bool _isConnecting = false;
  bool _connected = false;
  String? _error;

  late final String _verificationCode =
      (Random.secure().nextInt(900000) + 100000).toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('连接确认')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 56,
                color: Color(0xFF477AA9),
              ),
              const SizedBox(height: 20),
              Text(
                widget.device.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text('请确认两台设备显示的验证码一致', textAlign: TextAlign.center),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  _verificationCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 8,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFD94A4A)),
                ),
              ],
              const Spacer(),
              if (_connected)
                const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: Text(
                    '两台设备已确认，静域通信通道已建立。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF2E7D5B)),
                  ),
                ),
              FilledButton.icon(
                onPressed: _isConnecting
                    ? null
                    : _connected
                    ? _openChat
                    : _confirmConnection,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _connected
                            ? Icons.chat_bubble_rounded
                            : Icons.link_rounded,
                      ),
                label: Text(
                  _connected
                      ? '开始聊天'
                      : _isConnecting
                      ? '正在连接…'
                      : '确认并连接',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmConnection() async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });
    try {
      await widget.service.connect(
        widget.device,
        verificationCode: _verificationCode,
      );
      if (mounted) setState(() => _connected = true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyConnectionError(error));
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _openChat() {
    Navigator.of(context).pop(true);
  }

  String _friendlyConnectionError(Object error) {
    final message = error.toString();
    if (message.contains('writeRequestBusy') ||
        message.contains('WRITE_REQUEST_BUSY')) {
      return '另一台设备正在准备通信通道，请稍后重试。';
    }
    if (message.contains('TimeoutException')) {
      return '等待另一台设备确认超时，请重新发起连接。';
    }
    return message.replaceFirst('Bad state: ', '');
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.messageStore,
    required this.emojiStore,
    required this.discoveryService,
    required this.peripheralService,
    required this.securityRegistry,
    super.key,
  });

  final MessageStore messageStore;
  final EmojiStore emojiStore;
  final DiscoveryService discoveryService;
  final UniversalBlePeripheralChat peripheralService;
  final SessionSecurityRegistry securityRegistry;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _messages = <Message>[];
  bool _isLoading = true;
  StreamSubscription<BlePacket>? _centralPackets;
  StreamSubscription<PeripheralBlePacket>? _peripheralPackets;
  String? _peripheralPeerId;
  final Set<String> _disconnectedPeripheralPeers = <String>{};

  @override
  void initState() {
    super.initState();
    _centralPackets = widget.discoveryService.incomingPackets.listen(
      (packet) => unawaited(
        _handleIncoming(
          packet,
          decrypt: widget.securityRegistry.decryptFromCentral,
          acknowledge: (acknowledgement) async {
            await widget.discoveryService.sendPacket(
              await widget.securityRegistry.encryptForCentral(acknowledgement),
            );
          },
        ),
      ),
    );
    _peripheralPackets = widget.peripheralService.incomingPackets.listen((
      incoming,
    ) {
      try {
        final packet = BlePacket.decode(incoming.bytes);
        final isPairingRequest =
            packet.type == BlePacketType.hello &&
            packet.id == 'pairing-request';
        if (_disconnectedPeripheralPeers.contains(incoming.deviceId) &&
            !isPairingRequest) {
          return;
        }
        if (isPairingRequest) {
          _disconnectedPeripheralPeers.remove(incoming.deviceId);
        }
        _setPeripheralPeer(incoming.deviceId);
        unawaited(
          _handleIncoming(
            packet,
            decrypt: (encrypted) => widget.securityRegistry
                .decryptFromPeripheral(incoming.deviceId, encrypted),
            acknowledge: (acknowledgement) async {
              await widget.peripheralService.send(
                incoming.deviceId,
                await widget.securityRegistry.encryptForPeripheral(
                  incoming.deviceId,
                  acknowledgement,
                ),
              );
            },
          ),
        );
      } on FormatException {
        // 忽略不属于静域协议的损坏包。
      }
    });
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final messages = await widget.messageStore.loadMessages();
    if (messages.isEmpty) {
      messages.addAll([
        Message(
          id: 'welcome',
          sender: 'nearby-device',
          content: '欢迎来到静域。',
          timestamp: DateTime(2026, 1, 1, 9, 41),
        ),
        Message(
          id: 'offline',
          sender: 'self',
          content: '这里不需要互联网。',
          timestamp: DateTime(2026, 1, 1, 9, 42),
        ),
        Message(
          id: 'failed-demo',
          sender: 'self',
          content: '这是一条发送失败的消息',
          timestamp: DateTime(2026, 1, 1, 9, 43),
          status: MessageStatus.failed,
        ),
      ]);
      for (final message in messages) {
        await widget.messageStore.saveMessage(message);
      }
    }
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(messages);
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _centralPackets?.cancel();
    _peripheralPackets?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFDDEBFA),
                  child: Icon(
                    Icons.devices_other_rounded,
                    color: Color(0xFF477AA9),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '附近设备',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isConnected ? '已连接 · 蓝牙离线通道' : '等待连接 · 离线',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF75849A),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_ChatMenuAction>(
                  tooltip: '聊天选项',
                  onSelected: (action) {
                    if (action == _ChatMenuAction.disconnect) {
                      unawaited(_disconnect());
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<_ChatMenuAction>(
                      value: _ChatMenuAction.disconnect,
                      enabled: _isConnected,
                      child: const Row(
                        children: [
                          Icon(
                            Icons.link_off_rounded,
                            color: Color(0xFFD94A4A),
                          ),
                          SizedBox(width: 12),
                          Text('断开连接'),
                        ],
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) => _MessageBubble(
                      message: _messages[index],
                      emojiStore: widget.emojiStore,
                      onRetry: () => _retryMessage(_messages[index]),
                    ),
                  ),
          ),
          _Composer(
            controller: _controller,
            onSend: _sendMessage,
            onOpenEmoji: _showEmojiPicker,
          ),
        ],
      ),
    );
  }

  bool get _isConnected =>
      widget.discoveryService.isConnected || _peripheralPeerId != null;

  void _setPeripheralPeer(String deviceId) {
    if (_peripheralPeerId == deviceId) return;
    if (mounted) {
      setState(() => _peripheralPeerId = deviceId);
    } else {
      _peripheralPeerId = deviceId;
    }
  }

  Future<void> _disconnect() async {
    final centralConnected = widget.discoveryService.isConnected;
    final peripheralPeerId = _peripheralPeerId;
    if (!centralConnected && peripheralPeerId == null) return;

    const disconnectPacket = BlePacket(
      type: BlePacketType.hello,
      id: 'disconnect-request',
      payload: '',
    );
    try {
      if (centralConnected) {
        // 先通知对端更新界面，再关闭本机的 GATT 连接。
        try {
          await widget.discoveryService.sendPacket(
            await widget.securityRegistry.encryptForCentral(disconnectPacket),
          );
        } finally {
          await widget.discoveryService.disconnect();
          widget.securityRegistry.clearCentralSession();
        }
      }
      if (peripheralPeerId != null) {
        try {
          await widget.peripheralService.send(
            peripheralPeerId,
            await widget.securityRegistry.encryptForPeripheral(
              peripheralPeerId,
              disconnectPacket,
            ),
          );
        } finally {
          _disconnectedPeripheralPeers.add(peripheralPeerId);
          widget.securityRegistry.clearPeripheralSession(peripheralPeerId);
        }
      }
      if (mounted) {
        setState(() => _peripheralPeerId = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已断开当前静域连接')));
      }
    } on Object {
      if (mounted) {
        setState(() => _peripheralPeerId = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('连接已在本机断开')));
      }
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final message = Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sender: 'self',
      content: text,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );
    setState(() {
      _messages.add(message);
      _controller.clear();
    });
    unawaited(widget.messageStore.saveMessage(message));

    unawaited(_transmit(message));
  }

  Future<void> _showEmojiPicker() async {
    final sticker = await showModalBottomSheet<EmojiSticker>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EmojiPickerSheet(store: widget.emojiStore),
    );
    if (sticker == null || !mounted) return;
    final message = Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sender: 'self',
      content: '[表情：${sticker.name}]',
      emojiId: sticker.id,
      emojiName: sticker.name,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );
    setState(() => _messages.add(message));
    unawaited(widget.messageStore.saveMessage(message));
    unawaited(_transmit(message));
  }

  void _retryMessage(Message message) {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return;
    setState(() {
      _messages[index] = message.copyWith(status: MessageStatus.sending);
    });
    unawaited(widget.messageStore.saveMessage(_messages[index]));
    unawaited(_transmit(_messages[index]));
  }

  Future<void> _transmit(Message message) async {
    try {
      final packet = BlePacket.fromMessage(message);
      if (widget.discoveryService.isConnected) {
        await widget.discoveryService.sendPacket(
          await widget.securityRegistry.encryptForCentral(packet),
        );
      } else {
        final peerId = _peripheralPeerId;
        if (peerId == null) throw StateError('尚未建立静域通信通道');
        await widget.peripheralService.send(
          peerId,
          await widget.securityRegistry.encryptForPeripheral(peerId, packet),
        );
      }
      await Future<void>.delayed(const Duration(seconds: 12));
      _markFailedIfPending(message.id);
    } on Object {
      _markFailedIfPending(message.id);
    }
  }

  Future<void> _handleIncoming(
    BlePacket packet, {
    required Future<BlePacket> Function(BlePacket encrypted) decrypt,
    required Future<void> Function(BlePacket acknowledgement) acknowledge,
  }) async {
    if (packet.type == BlePacketType.encrypted) {
      try {
        final decrypted = await decrypt(packet);
        await _handleIncoming(
          decrypted,
          decrypt: decrypt,
          acknowledge: acknowledge,
        );
      } on Object {
        // 认证失败或不属于当前会话的密文一律丢弃。
      }
      return;
    }
    if (packet.type == BlePacketType.hello &&
        packet.id == 'disconnect-request') {
      await _handleRemoteDisconnect();
      return;
    }
    if (packet.type == BlePacketType.acknowledgement &&
        packet.payload == 'delivered') {
      _markSuccess(packet.id);
      return;
    }
    if (packet.type != BlePacketType.message) return;
    try {
      final payload = jsonDecode(packet.payload) as Map<String, dynamic>;
      final message = Message(
        id: packet.id,
        sender: 'nearby-device',
        content: payload['content'] as String,
        timestamp: DateTime.parse(payload['timestamp'] as String),
        emojiId: payload['emojiId'] as String?,
        emojiName: payload['emojiName'] as String?,
      );
      if (mounted && !_messages.any((item) => item.id == message.id)) {
        setState(() => _messages.add(message));
        await widget.messageStore.saveMessage(message);
      }
      await acknowledge(
        BlePacket(
          type: BlePacketType.acknowledgement,
          id: packet.id,
          payload: 'delivered',
        ),
      );
    } on FormatException {
      // 丢弃无效消息包，保持会话可用。
    }
  }

  Future<void> _handleRemoteDisconnect() async {
    final peerId = _peripheralPeerId;
    if (peerId != null) _disconnectedPeripheralPeers.add(peerId);
    if (widget.discoveryService.isConnected) {
      await widget.discoveryService.disconnect();
      widget.securityRegistry.clearCentralSession();
    }
    if (peerId != null) widget.securityRegistry.clearPeripheralSession(peerId);
    if (!mounted) return;
    setState(() => _peripheralPeerId = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('对方已断开连接')));
  }

  void _markSuccess(String id) {
    _updateMessageStatus(id, MessageStatus.success);
  }

  void _markFailedIfPending(String id) {
    final message = _messages.cast<Message?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (message?.status == MessageStatus.sending) {
      _updateMessageStatus(id, MessageStatus.failed);
    }
  }

  void _updateMessageStatus(String id, MessageStatus status) {
    if (!mounted) return;
    final index = _messages.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final updated = _messages[index].copyWith(status: status);
    setState(() => _messages[index] = updated);
    unawaited(widget.messageStore.saveMessage(updated));
  }
}

enum _ChatMenuAction { disconnect }

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.themeController, super.key});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          children: [
            Text(
              '设置',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              title: '外观',
              children: [
                _SettingsTile(
                  icon: Icons.palette_outlined,
                  title: '主题',
                  subtitle: SilentDomainThemes.labelFor(
                    themeController.settings.mode,
                  ),
                  onTap: () => _showThemePicker(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _SettingsSection(
              title: '隐私与安全',
              children: [
                _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  title: '本地安全',
                  subtitle: '数据只保存在本机',
                ),
                _SettingsTile(
                  icon: Icons.key_outlined,
                  title: '设备身份',
                  subtitle: '尚未建立连接',
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _SettingsSection(
              title: '关于',
              children: [
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: '关于静域',
                  subtitle: 'Silent Domain · 0.1.0',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ThemePickerSheet(controller: themeController),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.wifi_tethering_rounded,
              color: Theme.of(context).colorScheme.onPrimary,
              size: 30,
            ),
            const SizedBox(height: 18),
            Text(
              '连接附近设备',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '在没有网络的地方，也能保持联系。',
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer,
              ),
              child: const Text('发现设备'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DomainMark extends StatelessWidget {
  const _DomainMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Icon(
        Icons.all_inclusive_rounded,
        color: Theme.of(context).colorScheme.onPrimary,
        size: size * .55,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF9BAFC3)),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF75849A)),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onOpenEmoji,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onOpenEmoji;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: onOpenEmoji,
            tooltip: '表情',
            icon: const Icon(Icons.emoji_emotions_outlined),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: '写下消息…',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: onSend,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.emojiStore,
    required this.onRetry,
  });

  final Message message;
  final EmojiStore emojiStore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final mine = message.sender == 'self';
    final time =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.emojiId == null)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 290),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: mine ? const Color(0xFF17324F) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: mine ? Colors.white : const Color(0xFF24354A),
                        height: 1.35,
                      ),
                    ),
                  )
                else
                  EmojiMessageContent(
                    emojiId: message.emojiId!,
                    emojiName: message.emojiName ?? '表情',
                    emojiStore: emojiStore,
                    color: mine ? Colors.white : const Color(0xFF24354A),
                  ),
                if (mine && message.status == MessageStatus.failed)
                  IconButton(
                    onPressed: onRetry,
                    tooltip: '重新发送',
                    icon: const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFD94A4A),
                    ),
                  ),
                if (mine && message.status == MessageStatus.sending)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              time,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8897A8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: const Color(0xFF718096)),
          ),
        ),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
