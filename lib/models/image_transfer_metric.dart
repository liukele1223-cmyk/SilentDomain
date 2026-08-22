/// 单次聊天图片传输的本机性能元数据。
///
/// 该模型刻意不包含图片内容、消息文本、设备名称、蓝牙地址或任何用户身份。
/// 它仅用于离线诊断传输速度与稳定性。
enum ImageTransferDirection { outgoing, incoming }

enum ImageTransferOutcome { success, failed }

/// 仅描述本机在当前连接中的 BLE 角色，不包含设备或连接标识。
enum ImageTransferTransportPath {
  centralWrite,
  peripheralNotification,
  unavailable,
}

enum ImageTransferConnectionPriority {
  notRequested,
  highPerformanceAccepted,
  requestFailed,
}

/// 对外只保留固定、脱敏后的故障类别，不保存底层异常文本。
enum ImageTransferFailureCategory {
  timeout,
  integrity,
  transport,
  validation,
  storage,
  cancelled,
  unknown,
}

class ImageTransferMetric {
  const ImageTransferMetric({
    required this.id,
    required this.occurredAt,
    required this.direction,
    required this.outcome,
    required this.transportPath,
    required this.maximumBleFrameSize,
    required this.connectionPriority,
    required this.inputByteLength,
    required this.transferByteLength,
    required this.chunkCount,
    required this.durationMilliseconds,
    required this.retryCount,
    required this.batchRetryCount,
    required this.progressStallCount,
    required this.longestProgressStallMilliseconds,
    required this.concurrentAtStart,
    required this.maxConcurrentTransfers,
    this.failureCategory,
  });

  final String id;
  final DateTime occurredAt;
  final ImageTransferDirection direction;
  final ImageTransferOutcome outcome;
  final ImageTransferTransportPath transportPath;

  /// 本次发送路径采用的 BLE 帧上限；尚未建立路径时为 0。
  final int maximumBleFrameSize;
  final ImageTransferConnectionPriority connectionPriority;

  /// 发送端为重新编码前的本机图片字节数；接收端等于传输字节数。
  final int inputByteLength;

  /// 当前 BLE 实际承载的清理后图片字节数。
  final int transferByteLength;
  final int chunkCount;
  final int durationMilliseconds;
  final int retryCount;
  final int batchRetryCount;
  final int progressStallCount;
  final int longestProgressStallMilliseconds;
  final bool concurrentAtStart;
  final int maxConcurrentTransfers;

  final ImageTransferFailureCategory? failureCategory;

  int get bytesPerSecond {
    if (durationMilliseconds <= 0) return 0;
    return (transferByteLength * 1000 / durationMilliseconds).round();
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'occurredAt': occurredAt.toIso8601String(),
    'direction': direction.name,
    'outcome': outcome.name,
    'transportPath': transportPath.name,
    'maximumBleFrameSize': maximumBleFrameSize,
    'connectionPriority': connectionPriority.name,
    'inputByteLength': inputByteLength,
    'transferByteLength': transferByteLength,
    'chunkCount': chunkCount,
    'durationMilliseconds': durationMilliseconds,
    'retryCount': retryCount,
    'batchRetryCount': batchRetryCount,
    'progressStallCount': progressStallCount,
    'longestProgressStallMilliseconds': longestProgressStallMilliseconds,
    'concurrentAtStart': concurrentAtStart,
    'maxConcurrentTransfers': maxConcurrentTransfers,
    'failureCategory': failureCategory?.name,
  };

  factory ImageTransferMetric.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final occurredAt = map['occurredAt'];
    final direction = map['direction'];
    final outcome = map['outcome'];
    final transportPath = map['transportPath'];
    final maximumBleFrameSize = map['maximumBleFrameSize'];
    final connectionPriority = map['connectionPriority'];
    final inputByteLength = map['inputByteLength'];
    final transferByteLength = map['transferByteLength'];
    final chunkCount = map['chunkCount'];
    final durationMilliseconds = map['durationMilliseconds'];
    final retryCount = map['retryCount'];
    final batchRetryCount = map['batchRetryCount'];
    final progressStallCount = map['progressStallCount'];
    final longestProgressStallMilliseconds =
        map['longestProgressStallMilliseconds'];
    final concurrentAtStart = map['concurrentAtStart'];
    final maxConcurrentTransfers = map['maxConcurrentTransfers'];
    final failureCategory = map['failureCategory'];
    if (id is! String ||
        occurredAt is! String ||
        direction is! String ||
        outcome is! String ||
        transportPath is! String ||
        maximumBleFrameSize is! int ||
        connectionPriority is! String ||
        inputByteLength is! int ||
        transferByteLength is! int ||
        chunkCount is! int ||
        durationMilliseconds is! int ||
        retryCount is! int ||
        batchRetryCount is! int ||
        progressStallCount is! int ||
        longestProgressStallMilliseconds is! int ||
        concurrentAtStart is! bool ||
        maxConcurrentTransfers is! int ||
        (failureCategory != null && failureCategory is! String)) {
      throw const FormatException('图片传输诊断记录无效');
    }
    if (id.isEmpty ||
        maximumBleFrameSize < 0 ||
        inputByteLength < 0 ||
        transferByteLength < 0 ||
        chunkCount < 0 ||
        durationMilliseconds < 0 ||
        retryCount < 0 ||
        batchRetryCount < 0 ||
        progressStallCount < 0 ||
        longestProgressStallMilliseconds < 0 ||
        maxConcurrentTransfers < 1) {
      throw const FormatException('图片传输诊断记录无效');
    }
    try {
      final parsedOutcome = ImageTransferOutcome.values.byName(outcome);
      final parsedTransportPath = ImageTransferTransportPath.values.byName(
        transportPath,
      );
      final parsedConnectionPriority = ImageTransferConnectionPriority.values
          .byName(connectionPriority);
      final parsedFailureCategory = failureCategory == null
          ? null
          : ImageTransferFailureCategory.values.byName(failureCategory);
      if ((parsedOutcome == ImageTransferOutcome.success &&
              parsedFailureCategory != null) ||
          (parsedOutcome == ImageTransferOutcome.failed &&
              parsedFailureCategory == null)) {
        throw const FormatException('图片传输诊断记录无效');
      }
      return ImageTransferMetric(
        id: id,
        occurredAt: DateTime.parse(occurredAt),
        direction: ImageTransferDirection.values.byName(direction),
        outcome: parsedOutcome,
        transportPath: parsedTransportPath,
        maximumBleFrameSize: maximumBleFrameSize,
        connectionPriority: parsedConnectionPriority,
        inputByteLength: inputByteLength,
        transferByteLength: transferByteLength,
        chunkCount: chunkCount,
        durationMilliseconds: durationMilliseconds,
        retryCount: retryCount,
        batchRetryCount: batchRetryCount,
        progressStallCount: progressStallCount,
        longestProgressStallMilliseconds: longestProgressStallMilliseconds,
        concurrentAtStart: concurrentAtStart,
        maxConcurrentTransfers: maxConcurrentTransfers,
        failureCategory: parsedFailureCategory,
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('图片传输诊断记录无效');
    }
  }
}
