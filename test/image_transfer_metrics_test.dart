import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:silent_domain/core/bluetooth/ble_protocol.dart';
import 'package:silent_domain/core/bluetooth/discovery_service.dart';
import 'package:silent_domain/core/database/image_transfer_metrics_store.dart';
import 'package:silent_domain/features/diagnostics/image_transfer_metrics_recorder.dart';
import 'package:silent_domain/features/diagnostics/transfer_diagnostics_page.dart';
import 'package:silent_domain/features/emoji/emoji_transfer.dart';
import 'package:silent_domain/main.dart';
import 'package:silent_domain/models/image_transfer_metric.dart';

void main() {
  test('图片传输指标可以往返序列化并拒绝任意故障文本', () {
    final metric = _metric(
      id: 'metric-1',
      outcome: ImageTransferOutcome.failed,
      failureCategory: ImageTransferFailureCategory.timeout,
    );

    expect(ImageTransferMetric.fromMap(metric.toMap()), _matchesMetric(metric));

    final invalid = Map<String, Object?>.from(metric.toMap())
      ..['failureCategory'] = '包含底层异常正文';
    expect(
      () => ImageTransferMetric.fromMap(invalid),
      throwsA(isA<FormatException>()),
    );
  });

  test('记录器统计停顿、重试和并发且使用独立指标 ID', () async {
    var elapsed = Duration.zero;
    var idSequence = 0;
    final store = MemoryImageTransferMetricsStore();
    final recorder = ImageTransferMetricsRecorder(
      store,
      wallClock: () => DateTime(2026, 8, 22, 12),
      elapsedClock: () => elapsed,
      idFactory: () => 'independent-metric-${idSequence++}',
    );
    final outgoing = recorder.start(
      direction: ImageTransferDirection.outgoing,
      transportPath: ImageTransferTransportPath.centralWrite,
      maximumBleFrameSize: 244,
      connectionPriority:
          ImageTransferConnectionPriority.highPerformanceAccepted,
      inputByteLength: 4096,
      transferByteLength: 2048,
      chunkCount: 2,
    );
    elapsed = const Duration(milliseconds: 500);
    outgoing.markProgress();
    final incoming = recorder.start(
      direction: ImageTransferDirection.incoming,
      inputByteLength: 2048,
      transferByteLength: 2048,
      chunkCount: 2,
    );
    outgoing.incrementRetry();
    outgoing.incrementBatchRetry();
    elapsed = const Duration(milliseconds: 1600);
    outgoing.finishSuccess();
    incoming.finishFailure(ImageTransferFailureCategory.timeout);
    await Future<void>.delayed(Duration.zero);

    final records = await store.loadRecent();
    final outgoingMetric = records.singleWhere(
      (record) => record.direction == ImageTransferDirection.outgoing,
    );
    final incomingMetric = records.singleWhere(
      (record) => record.direction == ImageTransferDirection.incoming,
    );
    expect(outgoingMetric.id, 'independent-metric-0');
    expect(
      outgoingMetric.transportPath,
      ImageTransferTransportPath.centralWrite,
    );
    expect(outgoingMetric.maximumBleFrameSize, 244);
    expect(
      outgoingMetric.connectionPriority,
      ImageTransferConnectionPriority.highPerformanceAccepted,
    );
    expect(outgoingMetric.retryCount, 1);
    expect(outgoingMetric.batchRetryCount, 1);
    expect(outgoingMetric.progressStallCount, 1);
    expect(outgoingMetric.longestProgressStallMilliseconds, 1100);
    expect(outgoingMetric.concurrentAtStart, isFalse);
    expect(outgoingMetric.maxConcurrentTransfers, 2);
    expect(incomingMetric.concurrentAtStart, isTrue);
    expect(incomingMetric.maxConcurrentTransfers, 2);
  });

  test('诊断存储失败不会从旁路记录器冒泡', () async {
    final recorder = ImageTransferMetricsRecorder(
      _ThrowingMetricsStore(),
      idFactory: () => 'isolated-metric',
    );

    recorder
        .start(direction: ImageTransferDirection.outgoing)
        .finishFailure(ImageTransferFailureCategory.storage);
    await Future<void>.delayed(Duration.zero);
  });

  test('内存诊断存储严格限制为最近 120 条', () async {
    final store = MemoryImageTransferMetricsStore();
    for (var index = 0; index < 125; index++) {
      await store.record(
        _metric(
          id: 'metric-$index',
          occurredAt: DateTime(2026, 8, 22).add(Duration(seconds: index)),
        ),
      );
    }

    final records = await store.loadRecent(limit: 200);
    expect(records, hasLength(120));
    expect(records.first.id, 'metric-124');
    expect(records.last.id, 'metric-5');
  });

  test('MTU 协商只重试一次并在失败时可靠回退', () async {
    var attempts = 0;
    final recovered = await negotiateBleMaximumFrameSize(() async {
      attempts++;
      if (attempts == 1) throw StateError('test-only');
      return 247;
    }, retryDelay: Duration.zero);
    expect(attempts, 2);
    expect(recovered, 244);

    final fallback = await negotiateBleMaximumFrameSize(
      () async => throw StateError('test-only'),
      retryDelay: Duration.zero,
    );
    expect(fallback, BleFrameCodec.payloadSize);
    expect(BleFrameCodec.normalizeMaximumFrameSize(514), 244);
  });

  testWidgets('诊断页清空前必须确认且不会删除其他内容', (tester) async {
    final store = MemoryImageTransferMetricsStore(
      initialRecords: [_metric(id: 'metric-visible')],
    );
    await tester.pumpWidget(
      MaterialApp(home: TransferDiagnosticsPage(store: store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('图片传输诊断'), findsOneWidget);
    expect(find.textContaining('1 个应用分片'), findsOneWidget);
    await tester.tap(find.byTooltip('清空诊断记录'));
    await tester.pumpAndSettle();
    expect(find.text('清空传输诊断记录？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await store.loadRecent(), hasLength(1));

    await tester.tap(find.byTooltip('清空诊断记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(await store.loadRecent(), isEmpty);
    expect(find.textContaining('还没有图片传输记录'), findsOneWidget);
  });

  testWidgets('设置页可以进入仅本机图片传输诊断', (tester) async {
    final store = MemoryImageTransferMetricsStore();
    await tester.pumpWidget(SilentDomainApp(imageTransferMetricsStore: store));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('图片传输诊断'));
    await tester.pumpAndSettle();
    expect(find.text('图片传输诊断'), findsOneWidget);
    expect(find.text('诊断隐私说明'), findsOneWidget);
    await tester.tap(find.byTooltip('查看诊断隐私说明'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不记录图片内容'), findsOneWidget);
  });

  testWidgets('诊断汇总在窄屏和大字号下完整显示速度单位', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 720));
    final store = MemoryImageTransferMetricsStore(
      initialRecords: [_metric(id: 'metric-responsive')],
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: TransferDiagnosticsPage(store: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('平均速度'), findsOneWidget);
    expect(find.text('1.0 KB/s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('接收图片长时间无进度会记录脱敏超时并清理会话', (tester) async {
    final store = MemoryImageTransferMetricsStore();
    final discovery = FakeDiscoveryService();
    final bytes = Uint8List.fromList([1]);
    final manifest = EmojiTransferManifest(
      content: '[表情：测试]',
      name: '测试',
      timestamp: DateTime(2026, 8, 22, 12),
      byteLength: bytes.length,
      chunkCount: 1,
      checksum: await EmojiTransferCodec.checksum(bytes),
    );
    await tester.pumpWidget(
      SilentDomainApp(
        discoveryService: discovery,
        imageTransferMetricsStore: store,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();

    discovery.emitIncomingPacket(
      BlePacket(
        type: BlePacketType.emojiStart,
        id: 'test-incoming-timeout',
        payload: jsonEncode(manifest.toJson()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();

    final records = await store.loadRecent();
    expect(records, hasLength(1));
    expect(records.single.direction, ImageTransferDirection.incoming);
    expect(records.single.outcome, ImageTransferOutcome.failed);
    expect(
      records.single.failureCategory,
      ImageTransferFailureCategory.timeout,
    );
    expect(records.single.transferByteLength, 1);
  });
}

ImageTransferMetric _metric({
  required String id,
  DateTime? occurredAt,
  ImageTransferOutcome outcome = ImageTransferOutcome.success,
  ImageTransferFailureCategory? failureCategory,
}) {
  return ImageTransferMetric(
    id: id,
    occurredAt: occurredAt ?? DateTime(2026, 8, 22, 12),
    direction: ImageTransferDirection.outgoing,
    outcome: outcome,
    transportPath: ImageTransferTransportPath.centralWrite,
    maximumBleFrameSize: 244,
    connectionPriority: ImageTransferConnectionPriority.notRequested,
    inputByteLength: 2048,
    transferByteLength: 1024,
    chunkCount: 1,
    durationMilliseconds: 1000,
    retryCount: 0,
    batchRetryCount: 0,
    progressStallCount: 0,
    longestProgressStallMilliseconds: 0,
    concurrentAtStart: false,
    maxConcurrentTransfers: 1,
    failureCategory: failureCategory,
  );
}

Matcher _matchesMetric(ImageTransferMetric expected) =>
    isA<ImageTransferMetric>()
        .having((metric) => metric.id, 'id', expected.id)
        .having(
          (metric) => metric.occurredAt,
          'occurredAt',
          expected.occurredAt,
        )
        .having((metric) => metric.direction, 'direction', expected.direction)
        .having((metric) => metric.outcome, 'outcome', expected.outcome)
        .having(
          (metric) => metric.progressStallCount,
          'progressStallCount',
          expected.progressStallCount,
        )
        .having(
          (metric) => metric.failureCategory,
          'failureCategory',
          expected.failureCategory,
        );

class _ThrowingMetricsStore implements ImageTransferMetricsStore {
  @override
  Future<void> clear() async => throw StateError('test-only');

  @override
  Future<List<ImageTransferMetric>> loadRecent({int limit = 80}) async =>
      throw StateError('test-only');

  @override
  Future<void> record(ImageTransferMetric metric) async =>
      throw StateError('test-only');
}
