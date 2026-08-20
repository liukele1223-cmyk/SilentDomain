import 'dart:convert';
import 'dart:typed_data';

// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:universal_ble/universal_ble.dart';

import 'package:silent_domain/core/bluetooth/discovery_service.dart';
import 'package:silent_domain/core/bluetooth/ble_protocol.dart';
import 'package:silent_domain/core/database/message_store.dart';
import 'package:silent_domain/core/security/device_identity_service.dart';
import 'package:silent_domain/features/emoji/emoji_store.dart';
import 'package:silent_domain/features/emoji/emoji_management_page.dart';
import 'package:silent_domain/features/emoji/emoji_message_content.dart';
import 'package:silent_domain/features/emoji/emoji_transfer.dart';
import 'package:silent_domain/features/theme/theme_settings.dart';
import 'package:silent_domain/models/message.dart';
import 'package:silent_domain/main.dart';

void main() {
  testWidgets('启动页可以进入静域首页', (WidgetTester tester) async {
    await tester.pumpWidget(SilentDomainApp());
    expect(find.text('静域'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('连接附近设备'), findsOneWidget);
    expect(find.text('最近聊天'), findsOneWidget);
  });

  testWidgets('未连接时失败消息重试后仍显示失败', (WidgetTester tester) async {
    await tester.pumpWidget(SilentDomainApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天'));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.error_outline_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('聊天输入框可以打开本地表情面板', (WidgetTester tester) async {
    await tester.pumpWidget(SilentDomainApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();
    expect(find.text('我的表情'), findsOneWidget);
    expect(find.text('从相册批量导入'), findsOneWidget);
  });

  testWidgets('表情面板提供管理入口和固定分页', (WidgetTester tester) async {
    final store = MemoryEmojiStore();
    final source = image.Image(width: 48, height: 48);
    image.fill(source, color: image.ColorRgb8(60, 110, 180));
    for (var index = 0; index < 13; index++) {
      final sticker = await store.importImage(image.encodePng(source));
      await store.renameSticker(sticker.id, '表情 $index');
    }

    await tester.pumpWidget(SilentDomainApp(emojiStore: store));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();

    expect(find.text('管理'), findsOneWidget);
    expect(find.byKey(const ValueKey('emoji-picker-page-0')), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('emoji-picker-page-1')), findsOneWidget);

    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    expect(find.text('聊天附件 0'), findsOneWidget);
    expect(find.text('我的表情 13'), findsOneWidget);
  });

  testWidgets('设置页可以切换到森林绿主题', (WidgetTester tester) async {
    final themeController = ThemeController(null);
    await tester.pumpWidget(SilentDomainApp(themeController: themeController));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('森林绿').first);
    await tester.pump();
    expect(themeController.settings.mode, AppThemeMode.forestGreen);
  });

  testWidgets('设置页固定提供自定义调色入口和当前色号', (WidgetTester tester) async {
    final themeController = ThemeController(
      null,
      initialSettings: const ThemeSettings(
        mode: AppThemeMode.custom,
        customColorValue: 0xFF123456,
      ),
    );
    await tester.pumpWidget(SilentDomainApp(themeController: themeController));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('自定义调色'), findsOneWidget);
    expect(find.text('#123456 · 点击继续微调'), findsOneWidget);
    await tester.tap(find.text('自定义调色'));
    await tester.pumpAndSettle();
    expect(find.text('红'), findsOneWidget);
    expect(find.text('绿'), findsOneWidget);
    expect(find.text('蓝'), findsOneWidget);
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.map((slider) => slider.value), [18, 52, 86]);
  });

  testWidgets('设置页可以打开表情与附件管理', (WidgetTester tester) async {
    await tester.pumpWidget(SilentDomainApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('表情与附件'));
    await tester.pumpAndSettle();
    expect(find.text('表情与附件'), findsOneWidget);
    expect(find.text('聊天附件 0'), findsOneWidget);
    expect(find.byTooltip('从相册批量导入'), findsOneWidget);
  });

  testWidgets('旧版仅名称的表情会恢复唯一匹配的本地图片', (WidgetTester tester) async {
    final source = image.Image(width: 80, height: 80);
    image.fill(source, color: image.ColorRgb8(80, 120, 160));
    final emojiStore = MemoryEmojiStore();
    final sticker = await emojiStore.importImage(image.encodePng(source));
    await emojiStore.renameSticker(sticker.id, '表情 0818');
    final messageStore = MemoryMessageStore(
      initialMessages: [
        Message(
          id: 'legacy-emoji',
          sender: 'nearby-device',
          content: '[表情：表情 0818]',
          timestamp: DateTime(2026, 8, 21),
        ),
      ],
    );

    await tester.pumpWidget(
      SilentDomainApp(emojiStore: emojiStore, messageStore: messageStore),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天'));
    await tester.pumpAndSettle();

    expect(find.text('[表情：表情 0818]'), findsNothing);
    expect(find.byType(EmojiMessageContent), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('首页可以打开 BLE 设备发现面板', (WidgetTester tester) async {
    await tester.pumpWidget(
      SilentDomainApp(
        discoveryService: FakeDiscoveryService(
          initialDevices: const [
            NearbyDevice(id: 'demo-device', name: '演示设备', rssi: -42),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发现设备').first);
    await tester.pumpAndSettle();

    expect(find.text('发现附近设备'), findsOneWidget);
    await tester.tap(find.text('开始搜索'));
    await tester.pumpAndSettle();
    expect(find.text('演示设备'), findsOneWidget);
    await tester.tap(find.text('演示设备'));
    await tester.pumpAndSettle();
    expect(find.text('连接确认'), findsOneWidget);
    expect(find.text('确认并连接'), findsOneWidget);
    await tester.tap(find.text('确认并连接'));
    await tester.pumpAndSettle();
    expect(find.text('开始聊天'), findsOneWidget);
    await tester.tap(find.text('开始聊天'));
    await tester.pumpAndSettle();
    expect(find.text('附近设备'), findsOneWidget);
    expect(find.text('已连接 · 蓝牙离线通道'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('断开连接'), findsOneWidget);
    await tester.tap(find.text('断开连接'));
    await tester.pumpAndSettle();
    expect(find.text('等待连接 · 离线'), findsOneWidget);
  });

  test('Message copyWith 保留未修改字段', () {
    final message = Message(
      id: 'message-1',
      sender: 'self',
      content: '测试',
      timestamp: DateTime(2026, 1, 1),
      status: MessageStatus.sending,
    );

    final completed = message.copyWith(status: MessageStatus.success);
    expect(completed.id, 'message-1');
    expect(completed.content, '测试');
    expect(completed.status, MessageStatus.success);
  });

  test('MessageStore 可以保存并读取消息', () async {
    final store = MemoryMessageStore();
    final message = Message(
      id: 'persisted-message',
      sender: 'self',
      content: '本地保存测试',
      timestamp: DateTime(2026, 1, 1),
    );

    await store.saveMessage(message);
    final messages = await store.loadMessages();

    expect(messages, hasLength(1));
    expect(messages.single.content, '本地保存测试');
  });

  testWidgets('聊天图片快照在原表情删除后仍可显示', (WidgetTester tester) async {
    final source = image.Image(width: 80, height: 80);
    image.fill(source, color: image.ColorRgb8(40, 80, 120));
    final bytes = Uint8List.fromList(image.encodePng(source));
    final store = MemoryEmojiStore();
    final duplicateOne = await store.importImage(bytes);
    final duplicateTwo = await store.importImage(bytes);
    await store.renameSticker(duplicateOne.id, '历史快照');
    await store.renameSticker(duplicateTwo.id, '历史快照');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmojiMessageContent(
            emojiId: 'already-deleted',
            emojiName: '历史快照',
            emojiSnapshot: bytes,
            emojiStore: store,
            color: Colors.black,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('历史快照，点按查看大图'), findsOneWidget);
  });

  test('表情导入会重新编码、缩放并保存在本地资料库', () async {
    final source = image.Image(width: 900, height: 300);
    image.fill(source, color: image.ColorRgb8(20, 40, 60));
    final sourceBytes = image.encodeJpg(source, quality: 100);
    final store = MemoryEmojiStore();

    final sticker = await store.importImage(sourceBytes);
    final asset = await store.loadAsset(sticker.id);
    final decoded = image.decodeImage(asset!.bytes);

    expect(sticker.path, startsWith('memory://'));
    expect(decoded, isNotNull);
    expect(decoded!.width, EmojiImageSanitizer.maximumDimension);
    expect(
      decoded.height,
      lessThanOrEqualTo(EmojiImageSanitizer.maximumDimension),
    );
    expect(asset.bytes, isNot(equals(sourceBytes)));
  });

  test('接收端可以再次导入已清理的 WebP 图片', () async {
    final source = image.Image(width: 640, height: 640);
    image.fill(source, color: image.ColorRgba8(80, 120, 160, 200));
    final senderStore = MemoryEmojiStore();
    final receiverStore = MemoryEmojiStore();

    final sent = await senderStore.importImage(image.encodePng(source));
    final receivedBytes = (await senderStore.loadAsset(sent.id))!.bytes;
    final received = await receiverStore.importTransferredImage(
      receivedBytes,
      name: '接收测试表情',
    );

    expect(received.name, '接收测试表情');
    expect((await receiverStore.loadAsset(received.id))!.bytes, isNotEmpty);
    expect(await receiverStore.loadStickers(), isEmpty);
  });

  test('表情资料库支持重命名、主动保存附件与清理缓存', () async {
    final source = image.Image(width: 120, height: 120);
    image.fill(source, color: image.ColorRgb8(40, 80, 120));
    final store = MemoryEmojiStore();
    final local = await store.importImage(image.encodePng(source));
    final attachment = await store.importTransferredImage(
      (await store.loadAsset(local.id))!.bytes,
      name: '接收图片',
    );

    var stats = await store.loadStorageStats();
    expect(stats.localCount, 1);
    expect(stats.attachmentCount, 1);

    await store.saveAsLocalSticker(attachment.id);
    await store.renameSticker(attachment.id, '已保存图片');
    expect(
      (await store.loadStickers()).map((item) => item.name),
      contains('已保存图片'),
    );

    final anotherAttachment = await store.importTransferredImage(
      (await store.loadAsset(local.id))!.bytes,
      name: '待清理附件',
    );
    expect(anotherAttachment.isLocalSticker, isFalse);
    expect(await store.clearTransferredAttachments(), 1);
    stats = await store.loadStorageStats();
    expect(stats.attachmentCount, 0);

    await store.deleteSticker(attachment.id);
    expect(
      (await store.loadStickers()).map((item) => item.id),
      isNot(contains(attachment.id)),
    );
  });

  test('表情资料库可以独立列出附件并批量删除', () async {
    final source = image.Image(width: 100, height: 100);
    image.fill(source, color: image.ColorRgb8(30, 70, 110));
    final store = MemoryEmojiStore();
    final firstLocal = await store.importImage(image.encodePng(source));
    final secondLocal = await store.importImage(image.encodePng(source));
    final attachment = await store.importTransferredImage(
      (await store.loadAsset(firstLocal.id))!.bytes,
      name: '待管理附件',
    );

    expect(
      (await store.loadStickers()).map((item) => item.id),
      unorderedEquals([firstLocal.id, secondLocal.id]),
    );
    expect((await store.loadTransferredAttachments()).map((item) => item.id), [
      attachment.id,
    ]);

    expect(
      await store.deleteStickers([firstLocal.id, attachment.id, 'not-found']),
      2,
    );
    expect((await store.loadStickers()).map((item) => item.id), [
      secondLocal.id,
    ]);
    expect(await store.loadTransferredAttachments(), isEmpty);
  });

  testWidgets('短按住拖动可连续选择多个表情', (WidgetTester tester) async {
    final source = image.Image(width: 80, height: 80);
    image.fill(source, color: image.ColorRgb8(30, 70, 110));
    final store = MemoryEmojiStore();
    final first = await store.importImage(image.encodePng(source));
    final second = await store.importImage(image.encodePng(source));
    await store.renameSticker(first.id, '一号测试表情');
    await store.renameSticker(second.id, '二号测试表情');

    await tester.pumpWidget(
      MaterialApp(home: EmojiManagementPage(store: store)),
    );
    await tester.pumpAndSettle();

    final firstFinder = find.text('一号测试表情');
    final secondFinder = find.text('二号测试表情');
    final gesture = await tester.startGesture(tester.getCenter(firstFinder));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('已选择 1 个项目'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(secondFinder));
    await tester.pump();
    expect(find.text('已选择 2 个项目'), findsOneWidget);
    await gesture.up();
  });

  testWidgets('任意表情排序均可切换正序与倒序', (WidgetTester tester) async {
    final source = image.Image(width: 80, height: 80);
    image.fill(source, color: image.ColorRgb8(30, 70, 110));
    final store = MemoryEmojiStore();
    final first = await store.importImage(image.encodePng(source));
    final second = await store.importImage(image.encodePng(source));
    await store.renameSticker(first.id, '苹果');
    await store.renameSticker(second.id, '香蕉');

    await tester.pumpWidget(
      MaterialApp(home: EmojiManagementPage(store: store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('正序'), findsOneWidget);
    await tester.tap(find.byTooltip('排序方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按名称 A–Z'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('正序'));
    await tester.pump();
    expect(find.text('倒序'), findsOneWidget);
  });

  testWidgets('接收图片可在全屏预览内显示保存成功反馈', (WidgetTester tester) async {
    final source = image.Image(width: 80, height: 80);
    image.fill(source, color: image.ColorRgb8(40, 80, 120));
    final store = MemoryEmojiStore();
    final local = await store.importImage(image.encodePng(source));
    final attachment = await store.importTransferredImage(
      (await store.loadAsset(local.id))!.bytes,
      name: '接收图片',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmojiMessageContent(
            emojiId: attachment.id,
            emojiName: attachment.name,
            emojiStore: store,
            color: Colors.black,
            canSaveAsSticker: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('接收图片，点按查看大图'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('保存为我的表情'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('已保存到我的表情'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_added_rounded), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('已保存到我的表情'), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('发送和新消息会按用户浏览位置决定是否自动定位', (WidgetTester tester) async {
    final messages = List<Message>.generate(
      30,
      (index) => Message(
        id: 'history-$index',
        sender: index.isEven ? 'self' : 'nearby-device',
        content: '历史消息 $index',
        timestamp: DateTime(2026, 1, 1, 9, index),
      ),
    );
    final discovery = FakeDiscoveryService();
    await tester.pumpWidget(
      SilentDomainApp(
        messageStore: MemoryMessageStore(initialMessages: messages),
        discoveryService: discovery,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天'));
    await tester.pumpAndSettle();

    final messageList = tester.widget<ListView>(
      find.byKey(const ValueKey('chat-message-list')),
    );
    final scrollable = messageList.controller!;
    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.maxScrollExtent, 1),
    );

    scrollable.position.jumpTo(0);
    await tester.pump();
    discovery.emitIncomingPacket(
      BlePacket(
        type: BlePacketType.message,
        id: 'remote-new-message',
        payload: jsonEncode({
          'content': '远端新消息',
          'timestamp': DateTime(2026, 1, 1, 10).toIso8601String(),
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('有新消息'), findsOneWidget);

    await tester.tap(find.text('有新消息'));
    await tester.pumpAndSettle();
    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.maxScrollExtent, 1),
    );
  });

  test('不透明图片会编码为适合 BLE 传输的 JPEG', () {
    final source = image.Image(width: 640, height: 640);
    image.fill(source, color: image.ColorRgb8(80, 120, 160));

    final bytes = EmojiImageSanitizer.sanitize(image.encodePng(source));

    expect(bytes.take(2), orderedEquals([0xff, 0xd8]));
  });

  test('含透明像素的表情仍保留透明通道', () {
    final source = image.Image(width: 128, height: 128, numChannels: 4);
    image.fill(source, color: image.ColorRgba8(80, 120, 160, 120));

    final bytes = EmojiImageSanitizer.sanitize(image.encodePng(source));
    final decoded = image.decodeImage(bytes);

    expect(decoded, isNotNull);
    expect(decoded!.getPixel(0, 0).a, 120);
  });

  test('大尺寸透明表情会缩小以减少 BLE 传输分片', () {
    final source = image.Image(width: 512, height: 384, numChannels: 4);
    image.fill(source, color: image.ColorRgba8(80, 120, 160, 180));

    final bytes = EmojiImageSanitizer.sanitize(image.encodePng(source));
    final decoded = image.decodeImage(bytes);

    expect(decoded, isNotNull);
    expect(
      decoded!.width,
      lessThanOrEqualTo(EmojiImageSanitizer.maximumTransparentDimension),
    );
    expect(
      decoded.height,
      lessThanOrEqualTo(EmojiImageSanitizer.maximumTransparentDimension),
    );
    expect(decoded.getPixel(0, 0).a, 180);
  });

  test('图片传输可以分片、乱序重组并校验完整性', () async {
    final bytes = Uint8List.fromList(
      List<int>.generate(2500, (index) => index % 251),
    );
    final chunks = EmojiTransferCodec.split(bytes);
    final manifest = EmojiTransferManifest(
      content: '[表情：测试图片]',
      name: '测试图片',
      timestamp: DateTime(2026, 8, 18),
      byteLength: bytes.length,
      chunkCount: chunks.length,
      checksum: await EmojiTransferCodec.checksum(bytes),
    );
    final receiver = EmojiTransferAccumulator(manifest);

    for (var index = chunks.length - 1; index >= 0; index--) {
      final encoded = EmojiTransferCodec.encodeChunk(index, chunks[index]);
      final chunk = EmojiTransferCodec.decodeChunk(encoded);
      receiver.add(chunk.index, chunk.bytes);
    }

    expect(receiver.progress, 1);
    expect(await receiver.assemble(), bytes);
  });

  test('主题控制器支持切换自定义 RGB 颜色', () async {
    final controller = ThemeController(null);

    controller.previewCustomColor(const Color(0xFF123456));

    expect(controller.settings.mode, AppThemeMode.custom);
    expect(controller.settings.customColor, const Color(0xFF123456));
    expect(controller.isPreviewing, isTrue);

    await controller.finishCustomPreview();
    expect(controller.isPreviewing, isFalse);
  });

  test('BLE 数据包可以编码、解码并分片重组', () {
    final packet = BlePacket(
      type: BlePacketType.message,
      id: 'packet-1',
      payload: '一段需要通过 BLE 传输的消息内容',
    );
    final encoded = packet.encode();
    final decoded = BlePacket.decode(encoded);
    final frames = BleFrameCodec.split(encoded);
    final restored = frames
        .expand((frame) => BleFrameCodec.decode(frame).payload)
        .toList();

    expect(decoded.id, packet.id);
    expect(decoded.payload, packet.payload);
    expect(restored, encoded);
    expect(
      frames.every((frame) => frame.length <= BleFrameCodec.payloadSize),
      isTrue,
    );
  });

  test('聊天图片快照不会重复进入 BLE 消息包', () {
    final packet = BlePacket.fromMessage(
      Message(
        id: 'emoji-message',
        sender: 'self',
        content: '[表情：测试]',
        timestamp: DateTime(2026, 8, 21),
        emojiId: 'local-sticker',
        emojiName: '测试',
        emojiSnapshot: Uint8List.fromList([1, 2, 3]),
      ),
    );
    final payload = jsonDecode(packet.payload) as Map<String, dynamic>;

    expect(payload.containsKey('emojiSnapshot'), isFalse);
  });

  test('BLE 帧组编号可区分相同长度的连续消息', () {
    final first = BleFrameCodec.split(Uint8List.fromList(List.filled(80, 1)));
    final second = BleFrameCodec.split(Uint8List.fromList(List.filled(80, 2)));
    final firstIds = first
        .map((frame) => BleFrameCodec.decode(frame).transferId)
        .toSet();
    final secondIds = second
        .map((frame) => BleFrameCodec.decode(frame).transferId)
        .toSet();

    expect(firstIds, hasLength(1));
    expect(secondIds, hasLength(1));
    expect(firstIds.single, isNot(secondIds.single));
  });

  test('BLE UUID 合同稳定且大小写不敏感', () {
    expect(
      BleUuidParser.compareStrings(
        SilentDomainBleUuid.service,
        '7E3A0001-4B9A-4C1D-9E2A-53494C454E54',
      ),
      isTrue,
    );
    expect(SilentDomainBleUuid.writeCharacteristic, isNotEmpty);
    expect(SilentDomainBleUuid.notifyCharacteristic, isNotEmpty);
  });

  test('ECDH 双方派生相同 AES-256-GCM 会话密钥并拒绝篡改', () async {
    final first = await EphemeralSessionKey.create();
    final second = await EphemeralSessionKey.create();
    const transcript = 'verified-pairing-transcript';
    final firstCipher = await first.deriveSessionCipher(
      remotePublicKey: second.publicKey,
      transcript: transcript,
    );
    final secondCipher = await second.deriveSessionCipher(
      remotePublicKey: first.publicKey,
      transcript: transcript,
    );

    final encrypted = await firstCipher.encrypt(
      '只在离线通道中可见',
      authenticatedData: 'message-001',
    );
    expect(encrypted.ciphertext, isNot('只在离线通道中可见'));
    expect(
      EncryptedPayload.fromCompact(encrypted.toCompact()).ciphertext,
      encrypted.ciphertext,
    );
    expect(
      await secondCipher.decrypt(encrypted, authenticatedData: 'message-001'),
      '只在离线通道中可见',
    );
    await expectLater(
      secondCipher.decrypt(encrypted, authenticatedData: 'message-002'),
      throwsA(anything),
    );
  });
}
