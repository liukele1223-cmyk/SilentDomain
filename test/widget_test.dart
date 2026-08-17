// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('失败消息可以点击重试', (WidgetTester tester) async {
    await tester.pumpWidget(SilentDomainApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天'));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.error_outline_rounded));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
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
}
