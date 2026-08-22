import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../core/database/image_transfer_metrics_store.dart';
import '../../models/image_transfer_metric.dart';

typedef ImageTransferElapsedClock = Duration Function();
typedef ImageTransferMetricIdFactory = String Function();

/// 图片传输关键路径使用的旁路记录器。
///
/// 它不接收消息 ID、图片内容或对端信息；持久化失败会被隔离，不能影响传输。
class ImageTransferMetricsRecorder {
  ImageTransferMetricsRecorder(
    this._store, {
    DateTime Function()? wallClock,
    ImageTransferElapsedClock? elapsedClock,
    ImageTransferMetricIdFactory? idFactory,
    this.progressStallThreshold = const Duration(seconds: 1),
  }) : _wallClock = wallClock ?? DateTime.now,
       _elapsedClock = elapsedClock ?? _defaultElapsedClock,
       _idFactory = idFactory ?? _createMetricId;

  static final Stopwatch _processClock = Stopwatch()..start();

  final ImageTransferMetricsStore _store;
  final DateTime Function() _wallClock;
  final ImageTransferElapsedClock _elapsedClock;
  final ImageTransferMetricIdFactory _idFactory;
  final Duration progressStallThreshold;
  final Set<ImageTransferMetricSession> _activeSessions =
      <ImageTransferMetricSession>{};

  ImageTransferMetricSession start({
    required ImageTransferDirection direction,
    ImageTransferTransportPath transportPath =
        ImageTransferTransportPath.unavailable,
    int maximumBleFrameSize = 0,
    ImageTransferConnectionPriority connectionPriority =
        ImageTransferConnectionPriority.notRequested,
    int inputByteLength = 0,
    int transferByteLength = 0,
    int chunkCount = 0,
  }) {
    final session = ImageTransferMetricSession._(
      owner: this,
      id: _idFactory(),
      occurredAt: _wallClock(),
      startedAt: _elapsedClock(),
      direction: direction,
      transportPath: transportPath,
      maximumBleFrameSize: maximumBleFrameSize,
      connectionPriority: connectionPriority,
      inputByteLength: inputByteLength,
      transferByteLength: transferByteLength,
      chunkCount: chunkCount,
      concurrentAtStart: _activeSessions.isNotEmpty,
    );
    _activeSessions.add(session);
    final concurrentCount = _activeSessions.length;
    for (final activeSession in _activeSessions) {
      activeSession._observeConcurrency(concurrentCount);
    }
    return session;
  }

  void _finish(
    ImageTransferMetricSession session, {
    required ImageTransferOutcome outcome,
    ImageTransferFailureCategory? failureCategory,
  }) {
    if (!_activeSessions.remove(session)) return;
    final finishedAt = _elapsedClock();
    session._observeProgressGap(finishedAt);
    final metric = ImageTransferMetric(
      id: session._id,
      occurredAt: session._occurredAt,
      direction: session.direction,
      outcome: outcome,
      transportPath: session.transportPath,
      maximumBleFrameSize: session.maximumBleFrameSize,
      connectionPriority: session.connectionPriority,
      inputByteLength: session.inputByteLength,
      transferByteLength: session.transferByteLength,
      chunkCount: session.chunkCount,
      durationMilliseconds: max(
        0,
        (finishedAt - session._startedAt).inMilliseconds,
      ),
      retryCount: session.retryCount,
      batchRetryCount: session.batchRetryCount,
      progressStallCount: session.progressStallCount,
      longestProgressStallMilliseconds:
          session.longestProgressStallMilliseconds,
      concurrentAtStart: session.concurrentAtStart,
      maxConcurrentTransfers: session.maxConcurrentTransfers,
      failureCategory: failureCategory,
    );
    unawaited(_recordSafely(metric));
  }

  Future<void> _recordSafely(ImageTransferMetric metric) async {
    try {
      await _store.record(metric);
    } on Object {
      // 诊断是旁路能力：记录失败不得改变消息状态或 BLE 传输流程。
    }
  }

  static Duration _defaultElapsedClock() => _processClock.elapsed;

  static String _createMetricId() {
    final bytes = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }
}

class ImageTransferMetricSession {
  ImageTransferMetricSession._({
    required this._owner,
    required this._id,
    required this._occurredAt,
    required Duration startedAt,
    required this.direction,
    required this.transportPath,
    required this.maximumBleFrameSize,
    required this.connectionPriority,
    required this.inputByteLength,
    required this.transferByteLength,
    required this.chunkCount,
    required this.concurrentAtStart,
  }) : _startedAt = startedAt,
       _lastProgressAt = startedAt;

  final ImageTransferMetricsRecorder _owner;
  final String _id;
  final DateTime _occurredAt;
  final Duration _startedAt;
  final ImageTransferDirection direction;
  final bool concurrentAtStart;

  ImageTransferTransportPath transportPath;
  int maximumBleFrameSize;
  ImageTransferConnectionPriority connectionPriority;
  int inputByteLength;
  int transferByteLength;
  int chunkCount;
  int retryCount = 0;
  int batchRetryCount = 0;
  int progressStallCount = 0;
  int longestProgressStallMilliseconds = 0;
  int maxConcurrentTransfers = 1;
  Duration _lastProgressAt;
  bool _finished = false;

  void setPayload({
    required int inputByteLength,
    required int transferByteLength,
    required int chunkCount,
  }) {
    if (_finished) return;
    this.inputByteLength = max(0, inputByteLength);
    this.transferByteLength = max(0, transferByteLength);
    this.chunkCount = max(0, chunkCount);
  }

  void setTransport({
    required ImageTransferTransportPath path,
    required int maximumBleFrameSize,
  }) {
    if (_finished) return;
    transportPath = path;
    this.maximumBleFrameSize = max(0, maximumBleFrameSize);
  }

  void setConnectionPriority(ImageTransferConnectionPriority priority) {
    if (!_finished) connectionPriority = priority;
  }

  void markProgress() {
    if (_finished) return;
    final now = _owner._elapsedClock();
    _observeProgressGap(now);
    _lastProgressAt = now;
  }

  void incrementRetry() {
    if (!_finished) retryCount++;
  }

  void incrementBatchRetry() {
    if (!_finished) batchRetryCount++;
  }

  void finishSuccess() => _finish(ImageTransferOutcome.success);

  void finishFailure(ImageTransferFailureCategory category) =>
      _finish(ImageTransferOutcome.failed, failureCategory: category);

  void _finish(
    ImageTransferOutcome outcome, {
    ImageTransferFailureCategory? failureCategory,
  }) {
    if (_finished) return;
    _finished = true;
    _owner._finish(this, outcome: outcome, failureCategory: failureCategory);
  }

  void _observeConcurrency(int concurrentCount) {
    maxConcurrentTransfers = max(maxConcurrentTransfers, concurrentCount);
  }

  void _observeProgressGap(Duration now) {
    final gap = now - _lastProgressAt;
    if (gap < _owner.progressStallThreshold) return;
    progressStallCount++;
    longestProgressStallMilliseconds = max(
      longestProgressStallMilliseconds,
      gap.inMilliseconds,
    );
  }
}
