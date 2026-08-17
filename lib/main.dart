import 'dart:async';

import 'package:flutter/material.dart';

import 'models/message.dart';

void main() => runApp(const SilentDomainApp());

class SilentDomainApp extends StatelessWidget {
  const SilentDomainApp({super.key});

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
      home: const SplashPage(),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

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
          MaterialPageRoute<void>(builder: (_) => const AppShell()),
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
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _pages = const [HomePage(), ChatPage(), SettingsPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
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
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

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
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('连接附近设备', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('阶段 1 暂使用界面演示。真实 BLE / Wi-Fi Direct 将在后续阶段接入。'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.bluetooth_searching_rounded),
                label: const Text('开始搜索'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _messages = <Message>[
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
  ];

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
            child: ListView.builder(
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
    });
  }

  void _retryMessage(Message message) {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return;
    setState(() {
      _messages[index] = message.copyWith(status: MessageStatus.sending);
    });
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
