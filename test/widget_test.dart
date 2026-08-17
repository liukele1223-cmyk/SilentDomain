// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'package:silent_domain/core/bluetooth/discovery_service.dart';
import 'package:silent_domain/core/bluetooth/ble_protocol.dart';
import 'package:silent_domain/core/database/message_store.dart';
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
}
