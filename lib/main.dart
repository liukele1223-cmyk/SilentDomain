import 'dart:async';

import 'package:flutter/material.dart';

import 'core/bluetooth/discovery_service.dart';
import 'core/bluetooth/universal_ble_peripheral_chat.dart';
import 'core/database/message_store.dart';
import 'models/message.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final messageStore = await HiveMessageStore.create();
  runApp(
    SilentDomainApp(
      messageStore: messageStore,
      discoveryService: BleDiscoveryService(),
      peripheralService: UniversalBlePeripheralChat(),
    ),
  );
}

class SilentDomainApp extends StatelessWidget {
  SilentDomainApp({
    super.key,
    MessageStore? messageStore,
    DiscoveryService? discoveryService,
    UniversalBlePeripheralChat? peripheralService,
  }) : messageStore = messageStore ?? MemoryMessageStore(),
       discoveryService = discoveryService ?? FakeDiscoveryService(),
       peripheralService = peripheralService ?? UniversalBlePeripheralChat();

  final MessageStore messageStore;
  final DiscoveryService discoveryService;
  final UniversalBlePeripheralChat peripheralService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '静域',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF78A9D8)),
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F9FC),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: SplashPage(
        messageStore: messageStore,
        discoveryService: discoveryService,
        peripheralService: peripheralService,
      ),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({
    required this.messageStore,
    required this.discoveryService,
    required this.peripheralService,
    super.key,
  });

  final MessageStore messageStore;
  final DiscoveryService discoveryService;
  final UniversalBlePeripheralChat peripheralService;

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
              discoveryService: widget.discoveryService,
              peripheralService: widget.peripheralService,
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
    required this.discoveryService,
    required this.peripheralService,
    super.key,
  });

  final MessageStore messageStore;
  final DiscoveryService discoveryService;
  final UniversalBlePeripheralChat peripheralService;

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
      ),
      ChatPage(messageStore: widget.messageStore),
      const SettingsPage(),
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
    super.key,
  });

  final DiscoveryService discoveryService;
  final UniversalBlePeripheralChat peripheralService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _broadcasting = false;
  String? _broadcastError;

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
      builder: (_) => DeviceDiscoverySheet(service: widget.discoveryService),
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
  const DeviceDiscoverySheet({required this.service, super.key});

  final DiscoveryService service;

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
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ConnectionRequestPage(
                            device: device,
                            service: widget.service,
                          ),
                        ),
                      );
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

  String get _verificationCode {
    final value = widget.device.id.hashCode.abs() % 900000;
    return (value + 100000).toString();
  }

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
                    '连接请求已确认，等待通信通道建立。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF2E7D5B)),
                  ),
                ),
              FilledButton.icon(
                onPressed: _isConnecting || _connected
                    ? null
                    : _confirmConnection,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(
                  _connected
                      ? '已连接'
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
      await widget.service.connect(widget.device);
      if (mounted) setState(() => _connected = true);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({required this.messageStore, super.key});

  final MessageStore messageStore;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _messages = <Message>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '附近设备',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '模拟会话 · 离线',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF75849A),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {},
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
                      onRetry: () => _retryMessage(_messages[index]),
                    ),
                  ),
          ),
          _Composer(controller: _controller, onSend: _sendMessage),
        ],
      ),
    );
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

    Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final index = _messages.indexWhere((item) => item.id == message.id);
      if (index == -1) return;
      setState(() {
        _messages[index] = message.copyWith(
          status: text.contains('失败')
              ? MessageStatus.failed
              : MessageStatus.success,
        );
      });
      unawaited(widget.messageStore.saveMessage(_messages[index]));
    });
  }

  void _retryMessage(Message message) {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return;
    setState(() {
      _messages[index] = message.copyWith(status: MessageStatus.sending);
    });
    unawaited(widget.messageStore.saveMessage(_messages[index]));
    Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final currentIndex = _messages.indexWhere(
        (item) => item.id == message.id,
      );
      if (currentIndex == -1) return;
      setState(() {
        _messages[currentIndex] = _messages[currentIndex].copyWith(
          status: MessageStatus.success,
        );
      });
      unawaited(widget.messageStore.saveMessage(_messages[currentIndex]));
    });
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
          const _SettingsSection(
            title: '外观',
            children: [
              _SettingsTile(
                icon: Icons.palette_outlined,
                title: '主题',
                subtitle: '深空蓝',
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
      color: const Color(0xFF17324F),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.wifi_tethering_rounded,
              color: Color(0xFFBBD9F5),
              size: 30,
            ),
            const SizedBox(height: 18),
            Text(
              '连接附近设备',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '在没有网络的地方，也能保持联系。',
              style: TextStyle(color: Color(0xFFBBD0E5)),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFBBD9F5),
                foregroundColor: const Color(0xFF17324F),
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
        color: const Color(0xFF17324F),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Icon(
        Icons.all_inclusive_rounded,
        color: const Color(0xFFBBD9F5),
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
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.add_circle_outline_rounded),
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
  const _MessageBubble({required this.message, required this.onRetry});

  final Message message;
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
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF477AA9)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () {},
    );
  }
}
