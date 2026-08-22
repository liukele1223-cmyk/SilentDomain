import 'package:flutter/material.dart';

import '../../core/database/image_transfer_metrics_store.dart';
import '../../models/image_transfer_metric.dart';

/// 本机图片传输性能诊断。
///
/// 仅展示本机加密保存的传输元数据，不展示图片内容、聊天内容或对方设备信息。
class TransferDiagnosticsPage extends StatefulWidget {
  const TransferDiagnosticsPage({required this.store, super.key});

  final ImageTransferMetricsStore store;

  @override
  State<TransferDiagnosticsPage> createState() =>
      _TransferDiagnosticsPageState();
}

class _TransferDiagnosticsPageState extends State<TransferDiagnosticsPage> {
  List<ImageTransferMetric> _records = const [];
  bool _isLoading = true;
  bool _isClearing = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records = await widget.store.loadRecent();
      if (!mounted) return;
      setState(() {
        _records = records;
        _isLoading = false;
        _loadFailed = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _clear() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空传输诊断记录？'),
        content: const Text('仅删除本机的图片传输性能数据，不会删除聊天记录、图片或表情。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    setState(() => _isClearing = true);
    try {
      await widget.store.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已清空本机传输诊断记录')));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法清空诊断记录，请稍后重试')));
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final successfulRecords = _records
        .where((record) => record.outcome == ImageTransferOutcome.success)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('图片传输诊断'),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              tooltip: '清空诊断记录',
              onPressed: _isClearing ? null : _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? _DiagnosticsLoadFailure(onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _PrivacyNotice(),
                  const SizedBox(height: 16),
                  _MetricsSummary(
                    totalCount: _records.length,
                    successfulRecords: successfulRecords,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '最近记录',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_records.isEmpty)
                    const _EmptyDiagnostics()
                  else
                    for (final record in _records) ...[
                      _MetricCard(record: record),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  static const _details =
      '仅保存最近 120 条本机加密性能元数据：字节数、耗时、重试、传输角色和结果。'
      '不记录图片内容、聊天文字、设备名称、地址、身份信息或密钥。';

  Future<void> _showDetails(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.privacy_tip_outlined),
        title: const Text('诊断隐私说明'),
        content: const Text(_details),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.privacy_tip_outlined,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
        title: Text(
          '诊断隐私说明',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        trailing: IconButton(
          tooltip: '查看诊断隐私说明',
          onPressed: () => _showDetails(context),
          icon: const Icon(Icons.info_outline_rounded),
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _MetricsSummary extends StatelessWidget {
  const _MetricsSummary({
    required this.totalCount,
    required this.successfulRecords,
  });

  final int totalCount;
  final List<ImageTransferMetric> successfulRecords;

  @override
  Widget build(BuildContext context) {
    final failedCount = totalCount - successfulRecords.length;
    final averageBytesPerSecond = successfulRecords.isEmpty
        ? 0
        : successfulRecords
                  .map((record) => record.bytesPerSecond)
                  .reduce((sum, value) => sum + value) ~/
              successfulRecords.length;
    final averageDuration = successfulRecords.isEmpty
        ? 0
        : successfulRecords
                  .map((record) => record.durationMilliseconds)
                  .reduce((sum, value) => sum + value) ~/
              successfulRecords.length;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columnCount = constraints.maxWidth >= 520 ? 4 : 2;
            final itemWidth = constraints.maxWidth / columnCount;
            final values = [
              _SummaryValue(label: '成功', value: '${successfulRecords.length}'),
              _SummaryValue(label: '失败', value: '$failedCount'),
              _SummaryValue(
                label: '平均速度',
                value: _formatRate(averageBytesPerSecond),
              ),
              _SummaryValue(
                label: '平均耗时',
                value: _formatDuration(averageDuration),
              ),
            ];
            return Wrap(
              runSpacing: 16,
              children: values
                  .map((value) => SizedBox(width: itemWidth, child: value))
                  .toList(),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF75849A)),
        ),
      ],
    );
  }
}

class _EmptyDiagnostics extends StatelessWidget {
  const _EmptyDiagnostics();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        '还没有图片传输记录\n完成一次图片收发后，这里会显示速度与稳定性数据。',
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _DiagnosticsLoadFailure extends StatelessWidget {
  const _DiagnosticsLoadFailure({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            const Text('暂时无法读取本机诊断记录'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.record});

  final ImageTransferMetric record;

  @override
  Widget build(BuildContext context) {
    final success = record.outcome == ImageTransferOutcome.success;
    final direction = record.direction == ImageTransferDirection.outgoing
        ? '发送'
        : '接收';
    final color = success ? const Color(0xFF2E7D5B) : const Color(0xFFD94A4A);
    final details = <String>[
      '${_formatBytes(record.inputByteLength)} → ${_formatBytes(record.transferByteLength)}',
      '${record.chunkCount} 个应用分片',
      _formatDuration(record.durationMilliseconds),
      if (success) '有效载荷 ${_formatRate(record.bytesPerSecond)}',
      if (record.retryCount > 0) '整图重试 ${record.retryCount}',
      if (record.batchRetryCount > 0) '批次重试 ${record.batchRetryCount}',
      if (record.progressStallCount > 0)
        '停顿 ${record.progressStallCount} 次（最长 ${_formatDuration(record.longestProgressStallMilliseconds)}）',
      if (record.concurrentAtStart) '并发开始',
      if (record.maxConcurrentTransfers > 1)
        '最高并发 ${record.maxConcurrentTransfers}',
      if (record.transportPath != ImageTransferTransportPath.unavailable)
        _transportLabel(record.transportPath),
      if (record.maximumBleFrameSize > 0)
        'BLE 帧上限 ${record.maximumBleFrameSize} B',
      if (record.transportPath == ImageTransferTransportPath.centralWrite)
        _connectionPriorityLabel(record.connectionPriority),
      if (!success && record.failureCategory != null)
        _failureLabel(record.failureCategory!),
    ];
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .12),
              foregroundColor: color,
              child: Icon(
                record.direction == ImageTransferDirection.outgoing
                    ? Icons.north_east_rounded
                    : Icons.south_west_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      Text(
                        '$direction · ${success ? '成功' : '失败'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      Text(
                        _formatTime(record.occurredAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF75849A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: details
                        .map(
                          (detail) => Text(
                            detail,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF55657A),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatRate(int bytesPerSecond) {
  if (bytesPerSecond <= 0) return '--';
  return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
}

String _formatDuration(int milliseconds) {
  if (milliseconds < 1000) return '${milliseconds}ms';
  return '${(milliseconds / 1000).toStringAsFixed(1)}秒';
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _failureLabel(ImageTransferFailureCategory category) =>
    switch (category) {
      ImageTransferFailureCategory.timeout => '超时',
      ImageTransferFailureCategory.integrity => '完整性校验失败',
      ImageTransferFailureCategory.transport => '链路失败',
      ImageTransferFailureCategory.validation => '数据格式无效',
      ImageTransferFailureCategory.storage => '本机保存失败',
      ImageTransferFailureCategory.cancelled => '传输已取消',
      ImageTransferFailureCategory.unknown => '未知故障',
    };

String _transportLabel(ImageTransferTransportPath path) => switch (path) {
  ImageTransferTransportPath.centralWrite => '中央端写入',
  ImageTransferTransportPath.peripheralNotification => '外围端通知',
  ImageTransferTransportPath.unavailable => '路径未建立',
};

String _connectionPriorityLabel(ImageTransferConnectionPriority priority) =>
    switch (priority) {
      ImageTransferConnectionPriority.notRequested => '未请求高性能优先级',
      ImageTransferConnectionPriority.highPerformanceAccepted => '已请求高性能优先级',
      ImageTransferConnectionPriority.requestFailed => '高性能优先级请求失败',
    };
