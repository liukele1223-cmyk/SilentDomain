// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:silent_domain/main.dart';

void main() {
  testWidgets('启动页可以进入静域首页', (WidgetTester tester) async {
    await tester.pumpWidget(const SilentDomainApp());
    expect(find.text('静域'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('连接附近设备'), findsOneWidget);
    expect(find.text('最近聊天'), findsOneWidget);
  });
}
